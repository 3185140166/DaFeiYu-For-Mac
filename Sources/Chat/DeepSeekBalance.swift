import Foundation

struct DeepSeekBalanceSnapshot: Sendable {
    struct Amount: Sendable {
        let currency: String
        let total: String
    }
    let amounts: [Amount]
    let isAvailable: Bool
    let fetchedAt: Date
    var displayAmount: String {
        amounts.map { ($0.currency == "CNY" ? "¥" : "$") + $0.total }.joined(separator: " / ")
    }
}

enum DeepSeekBalanceFailure: LocalizedError {
    case unsupported, missingKey, http(Int), malformed
    var errorDescription: String? {
        switch self {
        case .unsupported: return "Balance queries require the official DeepSeek HTTPS endpoint."
        case .missingKey: return "API Key is missing."
        case .http(let code): return "HTTP \(code)"
        case .malformed: return "Invalid balance response."
        }
    }
}

/// Read-only balance requests. Credentials never leave api.deepseek.com.
@MainActor
final class DeepSeekBalance {
    static let shared = DeepSeekBalance()
    static let cacheLifetime: TimeInterval = 60
    typealias Transport = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private struct Identity: Equatable { let endpoint: String; let key: String }
    private var cached: (identity: Identity, snapshot: DeepSeekBalanceSnapshot)?
    private var failed: (identity: Identity, at: Date, error: Error)?
    private var pending: (id: UUID, identity: Identity, task: Task<DeepSeekBalanceSnapshot, Error>)?
    private let transport: Transport

    init(transport: Transport? = nil) {
        self.transport = transport ?? { request in
            let session = URLSession(configuration: .ephemeral, delegate: ChatRedirectPolicy(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw DeepSeekBalanceFailure.malformed }
            return (data, response)
        }
    }
    static func balanceURL(for endpoint: String) throws -> URL {
        guard let url = URL(string: endpoint), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "api.deepseek.com", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw DeepSeekBalanceFailure.unsupported
        }
        return URL(string: "https://api.deepseek.com/user/balance")!
    }
    static func decode(_ data: Data, at date: Date) throws -> DeepSeekBalanceSnapshot {
        struct Response: Decodable {
            struct Row: Decodable { let currency: String; let total_balance: String }
            let is_available: Bool
            let balance_infos: [Row]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.balance_infos.isEmpty, response.balance_infos.count <= 2,
              Set(response.balance_infos.map(\.currency)).count == response.balance_infos.count else {
            throw DeepSeekBalanceFailure.malformed
        }
        let amounts = try response.balance_infos.map { row in
            guard ["CNY", "USD"].contains(row.currency), row.total_balance.count <= 50,
                  row.total_balance.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let amount = Decimal(string: row.total_balance, locale: Locale(identifier: "en_US_POSIX")) else {
                throw DeepSeekBalanceFailure.malformed
            }
            return DeepSeekBalanceSnapshot.Amount(currency: row.currency, total: NSDecimalNumber(decimal: amount).stringValue)
        }
        return DeepSeekBalanceSnapshot(amounts: amounts, isAvailable: response.is_available, fetchedAt: date)
    }
    func fetch(endpoint: String, key: String, now: Date = Date()) async throws -> DeepSeekBalanceSnapshot {
        let url = try Self.balanceURL(for: endpoint)
        guard !key.isEmpty else { throw DeepSeekBalanceFailure.missingKey }
        let identity = Identity(endpoint: endpoint, key: key)
        if let cached, cached.identity == identity,
           now.timeIntervalSince(cached.snapshot.fetchedAt) >= 0,
           now.timeIntervalSince(cached.snapshot.fetchedAt) < Self.cacheLifetime { return cached.snapshot }
        if let failed, failed.identity == identity, now.timeIntervalSince(failed.at) >= 0,
           now.timeIntervalSince(failed.at) < 10 { throw failed.error }
        if let pending, pending.identity == identity { return try await pending.task.value }
        let requestID = UUID()
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let transport = self.transport
        let task = Task {
            let (data, response) = try await transport(request)
            try Task.checkCancellation()
            guard (200..<300).contains(response.statusCode) else { throw DeepSeekBalanceFailure.http(response.statusCode) }
            return try Self.decode(data, at: now)
        }
        pending = (requestID, identity, task)
        defer { if pending?.id == requestID { pending = nil } }
        do {
            let snapshot = try await task.value
            if pending?.id == requestID { cached = (identity, snapshot); failed = nil }
            return snapshot
        } catch {
            if pending?.id == requestID { failed = (identity, now, error) }
            throw error
        }
    }
}
