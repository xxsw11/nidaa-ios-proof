import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum TrialFailure: Error {
    case failed(String)
}

func requireTrial(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw TrialFailure.failed(name) }
}

/// Test-process-only inbox reader. Never follows a mail link or exposes its contents.
/// The application target does not depend on this executable target.
struct LocalMailbox {
    let baseURL: URL

    func verificationHash(for email: String) async throws -> String {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            let listing = try await object("api/v1/messages")
            let messages = listing["messages"] as? [[String: Any]] ?? []
            for message in messages {
                let recipients = message["To"] as? [[String: Any]] ?? []
                guard recipients.contains(where: { ($0["Address"] as? String)?.lowercased() == email.lowercased() }),
                      let id = message["ID"] as? String else { continue }
                let full = try await object("api/v1/message/" + id)
                let body = ((full["HTML"] as? String ?? "") + "\n" + (full["Text"] as? String ?? ""))
                    .replacingOccurrences(of: "&amp;", with: "&")
                let expression = try NSRegularExpression(pattern: "https?://[^\\s<>\"']+")
                let whole = NSRange(body.startIndex..<body.endIndex, in: body)
                for match in expression.matches(in: body, range: whole) {
                    guard let range = Range(match.range, in: body),
                          let parts = URLComponents(string: String(body[range])) else { continue }
                    let values = parts.queryItems ?? []
                    guard values.first(where: { $0.name == "type" })?.value == "signup",
                          let token = values.first(where: { $0.name == "token_hash" || $0.name == "token" })?.value,
                          !token.isEmpty else { continue }
                    return token
                }
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        throw TrialFailure.failed("local verification message timeout")
    }

    private func object(_ path: String) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(from: baseURL.appendingPathComponent(path))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TrialFailure.failed("local inbox HTTP response")
        }
        return object
    }
}
