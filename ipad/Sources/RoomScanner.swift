import ARKit
import RoomPlan
import SwiftUI

/// Wraps RoomCaptureView. Also the frame source: every `frameInterval` seconds
/// the current ARFrame is downscaled to JPEG and shipped to the backend, so no
/// second camera session competes with RoomPlan.
final class RoomScanner: NSObject, ObservableObject, RoomCaptureViewDelegate {
    static let shared = RoomScanner()

    @Published var isScanning = false
    @Published var lastStatus = ""

    let captureView = RoomCaptureView(frame: .zero)
    var currentRoom = "entry"

    private var frameTimer: Timer?
    private let frameInterval: TimeInterval = 2.5
    private let ciContext = CIContext()

    override init() {
        super.init()
        captureView.delegate = self
    }

    // RoomCaptureViewDelegate inherits NSCoding (state restoration we don't use)
    func encode(with coder: NSCoder) {}
    required init?(coder: NSCoder) { return nil }

    func startRoom(named room: String) {
        currentRoom = room
        let config = RoomCaptureSession.Configuration()
        captureView.captureSession.run(configuration: config)
        isScanning = true
        BackendClient.shared.send(event: "Caregiver started scanning the \(room).")
        frameTimer = Timer.scheduledTimer(withTimeInterval: frameInterval,
                                          repeats: true) { [weak self] _ in
            self?.captureAndUploadFrame()
        }
    }

    func finishRoom() {
        frameTimer?.invalidate()
        frameTimer = nil
        captureView.captureSession.stop()   // triggers processing → didPresent
        isScanning = false
    }

    private func captureAndUploadFrame() {
        guard let frame = captureView.captureSession.arSession.currentFrame else { return }
        let ci = CIImage(cvPixelBuffer: frame.capturedImage)
        let scale = 512.0 / max(ci.extent.width, ci.extent.height)
        let scaled = ci.transformed(by: .init(scaleX: scale, y: scale))
        guard let jpeg = ciContext.jpegRepresentation(
            of: scaled, colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [kCGImageDestinationLossyCompressionQuality
                        as CIImageRepresentationOption: 0.6]) else { return }
        BackendClient.shared.send(frame: jpeg, room: currentRoom)
    }

    // MARK: RoomCaptureViewDelegate

    func captureView(shouldPresent roomDataForProcessing: CapturedRoomData,
                     error: Error?) -> Bool { true }

    func captureView(didPresent processedResult: CapturedRoom, error: Error?) {
        guard error == nil else {
            DispatchQueue.main.async { self.lastStatus = "Scan failed — camera only" }
            return
        }
        let inch = { (m: Float) in Double(m) * 39.3701 }
        let doors = processedResult.doors.map { ["width_m": Double($0.dimensions.x)] }
        let openings = processedResult.openings.map { ["width_m": Double($0.dimensions.x)] }
        let area = processedResult.floors
            .map { Double($0.dimensions.x * $0.dimensions.y) }.reduce(0, +)

        var payload: [String: Any] = ["room": currentRoom]
        if !doors.isEmpty { payload["doors"] = doors }
        if !openings.isEmpty { payload["openings"] = openings }
        if area > 0 { payload["floor_area_m2"] = area }
        BackendClient.shared.send(roomPlan: payload)

        let widths = (processedResult.doors + processedResult.openings)
            .map { String(format: "%.0fin", inch($0.dimensions.x)) }
            .joined(separator: ", ")
        DispatchQueue.main.async {
            self.lastStatus = widths.isEmpty
                ? "\(self.currentRoom) scanned"
                : "\(self.currentRoom): door/opening widths \(widths)"
        }
    }
}

struct RoomCaptureViewRep: UIViewRepresentable {
    func makeUIView(context: Context) -> RoomCaptureView { RoomScanner.shared.captureView }
    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}
}
