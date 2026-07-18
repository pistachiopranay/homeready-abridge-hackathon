import SwiftUI

// MARK: - Clinician portal (Act 1)

struct ClinicianPortalView: View {
    let onHandoff: () -> Void
    @State private var chart: [String: Any] = [:]
    @State private var handedOff = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            notePane
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            BackendClient.shared.fetchChart { chart = $0 }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Clinician Portal", systemImage: "stethoscope")
                .font(.headline)
                .padding()
            Divider()
            patientRow(name: "Hilpert, Monica", detail: "76F · SNF rehab · DC Friday",
                       active: true)
            patientRow(name: "Bergstrom, Elsa", detail: "82F · CHF follow-up",
                       active: false)
            patientRow(name: "Okafor, James", detail: "61M · post-op wound check",
                       active: false)
            Spacer()
            Text("Ambient notes by Abridge\nFollow-through by Relay")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding()
        }
        .frame(width: 260)
        .background(.background)
    }

    private func patientRow(name: String, detail: String, active: Bool) -> some View {
        HStack {
            Circle().fill(active ? .teal : .gray.opacity(0.3))
                .frame(width: 34, height: 34)
                .overlay(Text(String(name.prefix(1))).foregroundStyle(.white).bold())
            VStack(alignment: .leading) {
                Text(name).font(.subheadline.weight(active ? .bold : .regular))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(active ? Color.teal.opacity(0.08) : .clear)
    }

    private var notePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monica Hilpert, 76F")
                        .font(.title2.bold())
                    Text(chart["visit_title"] as? String ?? "")
                        .foregroundStyle(.secondary)
                    Text("Encounter note · generated from ambient conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(noteParagraphs, id: \.self) { para in
                    Text((try? AttributedString(
                        markdown: para,
                        options: .init(interpretedSyntax:
                            .inlineOnlyPreservingWhitespace)))
                        ?? AttributedString(para))
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                planCard
            }
            .padding(24)
            .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity)
    }

    private var noteParagraphs: [String] {
        (chart["note"] as? String ?? "Loading note…")
            .components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pre-discharge — home setup needed", systemImage: "house.badge.clock")
                .font(.headline)
                .foregroundStyle(.orange)
            ForEach(chart["plan_items"] as? [String] ?? [], id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill").font(.system(size: 5))
                        .padding(.top, 6)
                    Text(item).font(.subheadline)
                }
            }
            Text("The last item can't be verified from this chair.")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)

            Button {
                handedOff = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onHandoff() }
            } label: {
                Label(handedOff ? "Relay accepted — notifying patient…"
                                : "Hand over to Relay",
                      systemImage: handedOff ? "checkmark.circle.fill"
                                             : "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(handedOff ? .green : .teal)
            .disabled(handedOff)
        }
        .padding(18)
        .background(.orange.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.orange.opacity(0.4)))
    }
}

// MARK: - Patient message (Act 2)

struct PatientMessageView: View {
    let onStartLive: () -> Void
    let onStartDemo: () -> Void
    @State private var message = ""
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: "message.badge.filled.fill")
                .font(.system(size: 44))
                .foregroundStyle(.teal)
            Text("New message from Monica's care team")
                .font(.title3.bold())

            Text(message.isEmpty ? "…" : message)
                .font(.body)
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .background(.teal.opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 20))
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            VStack(spacing: 12) {
                Button {
                    onStartLive()
                } label: {
                    Label("I'm here with the iPad — start the walk-through",
                          systemImage: "figure.walk")
                        .font(.headline)
                        .padding(.horizontal, 24).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)

                Button("Schedule a home visit instead") {}
                    .font(.subheadline)
                    .tint(.secondary)

                Button {
                    onStartDemo()
                } label: {
                    Label("replay recorded walk-through", systemImage: "play.rectangle")
                        .font(.caption)
                }
                .tint(.secondary)
            }
            Spacer()
        }
        .padding()
        .onAppear {
            BackendClient.shared.fetchChart {
                message = $0["handoff_message"] as? String ?? ""
                withAnimation(.spring(duration: 0.6)) { appeared = true }
            }
        }
    }
}

// MARK: - Thanks / generating (Act 4)

struct ThanksView: View {
    let reportReady: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: reportReady ? "checkmark.seal.fill" : "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(reportReady ? .green : .teal)
            Text("Thank you so much!")
                .font(.largeTitle.bold())
            if reportReady {
                Text("Monica's report has been shared with her care team.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Button {
                    onContinue()
                } label: {
                    Label("Care team view", systemImage: "stethoscope")
                        .font(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
            } else {
                Text("Reviewing everything we saw and heard,\npreparing a report for Monica's care team…")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                ProgressView().controlSize(.large)
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Care-team review (Act 5)

struct Approval: Identifiable {
    let id: String
    let kind: String
    let title: String
    let detail: String
    var status: String
}

struct CareTeamView: View {
    let onCleared: () -> Void
    @State private var approvals: [Approval] = []
    @State private var runId: String?
    @State private var blocked = 0
    @State private var allApproved = false
    @State private var clearing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Care-team review — walkthrough report received",
                      systemImage: "tray.full.fill")
                    .font(.title2.bold())

                if blocked > 0 {
                    Label("The current discharge plan will not work: "
                          + "\(blocked) care-plan obligation(s) BLOCKED by the home.",
                          systemImage: "exclamationmark.octagon.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 12))
                }

                if let runId {
                    AsyncImage(url: BackendClient.shared.baseURL
                        .appendingPathComponent("floorplan")
                        .appending(queryItems: [.init(name: "run", value: runId)])) { ph in
                        if case .success(let img) = ph {
                            img.resizable().scaledToFit().frame(maxHeight: 260)
                        }
                    }
                }

                Text("Drafted by Relay — awaiting clinician approval")
                    .font(.headline)

                ForEach(approvals) { a in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.kind.uppercased())
                                .font(.caption2.bold())
                                .foregroundStyle(a.kind == "clinical" ? .red :
                                                 a.kind == "dme" ? .teal : .orange)
                            Text(a.title).font(.subheadline.bold())
                            Text(a.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if a.status == "approved" {
                            Label("Approved", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline.bold())
                        } else {
                            Button("Approve") { approve(a) }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                        }
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                }

                if allApproved {
                    Button {
                        clearing = true
                        BackendClient.shared.clearDischarge {
                            onCleared()
                        }
                    } label: {
                        Label(clearing ? "Updating chart…"
                              : "Remediations verified — update chart & clear discharge",
                              systemImage: "checkmark.shield.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(clearing)
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
        }
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .onAppear(perform: refresh)
    }

    private func refresh() {
        BackendClient.shared.fetchApprovals { obj in
            runId = obj["run_id"] as? String
            blocked = obj["n_blocked"] as? Int ?? 0
            approvals = (obj["approvals"] as? [[String: Any]] ?? []).map {
                Approval(id: $0["id"] as? String ?? "",
                         kind: $0["kind"] as? String ?? "",
                         title: $0["title"] as? String ?? "",
                         detail: $0["detail"] as? String ?? "",
                         status: $0["status"] as? String ?? "pending")
            }
            allApproved = !approvals.isEmpty
                && approvals.allSatisfy { $0.status == "approved" }
        }
    }

    private func approve(_ a: Approval) {
        BackendClient.shared.approve(id: a.id) { refresh() }
    }
}

// MARK: - Discharged (finale)

struct DischargedView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72))
                .foregroundStyle(.green)
            Text("Chart updated")
                .font(.largeTitle.bold())
            Text("Home readiness verified · barriers remediated ·\nFHIR write-back complete")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Monica is cleared to go home Friday.")
                .font(.title2.bold())
                .foregroundStyle(.teal)
            Text("Abridge captures the encounter. Relay carries the care forward.")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Button("Done") { onDone() }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            Spacer()
        }
        .padding()
    }
}
