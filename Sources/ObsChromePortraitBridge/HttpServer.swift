import Foundation

final class HttpServer {
  private let store: FrameStore
  private let port: UInt16
  private var serverFD: Int32 = -1
  private let queue = DispatchQueue(label: "obs.chrome.portrait.bridge.http", attributes: .concurrent)
  private var running = false

  init(store: FrameStore, port: UInt16) {
    self.store = store
    self.port = port
  }

  func start() throws {
    serverFD = socket(AF_INET, SOCK_STREAM, 0)
    guard serverFD >= 0 else {
      throw NSError(domain: "ObsChromePortraitBridge", code: 10, userInfo: [
        NSLocalizedDescriptionKey: "Could not create socket",
      ])
    }
    var yes: Int32 = 1
    setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bindResult == 0 else {
      close(serverFD)
      serverFD = -1
      throw NSError(domain: "ObsChromePortraitBridge", code: 11, userInfo: [
        NSLocalizedDescriptionKey: "Could not bind 127.0.0.1:\(port)",
      ])
    }
    guard listen(serverFD, 16) == 0 else {
      close(serverFD)
      serverFD = -1
      throw NSError(domain: "ObsChromePortraitBridge", code: 12, userInfo: [
        NSLocalizedDescriptionKey: "Could not listen on \(port)",
      ])
    }
    running = true
    queue.async { [weak self] in
      self?.acceptLoop()
    }
  }

  func stop() {
    running = false
    if serverFD >= 0 {
      close(serverFD)
      serverFD = -1
    }
  }

  private func acceptLoop() {
    while running {
      var addr = sockaddr_in()
      var len: socklen_t = socklen_t(MemoryLayout<sockaddr_in>.size)
      let client = withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          accept(serverFD, $0, &len)
        }
      }
      if client < 0 {
        if running { usleep(20_000) }
        continue
      }
      queue.async { [weak self] in
        self?.handle(client: client)
      }
    }
  }

  private func handle(client: Int32) {
    defer { close(client) }
    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let n = read(client, &chunk, chunk.count)
      if n <= 0 { return }
      buffer.append(contentsOf: chunk[0..<n])
      if buffer.range(of: Data([13, 10, 13, 10])) != nil { break }
      if buffer.count > 64 * 1024 { return }
    }
    let head = String(data: buffer, encoding: .utf8) ?? ""
    let requestLine = head.split(separator: "\r\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let parts = requestLine.split(separator: " ")
    let method = parts.first.map(String.init) ?? "GET"
    let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? parts[1]) : "/"
    if method == "OPTIONS" {
      writeResponse(client, status: 204, reason: "No Content", contentType: "text/plain", body: Data(), headOnly: true)
      return
    }
    let headOnly = method == "HEAD"
    switch path {
    case "/", "/health":
      let snap = store.snapshot()
      let ageMs = snap.jpeg.isEmpty ? NSNull() : Int(Date().timeIntervalSince(snap.updatedAt) * 1000) as Any
      let ok = !snap.jpeg.isEmpty
      let payload: [String: Any] = [
        "ok": ok,
        "version": BridgeVersion.version,
        "protocol": BridgeVersion.protocolNumber,
        "app": BridgeVersion.appName,
        "port": Int(port),
        "width": snap.width,
        "height": snap.height,
        "ageMs": ageMs,
        "source": snap.source,
        "status": snap.status,
        "detail": snap.detail,
      ]
      let body = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
      writeResponse(
        client,
        status: ok ? 200 : 503,
        reason: ok ? "OK" : "Service Unavailable",
        contentType: "application/json; charset=utf-8",
        body: body,
        headOnly: headOnly
      )
    case "/frame.jpg":
      let snap = store.snapshot()
      if snap.jpeg.isEmpty {
        writeResponse(client, status: 503, reason: "Service Unavailable", contentType: "text/plain; charset=utf-8", body: Data("no frame yet".utf8), headOnly: headOnly)
      } else {
        writeResponse(client, status: 200, reason: "OK", contentType: "image/jpeg", body: snap.jpeg, headOnly: headOnly)
      }
    case "/version":
      let body = Data("""
      {"version":"\(BridgeVersion.version)","protocol":\(BridgeVersion.protocolNumber),"app":"\(BridgeVersion.appName)"}
      """.utf8)
      writeResponse(client, status: 200, reason: "OK", contentType: "application/json; charset=utf-8", body: body, headOnly: headOnly)
    default:
      writeResponse(client, status: 404, reason: "Not Found", contentType: "text/plain; charset=utf-8", body: Data("not found".utf8), headOnly: headOnly)
    }
  }

  private func writeResponse(
    _ client: Int32,
    status: Int,
    reason: String,
    contentType: String,
    body: Data,
    headOnly: Bool
  ) {
    var header = "HTTP/1.1 \(status) \(reason)\r\n"
    header += "Content-Type: \(contentType)\r\n"
    header += "Content-Length: \(body.count)\r\n"
    header += "Access-Control-Allow-Origin: *\r\n"
    header += "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n"
    header += "Cache-Control: no-store\r\n"
    header += "Connection: close\r\n\r\n"
    var payload = Data(header.utf8)
    if !headOnly {
      payload.append(body)
    }
    payload.withUnsafeBytes { raw in
      guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
      var sent = 0
      while sent < payload.count {
        let n = write(client, base.advanced(by: sent), payload.count - sent)
        if n <= 0 { break }
        sent += n
      }
    }
  }
}
