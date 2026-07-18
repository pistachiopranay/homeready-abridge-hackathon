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
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 54))
                .foregroundStyle(.teal)
            Text("Relay")
                .font(.system(size: 46, weight: .bold, design: .rounded))
            Text("Care doesn't end at the encounter.")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("Today's walkthrough")
                    .font(.caption.smallCaps())
                    .foregroundStyle(.secondary)
                Text("Monica's apartment · she comes home Friday")
                    .font(.headline)
                Text("Walk room to room and just talk to Steady —\nit will guide you the whole way.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

            Button {
                let raw = backendHost.contains("://") ? backendHost : "http://\(backendHost)"
                if let url = URL(string: raw) {
                    BackendClient.shared.baseURL = url
                }
                BackendClient.shared.startWalkthrough()
                walking = true
                reportURL = nil
                Task { await voice.start() }
                scanner.startRoom(named: room)
            } label: {
                Label("Start walkthrough", systemImage: "figure.walk")
                    .font(.title.bold())
                    .padding(.horizontal, 44).padding(.vertical, 18)
            }
            .buttonStyle(.borderedProminent)
            .tint(.teal)

            if let reportURL {
                VStack(spacing: 6) {
                    Label("Walkthrough complete — report sent to Monica's care team",
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

            // Setup detail, out of the caregiver's way
            TextField("backend host (ip:port or full URL)", text: $backendHost)
                .textFieldStyle(.roundedBorder)
                .font(.footnote.monospaced())
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .frame(maxWidth: 300)
                .opacity(0.5)
        }
        .padding()
    }

    private var walkthroughView: some View {
        ZStack(alignment: .bottom) {
            RoomCaptureViewRep()
                .ignoresSafeArea()

            VStack {
                ConfirmationOverlay()
                    .padding(.top, 14)
                Spacer()
            }

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
