import SwiftUI

@main
struct WalkthroughApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

private let ROOMS = ["entry", "living room", "kitchen", "hallway", "bathroom", "bedroom"]

struct ContentView: View {
    @StateObject private var voice = VoiceManager.shared
    @StateObject private var scanner = RoomScanner.shared

    @State private var backendHost = "10.1.63.110:8000"
    @State private var walking = false
    @State private var room = "entry"
    @State private var reportURL: String?
    @State private var finishing = false

    var body: some View {
        if walking {
            walkthroughView
        } else {
            startView
        }
    }

    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Home Safety Walkthrough")
                .font(.largeTitle.bold())
            Text("Monica Hilpert · going home Friday")
                .foregroundStyle(.secondary)

            TextField("Mac backend host:port", text: $backendHost)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(maxWidth: 340)

            Button {
                if let url = URL(string: "http://\(backendHost)") {
                    BackendClient.shared.baseURL = url
                }
                BackendClient.shared.startWalkthrough()
                walking = true
                reportURL = nil
                Task { await voice.start() }
                scanner.startRoom(named: room)
            } label: {
                Label("Start walkthrough", systemImage: "figure.walk")
                    .font(.title2.bold())
                    .padding(.horizontal, 32).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            if let reportURL {
                VStack(spacing: 6) {
                    Text("Report ready on the care-team side:")
                    Text("http://\(backendHost)\(reportURL)")
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
                .padding()
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            if !voice.connectionError.isEmpty {
                Text(voice.connectionError).foregroundStyle(.red).font(.footnote)
            }
            Spacer()
        }
        .padding()
    }

    private var walkthroughView: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureViewRep()
                .ignoresSafeArea()

            VStack(spacing: 12) {
                if !voice.lastAgentLine.isEmpty {
                    Text(voice.lastAgentLine)
                        .font(.callout)
                        .lineLimit(3)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                if !scanner.lastStatus.isEmpty {
                    Text(scanner.lastStatus)
                        .font(.footnote.monospaced())
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                HStack(spacing: 10) {
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

                    HStack {
                        Circle()
                            .fill(voice.isConnected ? .green : .red)
                            .frame(width: 10, height: 10)
                        Text(voice.isConnected ? "voice live" : "voice off")
                            .font(.footnote)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())

                    Button(role: .destructive) {
                        endWalkthrough()
                    } label: {
                        finishing ? Label("Finishing…", systemImage: "hourglass")
                                  : Label("End walkthrough", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(finishing)
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
    }

    private func endWalkthrough() {
        finishing = true
        scanner.finishRoom()
        Task { await voice.stop() }
        // Give the room-scan result a moment to post before the finish drain
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            BackendClient.shared.finishWalkthrough { url in
                reportURL = url
                finishing = false
                walking = false
            }
        }
    }
}
