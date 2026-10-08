import Foundation

/// Public address lookup through Cloudflare's trace endpoint (plain text, no account, no tracking cookies).
public enum PublicIP {
    public static let traceURL = URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!

    public enum LookupError: Error {
        case badResponse
    }

    /// The trace is `key=value` lines; the address is the `ip=` one.
    public static func parseTrace(_ text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix("ip=") {
            let address = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return IPAddress.isValid(address) ? address : nil
        }
        return nil
    }

    public static func fetch() async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: traceURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let address = parseTrace(String(decoding: data, as: UTF8.self))
        else { throw LookupError.badResponse }
        return address
    }
}
