import Foundation
import UIKit

/// Dumb pipe to the Mac backend. All intelligence lives server-side.
final class BackendClient {
    static let shared = BackendClient()

    /// Updated from the start screen; venue Wi-Fi changes the Mac's IP.
    var baseURL = URL(string: "http://10.1.63.110:8000")!

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()

    private func post(_ path: String, json: [String: Any],
                      completion: (([String: Any]?) -> Void)? = nil) {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        session.dataTask(with: req) { data, _, err in
            if let err { print("POST \(path) failed: \(err.localizedDescription)") }
            let obj = data.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            }
            completion.map { cb in DispatchQueue.main.async { cb(obj) } }
        }.resume()
    }

    func startWalkthrough() { post("walkthrough/start", json: [:]) }

    func send(frame jpeg: Data, room: String) {
        post("frame", json: ["image_b64": jpeg.base64EncodedString(), "room": room])
    }

    func send(roomPlan: [String: Any]) { post("roomplan", json: roomPlan) }

    func send(event text: String, room: String? = nil) {
        var body: [String: Any] = ["text": text]
        if let room { body["room"] = room }
        post("event", json: body)
    }

    func fetchConfirmations(completion: @escaping ([[String: Any]]) -> Void) {
        let url = baseURL.appendingPathComponent("confirmations")
        session.dataTask(with: url) { data, _, _ in
            let items = data
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["confirmations"] as? [[String: Any]] } ?? []
            DispatchQueue.main.async { completion(items) }
        }.resume()
    }

    func resolveConfirmation(id: String, answer: Bool) {
        post("confirmations/\(id)/resolve", json: ["answer": answer, "by": "tap"])
    }

    func fetchState(completion: @escaping ([String: Any]) -> Void) {
        let url = baseURL.appendingPathComponent("state")
        session.dataTask(with: url) { data, _, _ in
            let obj = data.flatMap {
                try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
            } ?? [:]
            DispatchQueue.main.async { completion(obj) }
        }.resume()
    }

    func finishWalkthrough(completion: @escaping (String?) -> Void) {
        post("walkthrough/finish", json: [:]) { obj in
            completion(obj?["report_url"] as? String)
        }
    }
}
