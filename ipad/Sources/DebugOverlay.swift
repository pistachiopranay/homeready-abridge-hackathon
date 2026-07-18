import SwiftUI

/// Toggleable backend-state peek for the operator: what the server has seen,
/// heard, and measured. Hidden behind a small ladybug button — invisible to the
/// demo unless you want it.
struct DebugOverlay: View {
    @State private var open = false
    @State private var state: [String: Any] = [:]
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Button {
                open.toggle()
            } label: {
                Image(systemName: open ? "ladybug.fill" : "ladybug")
                    .font(.title3)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .tint(.secondary)

            if open {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: open)
        .onReceive(timer) { _ in
            guard open else { return }
            BackendClient.shared.fetchState { state = $0 }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var panel: some View {
        let events = (state["events"] as? [String]) ?? []
        let meas = (state["measurements"] as? [[String: Any]]) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            line("run", state["run_id"] as? String ?? "—")
            line("frames", "\(state["n_frames"] as? Int ?? 0) uploaded")
            line("findings", "\(state["n_findings"] as? Int ?? 0) graded (deep pass)")
            line("room", state["current_room"] as? String ?? "—")
            if !meas.isEmpty {
                line("lidar", meas.compactMap { $0["text"] as? String }
                                  .joined(separator: "\n"))
            }
            Divider()
            Text("last callouts").foregroundStyle(.secondary)
            ForEach(events.suffix(4).reversed(), id: \.self) { e in
                Text("• \(e)").lineLimit(2)
            }
        }
        .font(.caption.monospaced())
        .padding(12)
        .frame(width: 380, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.white)
    }
}
