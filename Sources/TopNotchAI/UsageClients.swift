import Foundation
import Security

enum UsageService {
    static func fetch(_ provider: ProviderID) async -> ProviderUsage {
        do {
            let windows: [UsageWindow]
            switch provider {
            case .anthropic: windows = try await fetchAnthropic()
            case .openAI: windows = try await fetchOpenAI()
            case .grok: windows = try await fetchGrok()
            }
            return ProviderUsage(provider: provider, windows: windows, message: nil, refreshedAt: Date())
        } catch {
            if provider == .openAI, let local = try? CodexLocalUsageReader.read() {
                return ProviderUsage(provider: provider, windows: local, message: "From latest Codex session", refreshedAt: Date())
            }
            return .failed(provider, message: (error as? LocalizedError)?.errorDescription ?? "Refresh failed")
        }
    }

    private static func fetchAnthropic() async throws -> [UsageWindow] {
        let token = try ClaudeCredential.readAccessToken()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let data = try await requestData(request, provider: .anthropic)
        return try UsageParsers.anthropic(data)
    }

    private static func fetchOpenAI() async throws -> [UsageWindow] {
        let auth = try JSONCredential.read(path: ".codex/auth.json", provider: .openAI)
        let tokens = auth["tokens"] as? [String: Any] ?? [:]
        guard let token = tokens["access_token"] as? String, !token.isEmpty else {
            throw UsageClientError.notSignedIn(.openAI)
        }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let account = tokens["account_id"] as? String, !account.isEmpty {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let data = try await requestData(request, provider: .openAI)
        return try UsageParsers.openAI(data)
    }

    private static func fetchGrok() async throws -> [UsageWindow] {
        let auth = try JSONCredential.read(path: ".grok/auth.json", provider: .grok)
        let entries = auth.values.compactMap { $0 as? [String: Any] }
        let selected = entries.compactMap { entry -> (String, String)? in
            guard let token = (entry["key"] as? String) ?? (entry["access_token"] as? String), !token.isEmpty else { return nil }
            return (token, entry["create_time"] as? String ?? "")
        }.max(by: { $0.1 < $1.1 })
        guard let token = selected?.0 else { throw UsageClientError.notSignedIn(.grok) }

        func request(_ url: String) async throws -> Data {
            var request = URLRequest(url: URL(string: url)!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("cli", forHTTPHeaderField: "x-grok-client-mode")
            return try await requestData(request, provider: .grok)
        }

        async let creditsResult = request("https://cli-chat-proxy.grok.com/v1/billing?format=credits")
        async let monthlyResult = request("https://cli-chat-proxy.grok.com/v1/billing")

        var windows: [UsageWindow] = []
        if let credits = try? await creditsResult {
            windows.append(contentsOf: (try? UsageParsers.grokCredits(credits)) ?? [])
        }
        if let monthly = try? await monthlyResult,
           let window = try? UsageParsers.grokMonthly(monthly),
           !windows.contains(where: { $0.id == window.id }) {
            windows.append(window)
        }
        guard !windows.isEmpty else { throw UsageClientError.invalidResponse(.grok) }
        return windows
    }

    private static func requestData(_ request: URLRequest, provider: ProviderID) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.invalidResponse(provider) }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageClientError.expired(provider) }
        guard http.statusCode == 200 else { throw UsageClientError.http(provider, http.statusCode) }
        return data
    }
}

private enum ClaudeCredential {
    static func readAccessToken() throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        if status != errSecSuccess {
            query[kSecAttrAccount as String] = NSUserName()
            status = SecItemCopyMatching(query as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              !token.isEmpty else {
            throw UsageClientError.notSignedIn(.anthropic)
        }
        return token
    }
}

private enum JSONCredential {
    static func read(path: String, provider: ProviderID) throws -> [String: Any] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageClientError.notSignedIn(provider)
        }
        return root
    }
}

enum CodexLocalUsageReader {
    static func read() throws -> [UsageWindow] {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { throw UsageClientError.notSignedIn(.openAI) }

        var newest: (URL, Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if newest == nil || date > newest!.1 { newest = (url, date) }
        }
        guard let url = newest?.0 else { throw UsageClientError.invalidResponse(.openAI) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let start = size > 262_144 ? size - 262_144 : 0
        try handle.seek(toOffset: start)
        let tail = try handle.readToEnd() ?? Data()
        guard let text = String(data: tail, encoding: .utf8) else { throw UsageClientError.invalidResponse(.openAI) }

        for line in text.split(separator: "\n").reversed() {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let rateLimits = findRateLimits(in: object),
                  let encoded = try? JSONSerialization.data(withJSONObject: ["rate_limits": rateLimits]),
                  let windows = try? UsageParsers.openAI(encoded), !windows.isEmpty else { continue }
            return windows
        }
        throw UsageClientError.invalidResponse(.openAI)
    }

    private static func findRateLimits(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let result = dictionary["rate_limits"] as? [String: Any] { return result }
            for nested in dictionary.values {
                if let result = findRateLimits(in: nested) { return result }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let result = findRateLimits(in: nested) { return result }
            }
        }
        return nil
    }
}
