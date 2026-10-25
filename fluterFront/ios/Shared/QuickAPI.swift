import Foundation

public enum QuickAPIError: Error, Equatable {
  case notConnected
  case network
  case server(status: Int, code: String?, message: String, params: [String: String])
}

public struct QuickAPI {
  public let base: URL
  public let key: String

  public init(base: URL, key: String) {
    self.base = base
    self.key = key
  }

  public static func fromStore() -> QuickAPI? {
    guard let key = DeviceKeyStore.readKey(accessGroup: CareCoinsShared.keychainAccessGroup),
          !key.isEmpty else {
      return nil
    }
    let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
    guard let apiBase = defaults?.string(forKey: CareCoinsShared.apiBaseDefault),
          !apiBase.isEmpty else {
      return nil
    }
    let trimmed = apiBase.hasSuffix("/") ? String(apiBase.dropLast()) : apiBase
    guard let url = URL(string: trimmed) else {
      return nil
    }
    return QuickAPI(base: url, key: key)
  }

  public static func newClientRef() -> String {
    UUID().uuidString
  }

  private func endpointURL(_ path: String) -> URL {
    let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
    let baseString = base.absoluteString.hasSuffix("/") ? String(base.absoluteString.dropLast()) : base.absoluteString
    return URL(string: "\(baseString)/\(cleanPath)") ?? base.appendingPathComponent(cleanPath)
  }

  private func makeRequest(endpoint: String, method: String, body: [String: Any]? = nil) throws -> URLRequest {
    let url = endpointURL(endpoint)
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 15.0
    request.setValue("Device \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let body = body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
    }
    return request
  }

  private func send(request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw QuickAPIError.network
    }
    guard let httpResponse = response as? HTTPURLResponse else {
      throw QuickAPIError.network
    }

    if httpResponse.statusCode == 401 {
      CareCoinsShared.disconnectLocally()
      let (code, msg, params) = parseErrorBody(data: data, defaultStatus: 401)
      throw QuickAPIError.server(status: 401, code: code, message: msg, params: params)
    }

    if !(200...299).contains(httpResponse.statusCode) {
      let (code, msg, params) = parseErrorBody(data: data, defaultStatus: httpResponse.statusCode)
      throw QuickAPIError.server(status: httpResponse.statusCode, code: code, message: msg, params: params)
    }

    return (data, httpResponse)
  }

  private func parseErrorBody(data: Data, defaultStatus: Int) -> (code: String?, message: String, params: [String: String]) {
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      let str = String(data: data, encoding: .utf8) ?? "HTTP \(defaultStatus)"
      return (nil, str, [:])
    }
    let message = (json["error"] as? String) ?? "HTTP \(defaultStatus)"
    let code = json["code"] as? String
    var params: [String: String] = [:]
    if let rawParams = json["params"] as? [String: Any] {
      for (k, v) in rawParams {
        params[k] = String(describing: v)
      }
    }
    return (code, message, params)
  }

  public func snapshot() async throws -> (QuickSnapshot, Data) {
    let request = try makeRequest(endpoint: "/api/quick", method: "GET")
    let (data, _) = try await send(request: request)
    do {
      let snap = try JSONDecoder.quick.decode(QuickSnapshot.self, from: data)
      return (snap, data)
    } catch {
      throw QuickAPIError.network
    }
  }

  public func start(templateId: String, clientRef: String) async throws -> QuickActionResult {
    guard let idNum = Int(templateId) else {
      throw QuickAPIError.network
    }
    let body: [String: Any] = [
      "templateId": idNum,
      "clientRef": clientRef
    ]
    let request = try makeRequest(endpoint: "/api/quick/start", method: "POST", body: body)
    let (data, _) = try await send(request: request)
    return try JSONDecoder.quick.decode(QuickActionResult.self, from: data)
  }

  public func startNow(type: String, title: String, clientRef: String) async throws -> QuickActionResult {
    let body: [String: Any] = [
      "type": type,
      "title": title,
      "clientRef": clientRef
    ]
    let request = try makeRequest(endpoint: "/api/quick/start", method: "POST", body: body)
    let (data, _) = try await send(request: request)
    return try JSONDecoder.quick.decode(QuickActionResult.self, from: data)
  }

  public func done(templateId: String, clientRef: String) async throws -> QuickActionResult {
    guard let idNum = Int(templateId) else {
      throw QuickAPIError.network
    }
    let body: [String: Any] = [
      "templateId": idNum,
      "clientRef": clientRef
    ]
    let request = try makeRequest(endpoint: "/api/quick/done", method: "POST", body: body)
    let (data, _) = try await send(request: request)
    return try JSONDecoder.quick.decode(QuickActionResult.self, from: data)
  }

  public func finish(activityId: String) async throws -> QuickActionResult {
    guard let idNum = Int(activityId) else {
      throw QuickAPIError.network
    }
    let body: [String: Any] = [
      "activityId": idNum
    ]
    let request = try makeRequest(endpoint: "/api/quick/done", method: "POST", body: body)
    let (data, _) = try await send(request: request)
    return try JSONDecoder.quick.decode(QuickActionResult.self, from: data)
  }

  public func stop(activityId: String) async throws -> QuickActionResult {
    guard let idNum = Int(activityId) else {
      throw QuickAPIError.network
    }
    let body: [String: Any] = [
      "activityId": idNum
    ]
    let request = try makeRequest(endpoint: "/api/quick/stop", method: "POST", body: body)
    let (data, _) = try await send(request: request)
    return try JSONDecoder.quick.decode(QuickActionResult.self, from: data)
  }

  public func undo(clientRef: String) async throws -> QuickActionResult {
    let body: [String: Any] = [
      "clientRef": clientRef
    ]
    let request = try makeRequest(endpoint: "/api/quick/undo", method: "POST", body: body)
    let (data, _) = try await send(request: request)
    return try JSONDecoder.quick.decode(QuickActionResult.self, from: data)
  }
}
