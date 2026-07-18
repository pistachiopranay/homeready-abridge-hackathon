import SwiftUI
import WebKit

// MARK: - Design tokens (baseline: Abridge — warm paper, warm ink, red-orange)

enum RelayTheme {
    static let brand = Color(red: 0.918, green: 0.173, blue: 0.0)          // #EA2C00
    static let ink = Color(red: 0.078, green: 0.075, blue: 0.071)          // #141312
    static let inkSecondary = Color(red: 0.427, green: 0.392, blue: 0.353) // #6D645A
    static let paper = Color(red: 0.984, green: 0.976, blue: 0.965)        // #FBF9F6
    static let paper2 = Color(red: 0.969, green: 0.949, blue: 0.929)       // #F7F2ED
    static let hairline = Color(red: 0.655, green: 0.596, blue: 0.541).opacity(0.35)
    static let blue = Color(red: 0.463, green: 0.659, blue: 0.957)         // #76A8F4
    static let blueDeep = Color(red: 0.243, green: 0.427, blue: 0.710)     // #3E6DB5
    static let green = Color(red: 0.118, green: 0.478, blue: 0.275)        // #1E7A46
    static let amber = Color(red: 0.710, green: 0.278, blue: 0.031)        // #B54708
    static let red = Color(red: 0.706, green: 0.137, blue: 0.094)          // #B42318
}

/// The server-rendered report, embedded (embed=1 hides its header/footer)
struct ReportWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        wv.isOpaque = false
        wv.backgroundColor = UIColor(RelayTheme.paper)
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        if wv.url != url { wv.load(URLRequest(url: url)) }
    }
}

// MARK: - Patient-side chrome
// The clinician side is teal + clinical; everything the patient/family sees is
// warm indigo with a persistent top bar so the audience always knows whose
// screen they're looking at.

enum PatientTheme {
    static let accent = RelayTheme.blueDeep
    static let barGradient = LinearGradient(
        colors: [RelayTheme.blueDeep, RelayTheme.blue],
        startPoint: .leading, endPoint: .trailing)
}

struct PatientChrome<Content: View>: View {
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                Text("HomeReady").font(.headline.bold())
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
                .background(RelayTheme.blue.opacity(0.06))
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
    var onOpenSample: ((String) -> Void)? = nil
    var onReset: (() -> Void)? = nil
    @State private var chart: [String: Any] = [:]
    @State private var handedOff = false
    @State private var patients: [[String: Any]] = []
    @State private var selectedPatient = "monica"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            notePane
        }
        .background(RelayTheme.paper2)
        .tint(RelayTheme.brand)
        .onAppear {
            loadChart()
            BackendClient.shared.fetchPatients { patients = $0 }
        }
    }

    private func loadChart() {
        BackendClient.shared.fetchChart(patient: selectedPatient) { chart = $0 }
    }

    private var relayStatus: [String: Any]? { chart["relay_status"] as? [String: Any] }
    private var isSample: Bool { chart["sample"] as? Bool == true }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Clinician Portal", systemImage: "stethoscope")
                .font(.headline)
                .padding()
            Divider()
            ForEach(Array(patients.enumerated()), id: \.offset) { _, p in
                let pid = p["id"] as? String ?? ""
                let disabled = p["disabled"] as? Bool == true
                Button {
                    guard !disabled else { return }
                    selectedPatient = pid
                    chart = [:]
                    loadChart()
                } label: {
                    patientRow(name: p["name"] as? String ?? "",
                               detail: p["detail"] as? String ?? "",
                               active: pid == selectedPatient)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .opacity(disabled ? 0.5 : 1)
            }
            Spacer()
            Text("Ambient notes by Abridge\nHome verification by HomeReady")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding()
            if let onReset {
                Button {
                    onReset()
                } label: {
                    Label("Reset demo", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .tint(.secondary)
                .padding([.horizontal, .bottom])
            }
        }
        .frame(width: 260)
        .background(.background)
    }

    private func patientRow(name: String, detail: String, active: Bool) -> some View {
        HStack {
            Circle().fill(active ? RelayTheme.brand : RelayTheme.hairline)
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
        .background(active ? RelayTheme.brand.opacity(0.07) : .clear)
    }

    private var notePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(chart["name"] as? String ?? "…"), "
                         + "\(chart["age"] as? Int ?? 0)\(chart["sex"] as? String ?? "")")
                        .font(.title2.bold())
                    Text(chart["visit_title"] as? String ?? "")
                        .foregroundStyle(.secondary)
                    Text("Encounter note · generated from ambient conversation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if relayStatus != nil { relayCard }

                if isSample, let runId = relayStatus?["run_id"] as? String {
                    Button {
                        onOpenSample?(runId)
                    } label: {
                        Label("Open care-team review & report",
                              systemImage: "tray.full.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RelayTheme.brand)
                }

                NoteMarkdownView(markdown: chart["note"] as? String ?? "Loading note…")
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))

                if !isSample { planCard }
            }
            .padding(24)
            .frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var relayCard: some View {
        if relayStatus?["processing"] as? Bool == true {
            processingCard
        } else {
            statusCard
        }
    }

    private var processingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("HomeReady · walk-through in progress")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Report is being generated — findings land as they're graded. "
                     + "Run \(relayStatus?["run_id"] as? String ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(.orange.opacity(0.4)))
    }

    private var statusCard: some View {
        let rs = relayStatus ?? [:]
        let cleared = (rs["discharge_state"] as? String ?? "in_review") == "cleared"
        let blocked = rs["n_blocked"] as? Int ?? 0
        let runId = rs["run_id"] as? String
        let nFindings = rs["n_findings"] as? Int ?? 0
        let nCritical = rs["n_critical"] as? Int ?? 0

        let title: String = cleared
            ? "HomeReady — VERIFIED, cleared for discharge"
            : (blocked > 0 ? "HomeReady — discharge plan BLOCKED by the home"
                           : "HomeReady — assessment on file")
        let icon: String = cleared ? "checkmark.seal.fill"
            : (blocked > 0 ? "exclamationmark.octagon.fill" : "house.and.flag")
        let color: Color = cleared ? RelayTheme.green : (blocked > 0 ? RelayTheme.red : RelayTheme.blueDeep)
        let tail: String = cleared
            ? "barriers remediated & verified · FHIR write-back complete"
            : "\(blocked) obligation(s) blocked"
        let summary = "Walk-through \(runId ?? "—") · \(nFindings) findings "
            + "(\(nCritical) critical) · " + tail

        return VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(color)

            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if rs["has_floorplan"] as? Bool == true, let runId {
                AsyncImage(url: BackendClient.shared.baseURL
                    .appendingPathComponent("floorplan")
                    .appending(queryItems: [.init(name: "run", value: runId)])) { ph in
                    if case .success(let img) = ph {
                        img.resizable().scaledToFit().frame(maxHeight: 220)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(color.opacity(0.4)))
    }

    private var planCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pre-discharge — home setup needed", systemImage: "house.badge.clock")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Monica's clinical team believes she may be ready to go home. "
                 + "HomeReady answers the question her chart cannot: "
                 + "is her home ready for her?")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                handedOff = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { onHandoff() }
            } label: {
                Label(handedOff ? "HomeReady accepted — notifying Monica…"
                                : "Hand over to HomeReady",
                      systemImage: handedOff ? "checkmark.circle.fill"
                                             : "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(handedOff ? RelayTheme.green : RelayTheme.brand)
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
                .tint(RelayTheme.brand)
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
    var initialRun: String? = nil
    var onBack: (() -> Void)? = nil
    @State private var approvals: [Approval] = []
    @State private var runId: String?
    @State private var selectedRun: String?
    @State private var sampleRuns: [String] = []
    @State private var blocked = 0
    @State private var nFrames = 0
    @State private var allApproved = false
    @State private var clearing = false
    private let timer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    private var approvedCount: Int {
        approvals.filter { $0.status == "approved" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                actionRail
                    .frame(width: 430)
                Divider()
                reportPane
            }
        }
        .background(RelayTheme.paper)
        .tint(RelayTheme.brand)
        .onAppear {
            if selectedRun == nil, let initialRun {
                selectedRun = initialRun
            }
            refresh()
            BackendClient.shared.fetchRuns { items in
                sampleRuns = items.compactMap { $0["run_id"] as? String }
            }
        }
        .onReceive(timer) { _ in
            if approvals.isEmpty || !allApproved { refresh() }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 14) {
            if let onBack {
                Button { onBack() } label: {
                    Label("Chart", systemImage: "chevron.left")
                        .font(.subheadline.bold())
                }
                .buttonStyle(.bordered)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Care-team review")
                    .font(.title3.bold())
                    .foregroundStyle(RelayTheme.ink)
                Text("walk-through \(runId ?? "…") · drafted by HomeReady, decided by clinicians")
                    .font(.caption)
                    .foregroundStyle(RelayTheme.inkSecondary)
            }
            Spacer()
            if !approvals.isEmpty {
                HStack(spacing: 8) {
                    ProgressView(value: Double(approvedCount),
                                 total: Double(max(approvals.count, 1)))
                        .frame(width: 90)
                    Text("\(approvedCount)/\(approvals.count) approved")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(RelayTheme.inkSecondary)
                }
            }
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
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.white)
    }

    // MARK: left rail — what the clinician acts on

    private var actionRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if approvals.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Report finalizing — findings land as they're graded. "
                             + "Pick a run from the menu to review a completed one now.")
                            .font(.footnote)
                            .foregroundStyle(RelayTheme.inkSecondary)
                    }
                    .padding(14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }

                if blocked > 0 {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("The discharge plan will not work as written")
                                .font(.subheadline.bold())
                            Text("\(blocked) care-plan obligation(s) blocked by the home")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RelayTheme.red, in: RoundedRectangle(cornerRadius: 12))
                }

                if !approvals.isEmpty {
                    sectionCaption("Actions drafted by HomeReady")
                }
                ForEach(approvals) { a in
                    approvalCard(a)
                }

                if allApproved {
                    Button {
                        clearing = true
                        BackendClient.shared.clearDischarge(run: selectedRun) {
                            onCleared()
                        }
                    } label: {
                        Label(clearing ? "Updating chart…"
                              : "Remediations verified — clear discharge",
                              systemImage: "checkmark.shield.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RelayTheme.green)
                    .disabled(clearing)
                }

                if let runId {
                    sectionCaption("Floor plan · LiDAR")
                    AsyncImage(url: floorplanURL(runId)) { ph in
                        if case .success(let img) = ph {
                            img.resizable().scaledToFit()
                        } else {
                            RelayTheme.paper2.frame(height: 120)
                        }
                    }
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(RelayTheme.hairline))
                    .id("fp-\(runId)")
                }

                if nFrames > 0, let runId {
                    sectionCaption("Walkthrough evidence · \(nFrames) frames")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(frameIndices, id: \.self) { i in
                                AsyncImage(url: frameURL(runId, i)) { ph in
                                    if case .success(let img) = ph {
                                        img.resizable().scaledToFill()
                                    } else {
                                        RelayTheme.paper2
                                    }
                                }
                                .frame(width: 128, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .id("film-\(runId)")
                }
            }
            .padding(16)
        }
        .background(RelayTheme.paper2)
    }

    private func sectionCaption(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .kerning(0.8)
            .foregroundStyle(RelayTheme.inkSecondary)
            .padding(.top, 4)
    }

    private func kindColor(_ kind: String) -> Color {
        switch kind {
        case "clinical": return RelayTheme.red
        case "operational": return RelayTheme.amber
        case "dme": return RelayTheme.blueDeep
        default: return RelayTheme.inkSecondary
        }
    }

    private func approvalCard(_ a: Approval) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(kindColor(a.kind))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 8)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(a.kind.uppercased())
                        .font(.caption2.bold())
                        .kerning(0.6)
                        .foregroundStyle(kindColor(a.kind))
                    Spacer()
                    if a.status == "approved" {
                        Label("Approved", systemImage: "checkmark.circle.fill")
                            .font(.caption.bold())
                            .foregroundStyle(RelayTheme.green)
                    } else {
                        Button("Approve") { approve(a) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(RelayTheme.green)
                    }
                }
                Text(a.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(RelayTheme.ink)
                Text(a.detail)
                    .font(.caption)
                    .foregroundStyle(RelayTheme.inkSecondary)
                    .lineSpacing(1.5)
            }
            .padding(12)
        }
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(RelayTheme.hairline))
    }

    // MARK: right pane — the full report, embedded

    @ViewBuilder
    private var reportPane: some View {
        if let runId {
            ReportWebView(url: reportURL(runId))
                .id(runId)
        } else {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: urls + data

    private var frameIndices: [Int] {
        let step = max(1, nFrames / 12)
        return Array(stride(from: 0, to: nFrames, by: step))
    }

    private func reportURL(_ run: String) -> URL {
        URL(string: "report?run=\(run)&embed=1",
            relativeTo: BackendClient.shared.baseURL)!
    }

    private func floorplanURL(_ run: String) -> URL {
        URL(string: "floorplan?run=\(run)",
            relativeTo: BackendClient.shared.baseURL)!
    }

    private func frameURL(_ run: String, _ i: Int) -> URL {
        URL(string: "frames/\(run)/\(i).jpg",
            relativeTo: BackendClient.shared.baseURL)!
    }

    private func refresh() {
        BackendClient.shared.fetchApprovals(run: selectedRun) { obj in
            runId = obj["run_id"] as? String
            blocked = obj["n_blocked"] as? Int ?? 0
            nFrames = obj["n_frames"] as? Int ?? 0
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
                .foregroundStyle(RelayTheme.blueDeep)
            Text("Abridge captures the encounter. HomeReady verifies the home.")
                .font(.footnote.italic())
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            Button {
                onDone()
            } label: {
                Label("Back to Monica's chart", systemImage: "arrow.uturn.backward")
                    .font(.headline)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(RelayTheme.brand)
            .padding(.top, 8)
            Spacer()
        }
        .padding()
    }
}
