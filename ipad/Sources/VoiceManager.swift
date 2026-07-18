import Combine
import ElevenLabs
import Foundation

/// Thin wrapper around the ElevenLabs conversation. The agent's LLM is our
/// backend (custom-LLM endpoint), so this class is plumbing only.
@MainActor
final class VoiceManager: ObservableObject {
    static let shared = VoiceManager()

    static let agentId = "agent_9201kxsnxjpmfcgr4thxc08k9jpq"

    @Published var isConnected = false
    @Published var lastAgentLine = ""
    @Published var connectionError = ""

    private var conversation: Conversation?
    private var cancellables: Set<AnyCancellable> = []

    func start() async {
        guard conversation == nil else { return }
        do {
            let convo = try await ElevenLabs.startConversation(agentId: Self.agentId)
            conversation = convo
            isConnected = true
            convo.$messages
                .receive(on: DispatchQueue.main)
                .sink { [weak self] messages in
                    if let last = messages.last(where: { $0.role == .agent }) {
                        self?.lastAgentLine = last.content
                    }
                }
                .store(in: &cancellables)
        } catch {
            connectionError = "Voice failed: \(error.localizedDescription)"
            isConnected = false
        }
    }

    func stop() async {
        await conversation?.endConversation()
        conversation = nil
        cancellables.removeAll()
        isConnected = false
    }
}
