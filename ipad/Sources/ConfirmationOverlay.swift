import SwiftUI

struct Confirmation: Identifiable, Equatable {
    let id: String
    let question: String
    let status: String   // pending | confirmed | denied
    let resolvedBy: String?
}

/// Polls the backend and shows the newest confirmation as a card. Pending cards
/// have tappable ✓/✗; if the caregiver answers by voice instead, the card flips
/// green (or red) on the next poll and fades out.
struct ConfirmationOverlay: View {
    @State private var visible: Confirmation?
    @State private var dismissTask: DispatchWorkItem?
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let c = visible {
                card(for: c)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: visible)
        .onReceive(timer) { _ in refresh() }
    }

    private func refresh() {
        BackendClient.shared.fetchConfirmations { items in
            let parsed = items.map {
                Confirmation(id: $0["id"] as? String ?? "",
                             question: $0["question"] as? String ?? "",
                             status: $0["status"] as? String ?? "pending",
                             resolvedBy: $0["resolved_by"] as? String)
            }
            // A visible card that just got voice-resolved: show its final state briefly
            if let cur = visible, let updated = parsed.first(where: { $0.id == cur.id }),
               updated.status != "pending" {
                show(updated, autoDismiss: true)
                return
            }
            if visible == nil || visible?.status != "pending",
               let next = parsed.last(where: { $0.status == "pending" }) {
                show(next, autoDismiss: false)
            }
        }
    }

    private func show(_ c: Confirmation, autoDismiss: Bool) {
        dismissTask?.cancel()
        visible = c
        if autoDismiss {
            let task = DispatchWorkItem { visible = nil }
            dismissTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: task)
        }
    }

    private func answer(_ c: Confirmation, _ yes: Bool) {
        BackendClient.shared.resolveConfirmation(id: c.id, answer: yes)
        show(Confirmation(id: c.id, question: c.question,
                          status: yes ? "confirmed" : "denied", resolvedBy: "tap"),
             autoDismiss: true)
    }

    @ViewBuilder
    private func card(for c: Confirmation) -> some View {
        let resolved = c.status != "pending"
        let good = c.status == "confirmed"
        HStack(spacing: 14) {
            if resolved {
                Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(good ? .green : .red)
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.blue)
            }

            Text(c.question)
                .font(.callout.weight(.medium))
                .lineLimit(3)

            if !resolved {
                Spacer(minLength: 4)
                Button { answer(c, true) } label: {
                    Image(systemName: "checkmark")
                        .font(.title3.bold())
                        .frame(width: 52, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Button { answer(c, false) } label: {
                    Image(systemName: "xmark")
                        .font(.title3.bold())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(resolved ? (good ? Color.green : .red) : .clear, lineWidth: 2))
        .frame(maxWidth: 560)
    }
}
