import Foundation

enum TestLanguage { case simplifiedChinese, traditionalChinese, english }
@MainActor final class LocalizationManager {
    static let shared = LocalizationManager()
    var resolved: TestLanguage = .english
}

@main struct BalanceTests {
    @MainActor static func main() async throws {
        func check(_ value: Bool, _ message: String) { precondition(value, message) }
        let endpoint = "https://api.deepseek.com/v1/chat/completions"
        let balanceURL = try DeepSeekBalance.balanceURL(for: endpoint)
        check(balanceURL.absoluteString == "https://api.deepseek.com/user/balance", "Wrong balance path")
        for address in ["http://api.deepseek.com/chat/completions", "https://api.deepseek.com.evil.com/chat/completions", "https://elsewhere.com/chat", "https://user@api.deepseek.com/chat", "https://api.deepseek.com:444/chat", "https://api.deepseek.com/chat?key=secret"] {
            do { _ = try DeepSeekBalance.balanceURL(for: address); fatalError("Accepted untrusted destination") } catch {}
        }
        let sample = Data(#"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"23.50","granted_balance":"0","topped_up_balance":"23.50"}]}"#.utf8)
        let stamp = Date(timeIntervalSince1970: 1000)
        let decoded = try DeepSeekBalance.decode(sample, at: stamp)
        check(decoded.displayAmount == "¥23.5" && decoded.fetchedAt == stamp, "Balance or timestamp incorrect")
        let dollars = try DeepSeekBalance.decode(Data(#"{"is_available":false,"balance_infos":[{"currency":"USD","total_balance":"0.001"}]}"#.utf8), at: stamp)
        check(dollars.displayAmount.contains("0.001") && !dollars.isAvailable, "Fractional balance/availability lost")
        for malformed in [#"{"is_available":true,"balance_infos":[]}"#, #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"NaN"}]}"#, #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"12oops"}]}"#] {
            do { _ = try DeepSeekBalance.decode(Data(malformed.utf8), at: stamp); fatalError("Accepted malformed balance") } catch {}
        }
        var count = 0
        let service = DeepSeekBalance { request in
            count += 1
            check(request.url == balanceURL && request.httpMethod == "GET", "Wrong request")
            check(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer test-") == true, "Missing auth")
            check(request.httpBody == nil, "Balance request sent chat history")
            return (sample, HTTPURLResponse(url: balanceURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await service.fetch(endpoint: endpoint, key: "test-one", now: stamp)
        _ = try await service.fetch(endpoint: endpoint, key: "test-one", now: stamp.addingTimeInterval(59))
        check(count == 1, "Cache missed")
        _ = try await service.fetch(endpoint: endpoint, key: "test-one", now: stamp.addingTimeInterval(60))
        check(count == 2, "Expired result reused")
        _ = try await service.fetch(endpoint: endpoint, key: "test-two", now: stamp.addingTimeInterval(61))
        check(count == 3, "Credential change reused another account's balance")
        do { _ = try await service.fetch(endpoint: endpoint, key: "", now: stamp); fatalError("Accepted empty key") } catch {}
        check(count == 3, "Missing key caused request")
        var concurrentCount = 0
        let coalesced = DeepSeekBalance { _ in
            concurrentCount += 1
            try await Task.sleep(for: .milliseconds(50))
            return (sample, HTTPURLResponse(url: balanceURL, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        async let a = coalesced.fetch(endpoint: endpoint, key: "test-one", now: stamp)
        async let b = coalesced.fetch(endpoint: endpoint, key: "test-one", now: stamp)
        _ = try await (a, b)
        check(concurrentCount == 1, "Rapid clicks duplicated requests")
        var failureCount = 0
        let failed = DeepSeekBalance { _ in
            failureCount += 1
            return (Data("private server response".utf8), HTTPURLResponse(url: balanceURL, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        for offset: Double in [0, 5, 10] {
            do { _ = try await failed.fetch(endpoint: endpoint, key: "test-one", now: stamp.addingTimeInterval(offset)); fatalError("HTTP error hidden") }
            catch {
                check(error.localizedDescription == "HTTP 401", "Error leaked server response")
            }
        }
        check(failureCount == 2, "Failed request cooldown broken")
        var expireCount = 0
        let expires = DeepSeekBalance { _ in
            expireCount += 1
            return (sample, HTTPURLResponse(url: balanceURL, statusCode: expireCount == 1 ? 200 : 503, httpVersion: nil, headerFields: nil)!)
        }
        _ = try await expires.fetch(endpoint: endpoint, key: "test-one", now: stamp)
        do { _ = try await expires.fetch(endpoint: endpoint, key: "test-one", now: stamp.addingTimeInterval(61)); fatalError("Stale balance shown on network failure") } catch {}
        print("PASS: official-only destination, decimal balances, timestamps, availability, malformed data, cache expiry, credential isolation, rapid-click coalescing, HTTP errors, failure cooldown, stale-result rejection")
    }
}
