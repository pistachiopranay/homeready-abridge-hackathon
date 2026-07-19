import AVKit
import SwiftUI

@main
struct WalkthroughApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

private let ROOMS = ["entry", "living room", "kitchen", "hallway", "bathroom", "bedroom"]

enum FlowStage {
    case home, portal, patientMessage, thanks, careTeam, discharged
}

struct ContentView: View {
    @StateObject private var voice = VoiceManager.shared
    @StateObject private var scanner = RoomScanner.shared

    @State private var backendHost = "10.1.63.110:8000"
    @State private var stage: FlowStage = .home
    @State private var inGuidedFlow = false
    @State private var walking = false
    @State private var demoMode = false
    @State private var demoPlayer: AVPlayer?
    @State private var room = "entry"
    @State private var reportURL: String?
    @State private var finishing = false
    @State private var showPastRuns = false
    @State private var careTeamRun: String?

    private func applyHost() {
        let raw = backendHost.contains("://") ? backendHost : "http://\(backendHost)"
        if let url = URL(string: raw) {
            BackendClient.shared.baseURL = url
        }
    }

    private func startLive() {
        applyHost()
        BackendClient.shared.startWalkthrough()
        demoMode = false
        walking = true
        reportURL = nil
        Task { await voice.start() }
        scanner.startRoom(named: room)
    }

    private func startDemoReplay() {
        applyHost()
        BackendClient.shared.startDemo()
        demoMode = true
        walking = true
        reportURL = nil
        let player = AVPlayer(url: BackendClient.shared.demoVideoURL)
        player.isMuted = true
        demoPlayer = player
        player.play()
        Task { await voice.start() }
    }

    var body: some View {
        if walking {
            walkthroughView
        } else {
            switch stage {
            case .home:
                startView
            case .portal:
                ClinicianPortalView(
                    onHandoff: { stage = .patientMessage },
                    onOpenSample: { runId in
                        careTeamRun = runId
                        stage = .careTeam
                    },
                    onReset: { stage = .home })
            case .patientMessage:
                PatientMessageView(
                    onStartLive: { inGuidedFlow = true; startLive() },
                    onStartDemo: { inGuidedFlow = true; startDemoReplay() })
            case .thanks:
                ThanksView { stage = .careTeam }
            case .careTeam:
                CareTeamView(onCleared: { stage = .discharged },
                             initialRun: careTeamRun,
                             onBack: { careTeamRun = nil; stage = .portal })
            case .discharged:
                DischargedView {
                    stage = .portal      // close the loop back in the chart
                    inGuidedFlow = false
                }
            }
        }
    }

    // MARK: Home

    private var startView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 54))
                .foregroundStyle(RelayTheme.brand)
            Text("HomeReady")
                .font(.system(size: 46, weight: .bold, design: .rounded))
            Text("Verify the home before discharge.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Button {
                applyHost()
                stage = .portal
            } label: {
                Label("Start demo — from the clinician portal",
                      systemImage: "play.circle.fill")
                    .font(.title.bold())
                    .padding(.horizontal, 36).padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(RelayTheme.brand)

            HStack(spacing: 12) {
                Button {
                    inGuidedFlow = false
                    startLive()
                } label: {
                    Label("Walk-through only", systemImage: "figure.walk")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    inGuidedFlow = false
                    startDemoReplay()
                } label: {
                    Label("Replay recording", systemImage: "play.rectangle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Button {
                    applyHost()
                    showPastRuns = true
                } label: {
                    Label("Past walkthroughs",
                          systemImage: "square.split.bottomrightquarter")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .sheet(isPresented: $showPastRuns) { PastRunsView() }
            }

            if let reportURL {
                VStack(spacing: 6) {
                    Label("Walkthrough complete — report ready for the care team",
                          systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("\(backendHost)\(reportURL)")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding()
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if !voice.connectionError.isEmpty {
                Text(voice.connectionError).foregroundStyle(.red).font(.footnote)
            }

            Spacer()

            TextField("backend host (ip:port or full URL)", text: $backendHost)
                .textFieldStyle(.roundedBorder)
                .font(.footnote.monospaced())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(maxWidth: 300)
                .opacity(0.5)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RelayTheme.paper)
    }

    // MARK: Walkthrough (Act 3)

    private var walkthroughView: some View {
        ZStack(alignment: .bottom) {
            if demoMode, let demoPlayer {
                VideoPlayer(player: demoPlayer)
                    .disabled(true)
                    .ignoresSafeArea()
            } else {
                RoomCaptureViewRep()
                    .ignoresSafeArea()
                DetectionOverlayView()
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "house.fill")
                    Text("HomeReady · walk-through with Riley")
                        .font(.footnote.bold())
                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(PatientTheme.barGradient.opacity(0.9))

                ConfirmationOverlay()
                    .padding(.top, 10)
                Spacer()
            }

            VStack {
                HStack {
                    Spacer()
                    DebugOverlay()
                }
                Spacer()
            }
            .padding(.top, 44)
            .padding(.trailing, 14)

            VStack(spacing: 12) {
                if !voice.lastAgentLine.isEmpty {
                    Text(voice.lastAgentLine)
                        .font(.callout)
                        .lineLimit(3)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if !scanner.lastStatus.isEmpty {
                    Label(scanner.lastStatus, systemImage: "ruler")
                        .font(.footnote.monospaced())
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .transition(.scale.combined(with: .opacity))
                }

                HStack(spacing: 10) {
                    if !demoMode {
                        Picker("Room", selection: $room) {
                            ForEach(ROOMS, id: \.self) { Text($0.capitalized) }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: room) { newRoom in
                            scanner.finishRoom()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                scanner.startRoom(named: newRoom)
                            }
                        }
                    }

                    HStack {
                        Circle()
                            .fill(voice.isConnected ? (voice.isMuted ? .orange : .green) : .red)
                            .frame(width: 10, height: 10)
                        Text(voice.isConnected
                             ? (voice.isMuted ? "Riley can't hear" : "Riley live")
                             : "voice off")
                            .font(.footnote)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())

                    Button {
                        voice.toggleMute()
                    } label: {
                        Label(voice.isMuted ? "Unmute" : "Mute",
                              systemImage: voice.isMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.footnote.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(voice.isMuted ? .orange : .gray)
                    .disabled(!voice.isConnected)

                    Button(role: .destructive) {
                        endWalkthrough()
                    } label: {
                        finishing ? Label("Finishing…", systemImage: "hourglass")
                                  : Label("End walkthrough",
                                          systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(finishing)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
            .animation(.spring(duration: 0.4), value: scanner.lastStatus)
        }
    }

    private func endWalkthrough() {
        finishing = true
        if demoMode {
            BackendClient.shared.stopDemo()
            demoPlayer?.pause()
            demoPlayer = nil
        } else {
            scanner.finishRoom()
        }
        Task { await voice.stop() }

        if inGuidedFlow {
            walking = false
            stage = .thanks
        }
        // Give the room-scan result a moment to post before the finish drain
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            BackendClient.shared.finishWalkthrough { url in
                reportURL = url
                finishing = false
                if !inGuidedFlow {
                    walking = false
                }
            }
        }
    }
}
