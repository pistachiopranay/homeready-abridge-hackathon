import ARKit
import RoomPlan
import SwiftUI
import Vision

// MARK: - Live on-device detection overlay
//
// Two Apple-native sources, no bundled models:
//  1. RoomPlan's live object recognition (sofa, table, bed, stove, stairs,
//     doors/openings…) — 3D oriented boxes projected into screen space.
//  2. Vision framework (Neural Engine) — person and pet rectangles on the
//     same ARKit frames RoomPlan is already producing.

struct DetectedBox: Identifiable, Equatable {
    let id: String
    let label: String
    let sub: String
    let rect: CGRect
    let color: Color
    let firm: Bool      // RoomPlan confidence >= medium → solid stroke
}

final class LiveDetector: NSObject, ObservableObject, RoomCaptureSessionDelegate {
    static let shared = LiveDetector()

    @Published var boxes: [DetectedBox] = []
    var viewSize: CGSize = .zero

    private weak var session: RoomCaptureSession?
    private var objects: [CapturedRoom.Object] = []
    private var doorways: [(surface: CapturedRoom.Surface, kind: String)] = []
    private var visionBoxes: [DetectedBox] = []
    private var renderTimer: Timer?
    private var lastVisionAt = Date.distantPast
    private var visionBusy = false
    private let visionQueue = DispatchQueue(label: "relay.live-vision", qos: .userInitiated)

    func start(session: RoomCaptureSession) {
        self.session = session
        session.delegate = self
        renderTimer?.invalidate()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0,
                                           repeats: true) { [weak self] _ in
            self?.render()
        }
    }

    func stop() {
        renderTimer?.invalidate()
        renderTimer = nil
        objects = []
        doorways = []
        visionBoxes = []
        boxes = []
    }

    // MARK: RoomCaptureSessionDelegate (live model, before final processing)

    func captureSession(_ session: RoomCaptureSession, didUpdate room: CapturedRoom) {
        objects = room.objects
        doorways = room.doors.map { ($0, "Door") }
            + room.openings.map { ($0, "Opening") }
    }

    // MARK: Projection loop

    private func render() {
        guard let frame = session?.arSession.currentFrame,
              viewSize.width > 1, viewSize.height > 1 else { return }
        let orientation = Self.interfaceOrientation
        var out: [DetectedBox] = []

        for o in objects {
            guard let rect = projectBox(center: o.transform,
                                        halfExtents: o.dimensions * 0.5,
                                        camera: frame.camera,
                                        orientation: orientation) else { continue }
            let name = Self.pretty(String(describing: o.category))
            out.append(DetectedBox(
                id: o.identifier.uuidString,
                label: name,
                sub: String(format: "%.1f × %.1f m", o.dimensions.x, o.dimensions.y),
                rect: rect,
                color: Self.color(forCategory: String(describing: o.category)),
                firm: o.confidence != .low))
        }

        for d in doorways {
            let s = d.surface
            guard let rect = projectBox(
                center: s.transform,
                halfExtents: simd_float3(s.dimensions.x * 0.5, s.dimensions.y * 0.5, 0.03),
                camera: frame.camera,
                orientation: orientation) else { continue }
            let inches = Double(s.dimensions.x) * 39.3701
            out.append(DetectedBox(
                id: s.identifier.uuidString,
                label: d.kind,
                sub: String(format: "%.0f in wide", inches),
                rect: rect,
                color: .indigo,
                firm: s.confidence != .low))
        }

        // Largest first so small boxes draw on top and stay readable.
        out.sort { $0.rect.width * $0.rect.height > $1.rect.width * $1.rect.height }
        out = Array(out.prefix(12))

        if !visionBusy, Date().timeIntervalSince(lastVisionAt) > 0.12 {
            runVision(on: frame, orientation: orientation)
        }
        // RoomPlan wins overlaps — it has real measured dimensions.
        let yolo = visionBoxes.filter { vb in
            !out.contains { Self.iou($0.rect, vb.rect) > 0.5 }
        }
        boxes = out + yolo
    }

    /// Projects an oriented 3D box into the view; nil when off-screen,
    /// partially behind the camera, or filling the whole frame.
    private func projectBox(center: simd_float4x4, halfExtents: simd_float3,
                            camera: ARCamera,
                            orientation: UIInterfaceOrientation) -> CGRect? {
        let worldToCamera = camera.transform.inverse
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude

        for sx in [Float(-1), 1] {
            for sy in [Float(-1), 1] {
                for sz in [Float(-1), 1] {
                    let local = simd_float4(sx * halfExtents.x, sy * halfExtents.y,
                                            sz * halfExtents.z, 1)
                    let world = center * local
                    guard (worldToCamera * world).z < -0.05 else { return nil }
                    let p = camera.projectPoint(simd_float3(world.x, world.y, world.z),
                                                orientation: orientation,
                                                viewportSize: viewSize)
                    minX = min(minX, p.x); maxX = max(maxX, p.x)
                    minY = min(minY, p.y); maxY = max(maxY, p.y)
                }
            }
        }

        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .intersection(CGRect(origin: .zero, size: viewSize).insetBy(dx: 4, dy: 4))
        guard !rect.isNull, rect.width > 30, rect.height > 30,
              rect.width < viewSize.width * 0.94 || rect.height < viewSize.height * 0.94
        else { return nil }
        return rect
    }

    // MARK: Core ML generic object detection (YOLOv3, Apple model gallery)

    /// Apple's gallery build ships the NMS pipeline inside the model, so Vision
    /// hands back labeled `VNRecognizedObjectObservation`s directly.
    private static let yoloModel: VNCoreMLModel? = {
        guard let url = Bundle.main.url(forResource: "YOLOv3Int8LUT",
                                        withExtension: "mlmodelc"),
              let ml = try? MLModel(contentsOf: url) else { return nil }
        return try? VNCoreMLModel(for: ml)
    }()

    private var nextTrackId = 0

    private func runVision(on frame: ARFrame, orientation: UIInterfaceOrientation) {
        guard let model = Self.yoloModel else { return }
        visionBusy = true
        lastVisionAt = Date()
        let buffer = frame.capturedImage
        let viewSize = self.viewSize
        let cgOrientation = Self.cgOrientation(for: orientation)

        visionQueue.async { [weak self] in
            let request = VNCoreMLRequest(model: model)
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer,
                                                orientation: cgOrientation)
            try? handler.perform([request])

            // Boxes are normalized (origin bottom-left) in the upright image;
            // map through the same aspect-fill the camera view uses.
            let bufW = CGFloat(CVPixelBufferGetWidth(buffer))
            let bufH = CGFloat(CVPixelBufferGetHeight(buffer))
            let rotated = cgOrientation == .right || cgOrientation == .left
            let imgW = rotated ? bufH : bufW
            let imgH = rotated ? bufW : bufH
            let scale = max(viewSize.width / imgW, viewSize.height / imgH)
            let offX = (viewSize.width - imgW * scale) / 2
            let offY = (viewSize.height - imgH * scale) / 2
            func viewRect(_ bb: CGRect) -> CGRect {
                CGRect(x: bb.minX * imgW * scale + offX,
                       y: (1 - bb.maxY) * imgH * scale + offY,
                       width: bb.width * imgW * scale,
                       height: bb.height * imgH * scale)
            }

            var found: [DetectedBox] = []
            let results = (request.results as? [VNRecognizedObjectObservation]) ?? []
            for obs in results {
                guard let top = obs.labels.first, top.confidence > 0.4 else { continue }
                let rect = viewRect(obs.boundingBox)
                guard rect.width > 24, rect.height > 24 else { continue }
                found.append(DetectedBox(
                    id: "",     // assigned by the tracker on the main thread
                    label: top.identifier.capitalized,
                    sub: String(format: "%.0f%%", top.confidence * 100),
                    rect: rect,
                    color: top.identifier == "person" ? .pink : .cyan,
                    firm: true))
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.visionBoxes = self.tracked(found)
                self.visionBusy = false
            }
        }
    }

    /// Reuses a previous box's id when the same label overlaps it, so SwiftUI
    /// animates boxes gliding between frames instead of blinking.
    private func tracked(_ found: [DetectedBox]) -> [DetectedBox] {
        var previous = visionBoxes
        return found.map { box in
            if let i = previous.firstIndex(where: {
                $0.label == box.label && Self.iou($0.rect, box.rect) > 0.3 }) {
                let id = previous.remove(at: i).id
                return DetectedBox(id: id, label: box.label, sub: box.sub,
                                   rect: box.rect, color: box.color, firm: box.firm)
            }
            nextTrackId += 1
            return DetectedBox(id: "yolo-\(nextTrackId)", label: box.label,
                               sub: box.sub, rect: box.rect,
                               color: box.color, firm: box.firm)
        }
    }

    private static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }

    // MARK: Helpers

    private static var interfaceOrientation: UIInterfaceOrientation {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .interfaceOrientation ?? .portrait
    }

    private static func cgOrientation(for o: UIInterfaceOrientation)
        -> CGImagePropertyOrientation {
        switch o {
        case .portrait: return .right
        case .portraitUpsideDown: return .left
        case .landscapeLeft: return .down
        default: return .up
        }
    }

    private static func pretty(_ camel: String) -> String {
        var out = ""
        for ch in camel {
            if ch.isUppercase { out.append(" ") }
            out.append(ch)
        }
        return out.capitalized
    }

    private static func color(forCategory raw: String) -> Color {
        // Mobility-relevant hazards pop; everything else stays cool teal.
        ["stairs", "bathtub", "stove", "fireplace"].contains(raw) ? .orange : .teal
    }
}

// MARK: - Overlay view

struct DetectionOverlayView: View {
    @ObservedObject private var detector = LiveDetector.shared

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                ForEach(detector.boxes) { box in
                    BoundingBoxView(box: box)
                }
                if !detector.boxes.isEmpty {
                    Label("on-device detection · \(detector.boxes.count)",
                          systemImage: "viewfinder")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.leading, 14)
                        .padding(.bottom, 110)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
            .onAppear { detector.viewSize = geo.size }
            .onChange(of: geo.size) { detector.viewSize = $0 }
        }
        .allowsHitTesting(false)
    }
}

private struct BoundingBoxView: View {
    let box: DetectedBox

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .stroke(box.color.opacity(0.95),
                    style: StrokeStyle(lineWidth: 2.5,
                                       dash: box.firm ? [] : [7, 5]))
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(box.color.opacity(0.05)))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 5) {
                    Text(box.label).font(.caption.bold())
                    Text(box.sub).font(.caption2).opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(box.color.opacity(0.88), in: Capsule())
                .offset(y: -24)
                .fixedSize()
            }
            .frame(width: box.rect.width, height: box.rect.height)
            .position(x: box.rect.midX, y: box.rect.midY)
            .animation(.easeOut(duration: 0.18), value: box.rect)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
