import SwiftUI

struct RunSummary: Identifiable {
    let id: String
    let frames: Int
    let findings: Int
    let critical: Int
    let escalations: Int
    let blocked: Int
    let hasFloorplan: Bool
    let rooms: [String]
}

/// Browse past walkthroughs: floor plans rendered by the backend + key counts.
struct PastRunsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var runs: [RunSummary] = []
    @State private var selected: RunSummary?

    var body: some View {
        NavigationStack {
            List(runs) { r in
                Button {
                    selected = r
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.id).font(.headline.monospaced())
                            Text("\(r.frames) frames · \(r.findings) findings "
                                 + "(\(r.critical) critical) · \(r.escalations) escalations")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !r.rooms.isEmpty {
                                Text("scanned: " + r.rooms.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if r.blocked > 0 {
                            Text("PLAN BLOCKED")
                                .font(.caption2.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(.red)
                        }
                        if r.hasFloorplan {
                            Image(systemName: "square.split.bottomrightquarter")
                                .foregroundStyle(.teal)
                        }
                    }
                }
                .tint(.primary)
            }
            .navigationTitle("Past walkthroughs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { r in
                RunDetailView(run: r)
            }
            .onAppear {
                BackendClient.shared.fetchRuns { items in
                    runs = items.map {
                        RunSummary(id: $0["run_id"] as? String ?? "?",
                                   frames: $0["n_frames"] as? Int ?? 0,
                                   findings: $0["n_findings"] as? Int ?? 0,
                                   critical: $0["n_critical"] as? Int ?? 0,
                                   escalations: $0["n_escalations"] as? Int ?? 0,
                                   blocked: $0["n_blocked"] as? Int ?? 0,
                                   hasFloorplan: $0["has_floorplan"] as? Bool ?? false,
                                   rooms: $0["rooms"] as? [String] ?? [])
                    }
                }
            }
        }
    }
}

extension RunSummary: Equatable {}

struct RunDetailView: View {
    let run: RunSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(run.id).font(.title3.monospaced().bold())
                if run.blocked > 0 {
                    Label("Care plan blocked — see escalations in the report",
                          systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }
                Text("\(run.findings) findings (\(run.critical) critical) · "
                     + "\(run.escalations) escalations routed")
                    .foregroundStyle(.secondary)

                if run.hasFloorplan {
                    Text("Floor plans").font(.headline)
                    AsyncImage(url: BackendClient.shared.baseURL
                        .appendingPathComponent("floorplan")
                        .appending(queryItems: [.init(name: "run", value: run.id)])) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFit()
                        case .failure:
                            Text("floor plan unavailable").foregroundStyle(.secondary)
                        default:
                            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        }
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("No LiDAR floor plan captured on this run.")
                        .foregroundStyle(.secondary)
                }

                Text("Full clinician report: \(BackendClient.shared.baseURL.absoluteString)/report?run=\(run.id)")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
    }
}
