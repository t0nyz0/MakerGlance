import Foundation

public enum NetworkOrigin {
    // An HTTPS origin includes its effective port, not only its hostname.
    public static func permitsRedirect(from original: URL?, to destination: URL?) -> Bool {
        guard let original, let destination,
              original.scheme?.lowercased() == "https", destination.scheme?.lowercased() == "https",
              original.user == nil, original.password == nil, destination.user == nil, destination.password == nil,
              let host = original.host?.lowercased(), host == destination.host?.lowercased(),
              (original.port ?? 443) == (destination.port ?? 443) else { return false }
        return true
    }
}

public final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(NetworkOrigin.permitsRedirect(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}
