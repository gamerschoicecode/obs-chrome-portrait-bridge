import Foundation
import Security

enum AuthToken {
  private static let defaultsKey = "obsChromePortraitBridge.authToken"

  static func current() -> String {
    let existing = UserDefaults.standard.string(forKey: defaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if existing.count >= 24 { return existing }
    let minted = mint()
    UserDefaults.standard.set(minted, forKey: defaultsKey)
    return minted
  }

  static func rotate() -> String {
    let minted = mint()
    UserDefaults.standard.set(minted, forKey: defaultsKey)
    return minted
  }

  static func matches(_ provided: String?) -> Bool {
    let want = Data(current().utf8)
    let got = Data((provided ?? "").utf8)
    guard want.count == got.count, !want.isEmpty else { return false }
    return want.withUnsafeBytes { wantBuf in
      got.withUnsafeBytes { gotBuf in
        guard let wantBase = wantBuf.bindMemory(to: UInt8.self).baseAddress,
              let gotBase = gotBuf.bindMemory(to: UInt8.self).baseAddress else {
          return false
        }
        return timingsafe_bcmp(wantBase, gotBase, want.count) == 0
      }
    }
  }

  private static func mint() -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    if status != errSecSuccess {
      bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}
