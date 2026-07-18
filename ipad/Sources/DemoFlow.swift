import SwiftUI

// MARK: - Patient-side chrome
// The clinician side is teal + clinical; everything the patient/family sees is
// warm indigo with a persistent top bar so the audience always knows whose
// screen they're looking at.

enum PatientTheme {
    static let accent = Color.indigo
    static let barGradient = LinearGradient(
        colors: [Color.indigo, Color.purple.opacity(0.85)],
        startPoint: .leading, endPoint: .trailing)
}

struct PatientChrome<Content: View>: View {
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                Text("Relay Home").font(.headline.bold())
                Text("·").opacity(0.6)
                Text(subtitle).font(.subheadline)
                Spacer()
                Image(systemName: "heart.fill").opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(PatientTheme.barGradient)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.indigo.opacity(0.04))
        }
        .tint(PatientTheme.accent)
    }
}

// MARK: - Note markdown (faithful to the Abridge-style note)

/// Block-level renderer for the note's actual structure:
/// `**Section:** text` paragraphs, `### ` headings, `- ` bullets.
struct NoteMarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    private enum Block {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    private var blocks: [Block] {
        markdown.components(separatedBy: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if line.hasPrefix("### ") {
                return .heading(String(line.dropFirst(4)))
            }
            if line.hasPrefix("- ") {
                return .bullet(String(line.dropFirst(2)))
            }
            if line.hasPrefix("* ") {
                return .bullet(String(line.dropFirst(2)))
            }
            return .paragraph(line)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let text):
            Text(inline(text))
                .font(.headline)
                .padding(.top, 8)
        case .bullet(let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•").font(.callout)
                Text(inline(text)).font(.callout)
            }
            .padding(.leading, 8)
        case .paragraph(let text):
            Text(inline(text))
                .font(.callout)
                .lineSpacing(2)
        }
    }
}

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
        .tint(.teal)
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

                NoteMarkdownView(markdown: chart["note"] as? String ?? "Loading note…")
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))

                planCard
            }
            .padding(24)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pre-discharge — home setup needed", systemImage: "house.badge.clock")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("The plan requires a formal pre-discharge assessment of home setup. "
                 + "That can't be verified from this chair.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                handedOff = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onHandoff() }
            } label: {
                Label(handedOff ? "Relay accepted — notifying Monica…"
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
    @State private var sentToHome = false
    @State private var scheduled = false

    var body: some View {
        PatientChrome(subtitle: "for Monica and her family") {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "message.badge.filled.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(PatientTheme.accent)
                Text("To: Monica Hilpert")
                    .font(.title3.bold())
                Text("from Riley · your care team")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(message.isEmpty ? "…" : message)
                    .font(.body)
                    .padding(20)
                    .frame(maxWidth: 560, alignment: .leading)
                    .background(PatientTheme.accent.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 20))
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                VStack(spacing: 12) {
                    Button {
                        sentToHome = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            onStartLive()
                        }
                    } label: {
                        Label(sentToHome
                              ? "Sent to Emma (niece) — opening on her device…"
                              : "Send to anyone at home",
                              systemImage: sentToHome ? "checkmark.circle.fill"
                                                      : "paperplane.fill")
                            .font(.headline)
                            .padding(.horizontal, 24).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(sentToHome ? .green : PatientTheme.accent)
                    .disabled(sentToHome)

                    Button {
                        scheduled = true
                    } label: {
                        Label(scheduled
                              ? "Request sent — the scheduling team will call you"
                              : "Schedule an in-person home visit",
                              systemImage: scheduled ? "checkmark.circle"
                                                     : "calendar.badge.plus")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .disabled(scheduled || sentToHome)

                    Button {
                        onStartDemo()
                    } label: {
                        Label("replay recorded walk-through",
                              systemImage: "play.rectangle")
                            .font(.caption)
                    }
                    .tint(.secondary)
                }
                Spacer()
            }
            .padding()
        }
        .onAppear {
            BackendClient.shared.fetchChart {
                message = $0["handoff_message"] as? String ?? ""
                withAnimation(.spring(duration: 0.6)) { appeared = true }
            }
        }
    }
}

// MARK: - Thanks (Act 4) — never blocks; report finalizes in the background

struct ThanksView: View {
    let onContinue: () -> Void

    var body: some View {
        PatientChrome(subtitle: "walk-through complete") {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
                Text("Thank you so much!")
                    .font(.largeTitle.bold())
                Text("Everything we saw and heard is being prepared\ninto a report for Monica's care team.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("You're all set — the care team takes it from here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    onContinue()
                } label: {
                    Label("Switch to care-team view", systemImage: "stethoscope")
                        .font(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                Spacer()
            }
            .padding()
        }
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
    @State private var selectedRun: String?     // nil = latest finished
    @State private var sampleRuns: [String] = []
    @State private var blocked = 0
    @State private var allApproved = false
    @State private var clearing = false
    private let timer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Care-team review", systemImage: "tray.full.fill")
                        .font(.title2.bold())
                    Spacer()
                    Menu {
                        Button("Latest walkthrough") { selectedRun = nil; refresh() }
                        ForEach(sampleRuns, id: \.self) { r in
                            Button(r) { selectedRun = r; refresh() }
                        }
                    } label: {
                        Label(selectedRun ?? "latest", systemImage: "clock.arrow.circlepath")
                            .font(.footnote.monospaced())
                    }
                }

                if approvals.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Report finalizing — findings land as they're graded. "
                             + "Pick a sample run above to review a completed one now.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                }

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
                    .id(runId)
                }

                if !approvals.isEmpty {
                    Text("Drafted by Relay — awaiting clinician approval")
                        .font(.headline)
                }

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
                        BackendClient.shared.clearDischarge(run: selectedRun) {
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
        .tint(.teal)
        .onAppear {
            refresh()
            BackendClient.shared.fetchRuns { items in
                sampleRuns = items.compactMap { $0["run_id"] as? String }
            }
        }
        .onReceive(timer) { _ in
            if approvals.isEmpty || !allApproved { refresh() }
        }
    }

    private func refresh() {
        BackendClient.shared.fetchApprovals(run: selectedRun) { obj in
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
        BackendClient.shared.approve(id: a.id, run: selectedRun) { refresh() }
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
