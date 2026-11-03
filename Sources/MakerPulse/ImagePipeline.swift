import AppKit
import Foundation
import ImageIO
import OSLog
import Combine
import MakerPulseCore

private actor ImageDataPipeline {
    static let shared = ImageDataPipeline()
    private let memory = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data?, Never>] = [:]
    private let session: URLSession
    private let privateSession: URLSession
    init() {
        memory.totalCostLimit = 12 * 1024 * 1024; memory.countLimit = 300
        let config = URLSessionConfiguration.default
        config.httpShouldSetCookies = false; config.httpMaximumConnectionsPerHost = 4
        config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        config.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 128 * 1024 * 1024, diskPath: "MakerPulseImages")
        session = URLSession(configuration: config, delegate: SameOriginRedirects(), delegateQueue: nil)
        let cloud = URLSessionConfiguration.ephemeral
        cloud.httpShouldSetCookies = false; cloud.httpCookieStorage = nil; cloud.urlCredentialStorage = nil
        cloud.httpMaximumConnectionsPerHost = 4; cloud.timeoutIntervalForRequest = 15; cloud.timeoutIntervalForResource = 25
        cloud.urlCache = nil
        privateSession = URLSession(configuration: cloud, delegate: SameOriginRedirects(), delegateQueue: nil)
    }
    func load(_ url: URL, reload: Bool = false) async -> Data? {
        if reload { memory.removeObject(forKey: url as NSURL) }
        if let value = memory.object(forKey: url as NSURL) { return value as Data }
        if let task = inFlight[url] { return await task.value }
        let task = Task<Data?, Never> { [session, privateSession] in
            do {
                let source = url.host?.lowercased() == ImageURLPolicy.printCoverHost ? privateSession : session
                var request = URLRequest(url: url)
                if reload { request.cachePolicy = .reloadIgnoringLocalCacheData }
                let (data, response) = try await source.data(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count <= 12 * 1024 * 1024,
                    NetworkOrigin.permitsRedirect(from: url, to: response.url),
                    let image = CGImageSourceCreateWithData(data as CFData, nil),
                    CGImageSourceCreateImageAtIndex(image, 0, nil) != nil else {
                    Logger(subsystem: AppIdentity.bundleIdentifier, category: "Images").warning("Image rejected on host \(url.host ?? "unknown", privacy: .public); HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                    return nil
                }
                return data
            } catch {
                let code = (error as NSError).code
                Logger(subsystem: AppIdentity.bundleIdentifier, category: "Images").warning("Image download failed on host \(url.host ?? "unknown", privacy: .public); error \(code)")
                return nil
            }
        }
        inFlight[url] = task
        let result = await task.value; inFlight[url] = nil
        if let result { memory.setObject(result as NSData, forKey: url as NSURL, cost: result.count) }
        return result
    }
}

@MainActor enum ImageRenderer {
    static let decoded: NSCache<NSURL, NSImage> = { let cache = NSCache<NSURL, NSImage>(); cache.countLimit = 220; cache.totalCostLimit = 40 * 1024 * 1024; return cache }()
    static func load(_ url: URL, fallback: URL? = nil) async -> NSImage? {
        if let image = decoded.object(forKey: url as NSURL) { return image }
        var data = await ImageDataPipeline.shared.load(url)
        // A cached error page or interrupted response must not trap a view in its placeholder.
        if data == nil { data = await ImageDataPipeline.shared.load(url, reload: true) }
        if data == nil, let fallback, fallback != url { data = await ImageDataPipeline.shared.load(fallback, reload: true) }
        guard let data, let image = NSImage(data: data) else { return nil }
        let pixels = image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? data.count * 4
        decoded.setObject(image, forKey: url as NSURL, cost: max(1, pixels)); return image
    }
}

@MainActor final class ImageRefresh: ObservableObject {
    static let shared = ImageRefresh()
    @Published private(set) var revision = 0
    func retry() { revision += 1 }
}
