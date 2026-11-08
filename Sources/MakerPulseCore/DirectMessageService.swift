import Foundation

/// A chat credential belongs in Keychain, never the analytics library or logs.
/// Only an explicit connection action calls authorize; polling never renews it.
public struct DirectMessageCredential: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let profileID: String
    public let userID: String
    public let token: String
    public let expiresAt: Date
    public init(profileID: String, userID: String, token: String, expiresAt: Date) {
        self.profileID = profileID; self.userID = userID; self.token = token; self.expiresAt = expiresAt
    }
    public var description: String { "MakerWorld direct-message credential (redacted)" }
    public var debugDescription: String { description }
}

public enum DirectMessageServiceError: LocalizedError, Sendable, Equatable {
    case authentication, accountMismatch, malformed, incomplete, network, unavailable(Int)
    public var errorDescription: String? {
        switch self {
        case .authentication: "The direct-message connection is unavailable or expired. Reconnect direct messages in Settings."
        case .accountMismatch: "This direct-message connection belongs to another monitored profile."
        case .malformed: "MakerWorld changed its direct-message response. Saved history was preserved."
        case .incomplete: "The direct-message refresh was incomplete. Saved history was preserved."
        case .network: "The direct-message request could not complete. Saved history was preserved."
        case .unavailable(let code): "The direct-message service returned HTTP \(code). Saved history was preserved."
        }
    }
}

/// MakerWorld's deployed OpenIM protocol v0.0.14 read operations. These JSON
/// POSTs query metadata/history; no send, read-marking, preference or WS APIs
/// are used. Full batches are returned before the caller can commit a baseline.
public actor DirectMessageService {
    private let transport: any HTTPTransport
    private let minimumInterval: TimeInterval
    private var nextRequest = Date.distantPast
    private static let maximumConversations = 5_000
    private static let maximumSequencesPerRefresh: Int64 = 5_000
    private static let maximumResponseBytes = 8 * 1_024 * 1_024

    public init(transport: any HTTPTransport = URLSessionTransport(), minimumInterval: TimeInterval = 0.4) {
        self.transport = transport
        self.minimumInterval = minimumInterval.isFinite ? min(60, max(0, minimumInterval)) : 0.4
    }

    /// Minting a chat token may invalidate another chat client's session. This
    /// method is intentionally separate from snapshot(), without grant retries.
    public func authorize(bambuToken: String, profileID: String, at date: Date = Date()) async throws -> DirectMessageCredential {
        do {
            guard Self.validID(profileID), Self.validToken(bambuToken), date.timeIntervalSince1970.isFinite else {
                throw DirectMessageServiceError.authentication
            }
            let validator = MakerWorldAPI(transport: transport, minimumInterval: 0)
            let profile = try await validator.validate(token: bambuToken)
            guard profile.id == profileID else { throw DirectMessageServiceError.accountMismatch }
            try Task.checkCancellation()
            var components = URLComponents(string: "https://api.bambulab.com")!
            components.path = "/v1/design-user-service/my/im/token"
            components.queryItems = [URLQueryItem(name: "platformId", value: "4")]
            var request = Self.request(url: components.url!)
            request.setValue("Bearer \(bambuToken)", forHTTPHeaderField: "Authorization")
            let data = try await send(request)
            let grant: AuthGrant
            do { grant = try JSONDecoder().decode(AuthGrant.self, from: data) }
            catch { throw DirectMessageServiceError.malformed }
            guard Self.validID(grant.userId), Self.validToken(grant.token), grant.expireIn > 0,
                grant.expireIn <= 366 * 86_400 else { throw DirectMessageServiceError.malformed }
            return DirectMessageCredential(profileID: profileID, userID: grant.userId, token: grant.token,
                expiresAt: date.addingTimeInterval(TimeInterval(grant.expireIn)))
        } catch { throw Self.sanitized(error) }
    }

    public func snapshot(session: DirectMessageCredential, known: DirectMessageState?, at date: Date = Date()) async throws -> DirectMessageBatch {
        do {
            guard Self.validID(session.profileID), Self.validID(session.userID), Self.validToken(session.token),
                date.timeIntervalSince1970.isFinite, session.expiresAt > date else { throw DirectMessageServiceError.authentication }
            // Scope validation also applies to an empty server conversation list.
            _ = try DirectMessageAnalytics.knownSequence(conversationID: "", profileID: session.profileID, metadata: known)
            let conversationData = try await read(path: "/conversation/get_all_conversations", session: session,
                body: OwnerRequest(ownerUserID: session.userID))
            let remote = try DirectMessageServiceParser.conversations(conversationData, userID: session.userID)
            guard remote.count <= Self.maximumConversations else { throw DirectMessageServiceError.incomplete }
            if remote.isEmpty {
                try Task.checkCancellation()
                return try DirectMessageBatch(conversations: [], conversationTotal: 0, unreadTotal: 0)
            }
            let ids = Set(remote.map(\.id))
            let sequenceData = try await read(path: "/msg/get_conversations_has_read_and_max_seq", session: session,
                body: SequenceRequest(userID: session.userID, conversationIDs: ids.sorted()))
            let sequences = try DirectMessageServiceParser.sequences(sequenceData, conversationIDs: ids)
            var result: [DirectMessageConversation] = [], unreadTotal = 0, requestedSequences: Int64 = 0
            for conversation in remote where conversation.kind == 1 {
                try Task.checkCancellation()
                guard let sequence = sequences[conversation.id] else { throw DirectMessageServiceError.incomplete }
                let unread = max(0, sequence.maximum - min(sequence.maximum, sequence.read))
                guard unread <= Int64(Int.max - unreadTotal) else { throw DirectMessageServiceError.incomplete }
                unreadTotal += Int(unread)
                let previous = try DirectMessageAnalytics.knownSequence(conversationID: conversation.id,
                    profileID: session.profileID, metadata: known)
                var messages: [DirectMessageMetadata] = []
                // A nonzero conversation maximum is a per-user history ceiling.
                // Honor it while consuming the global watermark to avoid replay
                // if an old, previously hidden range becomes visible later.
                let end = conversation.maximumSequence > 0 ? min(sequence.maximum, conversation.maximumSequence) : sequence.maximum
                let observed = previous ?? sequence.read
                if observed < end {
                    var begin = max(1, max(conversation.minimumSequence, observed + 1))
                    if begin <= end, end - begin + 1 > Self.maximumSequencesPerRefresh - requestedSequences {
                        throw DirectMessageServiceError.incomplete
                    }
                    var seenSequences = Set<Int64>()
                    while begin <= end {
                        try Task.checkCancellation()
                        let count = min(Int64(100), end - begin + 1)
                        guard count <= Self.maximumSequencesPerRefresh - requestedSequences else { throw DirectMessageServiceError.incomplete }
                        requestedSequences += count
                        let chunkEnd = begin + (count - 1)
                        let pullData = try await read(path: "/msg/pull_msg_by_seq", session: session,
                            body: PullRequest(userID: session.userID,
                                seqRanges: [SequenceRange(conversationID: conversation.id, begin: begin, end: chunkEnd, num: count)], order: 0))
                        let pull = try DirectMessageServiceParser.messages(pullData, conversationID: conversation.id,
                            userID: session.userID, peerID: conversation.peerID, begin: begin, end: chunkEnd)
                        guard pull.messages.count <= Int(count) else { throw DirectMessageServiceError.incomplete }
                        for message in pull.messages {
                            guard let value = message.sequence, (begin...chunkEnd).contains(value),
                                seenSequences.insert(value).inserted else { throw DirectMessageServiceError.incomplete }
                            messages.append(message)
                        }
                        // isEnd describes the live global boundary, not whether
                        // this explicit bounded range completed. Deleted-message
                        // holes are filtered by this deployed server contract.
                        if chunkEnd == end { break }
                        begin = chunkEnd + 1
                    }
                }
                result.append(DirectMessageConversation(conversationID: conversation.id, unreadCount: Int(unread),
                    receiveOption: conversation.receiveOption, latestMessage: messages.max { ($0.sequence ?? 0) < ($1.sequence ?? 0) },
                    messages: messages, maximumSequence: sequence.maximum, readSequence: sequence.read))
            }
            try Task.checkCancellation()
            return try DirectMessageBatch(conversations: result, conversationTotal: result.count, unreadTotal: unreadTotal)
        } catch { throw Self.sanitized(error) }
    }

    private func read<T: Encodable>(path: String, session: DirectMessageCredential, body: T) async throws -> Data {
        var components = URLComponents(string: "https://api.bambulab.com")!
        components.path = "/v1/im-service/api" + path
        var request = Self.request(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(session.token, forHTTPHeaderField: "token")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "operationID")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let slot = max(nextRequest, Date())
        nextRequest = slot.addingTimeInterval(minimumInterval)
        if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
        let response = try await transport.send(request)
        try Task.checkCancellation()
        if response.status == 401 || response.status == 403 { throw DirectMessageServiceError.authentication }
        if response.status == 429 {
            let delay = MakerWorldAPI.retryDelay(header: response.headers["retry-after"], attempt: 0)
            nextRequest = max(nextRequest, Date().addingTimeInterval(delay))
        }
        guard (200...299).contains(response.status) else { throw DirectMessageServiceError.unavailable(response.status) }
        guard !response.data.isEmpty, response.data.count <= Self.maximumResponseBytes else { throw DirectMessageServiceError.malformed }
        return response.data
    }

    private static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("MakerGlance (macOS; local analytics)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512 && value.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
        }
    }
    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16_384 && value.unicodeScalars.allSatisfy {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0)
        }
    }
    private static func sanitized(_ error: Error) -> Error {
        if error is CancellationError || Task.isCancelled { return CancellationError() }
        if let error = error as? DirectMessageServiceError { return error }
        if let error = error as? PulseError {
            switch error {
            case .authentication, .challenge: return DirectMessageServiceError.authentication
            case .accountMismatch: return DirectMessageServiceError.accountMismatch
            case .incomplete: return DirectMessageServiceError.incomplete
            case .malformed: return DirectMessageServiceError.malformed
            case .http(let code): return DirectMessageServiceError.unavailable(code)
            default: return DirectMessageServiceError.network
            }
        }
        return DirectMessageServiceError.network
    }
    private struct AuthGrant: Decodable { let userId: String; let token: String; let expireIn: Int64 }
    private struct OwnerRequest: Encodable { let ownerUserID: String }
    private struct SequenceRequest: Encodable { let userID: String; let conversationIDs: [String] }
    private struct SequenceRange: Encodable { let conversationID: String; let begin: Int64; let end: Int64; let num: Int64 }
    private struct PullRequest: Encodable { let userID: String; let seqRanges: [SequenceRange]; let order: Int }
}
