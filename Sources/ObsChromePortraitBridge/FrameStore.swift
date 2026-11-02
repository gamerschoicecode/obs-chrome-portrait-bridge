import Foundation

final class FrameStore {
  private let lock = NSLock()
  private var jpeg = Data()
  private var width = 0
  private var height = 0
  private var updatedAt = Date.distantPast
  private var source = "OBS Virtual Camera"
  private var status = "starting"
  private var detail = ""

  func publish(jpeg: Data, width: Int, height: Int, source: String) {
    lock.lock()
    self.jpeg = jpeg
    self.width = width
    self.height = height
    self.source = source
    self.updatedAt = Date()
    self.status = "capturing"
    self.detail = ""
    lock.unlock()
  }

  func setStatus(_ status: String, detail: String = "") {
    lock.lock()
    self.status = status
    self.detail = detail
    lock.unlock()
  }

  func snapshot() -> (
    jpeg: Data,
    width: Int,
    height: Int,
    updatedAt: Date,
    source: String,
    status: String,
    detail: String
  ) {
    lock.lock()
    defer { lock.unlock() }
    return (jpeg, width, height, updatedAt, source, status, detail)
  }
}
