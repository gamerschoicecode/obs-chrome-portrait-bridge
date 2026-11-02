import AVFoundation
import AppKit
import CoreImage
import Foundation

protocol CaptureServiceDelegate: AnyObject {
  func captureServiceDidUpdateStatus(_ text: String)
}

final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private enum Mode: String {
    case highQuality = "high"
    case nativeBuffers = "native"
  }

  weak var delegate: CaptureServiceDelegate?
  private let store: FrameStore
  private let session = AVCaptureSession()
  private let context = CIContext(options: [.useSoftwareRenderer: false])
  private let frameQueue = DispatchQueue(label: "obs.chrome.portrait.bridge.frames")
  private var lastSent = Date.distantPast
  private let minInterval: TimeInterval = 1.0 / 24.0
  private var retryTimer: DispatchSourceTimer?
  private var mode: Mode = .highQuality
  private var bestPixels = 0
  private var sawLandscapeScaled = false

  init(store: FrameStore) {
    self.store = store
  }

  func start() {
    stopRetry()
    do {
      try beginCapture(mode: mode)
    } catch {
      let message = error.localizedDescription
      store.setStatus("waiting", detail: message)
      delegate?.captureServiceDidUpdateStatus(message)
      scheduleRetry()
    }
  }

  func stop() {
    stopRetry()
    if session.isRunning {
      session.stopRunning()
    }
    session.inputs.forEach { session.removeInput($0) }
    session.outputs.forEach { session.removeOutput($0) }
  }

  private func scheduleRetry() {
    stopRetry()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
    timer.schedule(deadline: .now() + 2.0, repeating: 2.0)
    timer.setEventHandler { [weak self] in
      self?.start()
    }
    timer.resume()
    retryTimer = timer
  }

  private func stopRetry() {
    retryTimer?.cancel()
    retryTimer = nil
  }

  private func beginCapture(mode: Mode) throws {
    stop()
    self.mode = mode
    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.external, .builtInWideAngleCamera, .continuityCamera],
      mediaType: .video,
      position: .unspecified
    ).devices
    guard let obs = devices.first(where: { $0.localizedName.localizedCaseInsensitiveContains("obs") }) else {
      throw NSError(domain: "ObsChromePortraitBridge", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "OBS Virtual Camera not found. Start Virtual Camera in OBS.",
      ])
    }

    session.beginConfiguration()
    // Prefer the quality preset so macOS follows OBS sample-buffer size
    // (often 1080×1920). Never pin .hd1920x1080 — that forces a landscape
    // buffer and crop/scales the portrait canvas.
    if mode == .highQuality, session.canSetSessionPreset(.high) {
      session.sessionPreset = .high
    }

    let input = try AVCaptureDeviceInput(device: obs)
    guard session.canAddInput(input) else {
      throw NSError(domain: "ObsChromePortraitBridge", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "Could not open OBS Virtual Camera.",
      ])
    }
    session.addInput(input)

    if mode == .nativeBuffers {
      if let format = obs.formats.max(by: {
        let a = CMVideoFormatDescriptionGetDimensions($0.formatDescription)
        let b = CMVideoFormatDescriptionGetDimensions($1.formatDescription)
        return (a.width * a.height) < (b.width * b.height)
      }) {
        try obs.lockForConfiguration()
        obs.activeFormat = format
        obs.unlockForConfiguration()
      }
    }

    let output = AVCaptureVideoDataOutput()
    output.alwaysDiscardsLateVideoFrames = true
    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.setSampleBufferDelegate(self, queue: frameQueue)
    guard session.canAddOutput(output) else {
      throw NSError(domain: "ObsChromePortraitBridge", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "Could not attach video output.",
      ])
    }
    session.addOutput(output)
    session.commitConfiguration()
    session.startRunning()
    stopRetry()
    let label = "Capturing \(obs.localizedName) (\(mode.rawValue))"
    store.setStatus("capturing", detail: label)
    delegate?.captureServiceDidUpdateStatus(label)
  }

  private func maybeEscalate(from width: Int, height: Int) {
    let pixels = width * height
    if pixels > bestPixels {
      bestPixels = pixels
    }
    // Chrome-style landscape grab of a portrait canvas — switch modes.
    if width > height, mode == .highQuality, !sawLandscapeScaled {
      sawLandscapeScaled = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.mode = .nativeBuffers
        self.start()
      }
      return
    }
    // If we previously saw a larger frame and suddenly get a clear downscale
    // of the same portrait aspect (e.g. 360×640 vs 1080×1920), restart once
    // on the alternate mode to prefer the full canvas publish.
    guard height > width, bestPixels > 0, pixels > 0 else { return }
    let ratio = Double(bestPixels) / Double(pixels)
    if ratio >= 2.5, mode == .highQuality {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.mode = .nativeBuffers
        self.bestPixels = 0
        self.start()
      }
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    let now = Date()
    guard now.timeIntervalSince(lastSent) >= minInterval else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    maybeEscalate(from: width, height: height)

    // Never downscale before encode — publish the sample buffer as-is.
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cg = context.createCGImage(image, from: image.extent) else { return }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { return }
    lastSent = now
    store.publish(jpeg: data, width: width, height: height, source: "OBS Virtual Camera")
    let status = "Capturing \(width)×\(height)"
    DispatchQueue.main.async { [weak self] in
      self?.delegate?.captureServiceDidUpdateStatus(status)
    }
  }
}
