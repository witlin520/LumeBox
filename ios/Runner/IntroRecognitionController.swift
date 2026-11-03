import AVFoundation
import CoreML
import Flutter
import Network
import UIKit
import Vision
import os

/// A separate AVAsset, never the playing AVPlayer/MPV/MDK instance. All decode,
/// OCR and Core ML work is serialized on a utility queue and cancellable.
final class IntroRecognitionController {
  private let queue = DispatchQueue(label: "lumebox.reference.intro", qos: .utility)
  private let lock = NSLock()
  private var cancelled = Set<String>()
  private var assets: [String: AVURLAsset] = [:]
  private var generator: AVAssetImageGenerator?
  private var reader: AVAssetReader?
  private let monitor = NWPathMonitor()
  private var wifi = false
  private var imageModel: MLModel?
  private var modelRoot = ""
  private var textVectors: [(String, [Double])] = []

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self = self else { return }
      self.lock.lock(); self.wifi = path.status == .satisfied && path.usesInterfaceType(.wifi) && !path.isExpensive; self.lock.unlock()
    }
    monitor.start(queue: DispatchQueue(label: "lumebox.intro.network"))
  }
  deinit { monitor.cancel() }

  func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "lumebox/reference_intro", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any] ?? [:]
      let session = args["session"] as? String ?? ""
      if call.method == "resources" {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let foreground = UIApplication.shared.applicationState == .active
        let memoryOK = os_proc_available_memory() > 256 * 1024 * 1024
        self.lock.lock(); let wifi = self.wifi; self.lock.unlock()
        result(["allowed": foreground && !lowPower && thermal != .serious && thermal != .critical && memoryOK,
          "reason": !foreground ? "应用在后台" : lowPower ? "低电量模式" : !memoryOK ? "可用内存不足" : thermal == .serious || thermal == .critical ? "设备温控" : "",
          "wifi": wifi, "charging": UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full])
        return
      }
      if call.method == "cancel" {
        self.lock.lock(); self.cancelled.insert(session); let generator = self.generator; let reader = self.reader; self.lock.unlock()
        generator?.cancelAllCGImageGeneration(); reader?.cancelReading(); result(nil); return
      }
      self.queue.async {
        do {
          let value: Any?
          switch call.method {
          case "release":
            self.assets.removeValue(forKey: session)
            self.imageModel = nil; self.textVectors = []; self.modelRoot = ""
            self.lock.lock(); self.cancelled.remove(session); self.lock.unlock()
            value = nil
          case "metadata": value = try self.metadata(args, session)
          case "sample": value = try self.sample(args, session)
          case "classify": value = try self.classify(args, session)
          default: DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          // Never include media URLs or HTTP headers in diagnostic errors.
          DispatchQueue.main.async { result(FlutterError(code: "intro_scan", message: "Native scan unavailable or cancelled (\((error as NSError).code))", details: nil)) }
        }
      }
    }
  }
  private func check(_ session: String) throws {
    lock.lock(); let stopped = cancelled.contains(session); lock.unlock()
    if stopped || ProcessInfo.processInfo.isLowPowerModeEnabled || ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
      throw NSError(domain: "IntroScan", code: -999)
    }
  }
  private func asset(_ args: [String: Any], _ session: String) throws -> AVURLAsset {
    try check(session)
    if let asset = assets[session] { return asset }
    guard let raw = args["url"] as? String, let url = URL(string: raw), ["https", "http", "file"].contains(url.scheme ?? "") else { throw NSError(domain: "IntroScan", code: 1) }
    let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": args["headers"] as? [String: String] ?? [:]])
    assets[session] = asset
    return asset
  }
  private func metadata(_ args: [String: Any], _ session: String) throws -> [String: Any] {
    let asset = try asset(args, session)
    let semaphore = DispatchSemaphore(value: 0)
    asset.loadValuesAsynchronously(forKeys: ["availableChapterLocales", "availableMetadataFormats", "tracks", "duration"]) { semaphore.signal() }
    guard semaphore.wait(timeout: .now() + 7) == .success else { asset.cancelLoading(); throw NSError(domain: "IntroScan", code: 2) }
    try check(session)
    var chapters: [[String: Any]] = []
    for group in asset.chapterMetadataGroups(bestMatchingPreferredLanguages: ["zh", "en"]) {
      let title = group.items.compactMap { $0.stringValue }.joined(separator: " ")
      let start = group.timeRange.start.seconds, end = CMTimeRangeGetEnd(group.timeRange).seconds
      if start.isFinite && end.isFinite { chapters.append(["title": title, "startMs": Int(start * 1000), "endMs": Int(end * 1000)]) }
    }
    var tags: [[String: Any]] = []
    for format in asset.availableMetadataFormats {
      for item in asset.metadata(forFormat: format) {
        guard let title = item.stringValue, title.count < 400 else { continue }
        let start = item.time.seconds, span = item.duration.seconds
        if start.isFinite && span.isFinite && span > 0 { tags.append(["title": title, "startMs": Int(start * 1000), "endMs": Int((start + span) * 1000)]) }
      }
    }
    return ["chapters": chapters, "mkvTags": tags, "subtitles": try subtitles(asset, session)]
  }
  private func subtitles(_ asset: AVAsset, _ session: String) throws -> [[String: Any]] {
    let tracks = asset.tracks(withMediaType: .subtitle) + asset.tracks(withMediaType: .text)
    guard let track = tracks.first else { return [] }
    let duration = asset.duration.seconds
    guard duration.isFinite && duration > 0 else { return [] }
    var result: [[String: Any]] = []
    let started = Date()
    for start in [0.0, max(0, duration - 240)] {
      try check(session)
      let reader = try AVAssetReader(asset: asset)
      let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      output.alwaysCopiesSampleData = false
      guard reader.canAdd(output) else { continue }
      reader.add(output); reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: min(240, duration - start), preferredTimescale: 600))
      guard reader.startReading() else { continue }
      defer { reader.cancelReading() }
      while result.count < 240 && Date().timeIntervalSince(started) < 2, let sample = output.copyNextSampleBuffer() {
        try check(session)
        guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
        let size = min(CMBlockBufferGetDataLength(block), 8192)
        var bytes = Data(count: size)
        _ = bytes.withUnsafeMutableBytes { ptr in CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: ptr.baseAddress!) }
        let text = String(data: bytes, encoding: .utf8) ?? String(data: bytes.dropFirst(min(2, bytes.count)), encoding: .utf8) ?? ""
        let at = CMSampleBufferGetPresentationTimeStamp(sample).seconds, span = CMSampleBufferGetDuration(sample).seconds
        if !text.isEmpty && at.isFinite && span.isFinite && span > 0 { result.append(["title": text, "startMs": Int(at * 1000), "endMs": Int((at + span) * 1000)]) }
      }
    }
    return result
  }
  private func sample(_ args: [String: Any], _ session: String) throws -> [String: Any] {
    let asset = try asset(args, session)
    let at = Double((args["atMs"] as? NSNumber)?.intValue ?? 0) / 1000
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 384, height: 384)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 0.25, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.25, preferredTimescale: 600)
    lock.lock(); self.generator = generator; lock.unlock()
    defer { lock.lock(); self.generator = nil; lock.unlock() }
    var actual = CMTime.zero
    let image = try generator.copyCGImage(at: CMTime(seconds: at, preferredTimescale: 600), actualTime: &actual)
    try check(session)
    var pixels = [UInt8](repeating: 0, count: 1024)
    let rendered = pixels.withUnsafeMutableBytes { ptr -> Bool in
      guard let context = CGContext(data: ptr.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
      context.interpolationQuality = .medium; context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32)); return true
    }
    guard rendered else { throw NSError(domain: "IntroScan", code: 3) }
    var result: [String: Any] = ["atMs": actual.seconds.isFinite ? Int(actual.seconds * 1000) : Int(at * 1000), "gray": FlutterStandardTypedData(bytes: Data(pixels))]
    if args["jpeg"] as? Bool == true, let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.65) { result["jpeg"] = FlutterStandardTypedData(bytes: jpeg) }
    if args["ocr"] as? Bool == true {
      let request = VNRecognizeTextRequest(); request.recognitionLevel = .fast; request.usesLanguageCorrection = false
      request.recognitionLanguages = ["zh-Hans", "en-US"]
      do { try VNImageRequestHandler(cgImage: image).perform([request]) }
      catch { result["ocrError"] = true }
      let observations = request.results ?? []
      result["text"] = observations.prefix(40).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
      result["lines"] = observations.prefix(40).compactMap { observation -> [String: Any]? in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        return ["text": text, "y": 1 - observation.boundingBox.maxY]
      }
      if let first = observations.first { result["textY"] = 1 - first.boundingBox.maxY }
    }
    if args["audio"] as? Bool == true {
      do { result["pcm"] = FlutterStandardTypedData(bytes: try pcm(asset, at, session)) }
      catch { result["audioError"] = true }
    }
    return result
  }
  private func pcm(_ asset: AVAsset, _ at: Double, _ session: String) throws -> Data {
    let tracks = asset.tracks(withMediaType: .audio)
    guard !tracks.isEmpty else { return Data() }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderAudioMixOutput(audioTracks: [tracks[0]], audioSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { return Data() }
    reader.add(output); reader.timeRange = CMTimeRange(start: CMTime(seconds: at, preferredTimescale: 600), duration: CMTime(seconds: 0.975, preferredTimescale: 16000))
    lock.lock(); self.reader = reader; lock.unlock()
    defer { reader.cancelReading(); lock.lock(); self.reader = nil; lock.unlock() }
    guard reader.startReading() else { return Data() }
    var data = Data()
    while data.count < 15600 * 4, let sample = output.copyNextSampleBuffer() {
      try check(session)
      guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
      let size = min(CMBlockBufferGetDataLength(block), 15600 * 4 - data.count)
      var bytes = Data(count: size)
      let status = bytes.withUnsafeMutableBytes { ptr in CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: ptr.baseAddress!) }
      if status == kCMBlockBufferNoErr { data.append(bytes) }
    }
    return data
  }
  private struct AnchorVectors: Decodable {
    let format: String
    let revision: String
    let promptsSha256: String
    let dimension: Int
    let vectors: [String: [[Double]]]
    func validated(_ promptHash: String?) throws -> [(String, [Double])] {
      guard format == "lumebox.intro.anchors.v1",
        revision == "3e0a7bfb9fe83da8a3efaa3fd8f7df24214bb947",
        promptsSha256 == promptHash, dimension == 512,
        Set(vectors.keys) == Set(["recap", "opening", "main", "ending"]),
        vectors.values.allSatisfy({ examples in
          examples.count == 2 && examples.allSatisfy { vector in
            vector.count == dimension && vector.allSatisfy { $0.isFinite } && vector.contains { $0 != 0 }
          }
        }) else { throw NSError(domain: "IntroModel", code: 12) }
      return vectors.keys.sorted().flatMap { label in vectors[label]!.map { (label, $0) } }
    }
  }
  private func loadModels(_ root: String, _ prompts: [String: [[Int]]], _ promptHash: String?) throws {
    if modelRoot == root && imageModel != nil && !textVectors.isEmpty { return }
    let config = MLModelConfiguration()
    if #available(iOS 16.0, *) { config.computeUnits = .cpuAndNeuralEngine } else { config.computeUnits = .cpuOnly }
    func load(_ name: String) throws -> MLModel {
      let base = URL(fileURLWithPath: root).appendingPathComponent(name)
      let compiled = base.appendingPathExtension("mlmodelc")
      if !FileManager.default.fileExists(atPath: compiled.path) {
        let temporary = try MLModel.compileModel(at: base.appendingPathExtension("mlpackage"))
        try FileManager.default.moveItem(at: temporary, to: compiled)
      }
      return try MLModel(contentsOf: compiled, configuration: config)
    }
    // Bundled prompts use verified build-time embeddings from the same pinned
    // text encoder. Retain full-pair loading for existing custom model imports.
    let anchors = URL(fileURLWithPath: root).appendingPathComponent("anchor_vectors.json")
    if FileManager.default.fileExists(atPath: anchors.path) {
      let stored = try JSONDecoder().decode(AnchorVectors.self, from: Data(contentsOf: anchors))
      let vectors = try stored.validated(promptHash)
      imageModel = try load("mobileclip_s0_image"); textVectors = vectors; modelRoot = root
      return
    }
    let text = try load("mobileclip_s0_text")
    var vectors: [(String, [Double])] = []
    for (label, examples) in prompts {
      for tokens in examples where tokens.count == 77 {
        let input = try MLMultiArray(shape: [1, 77], dataType: .int32)
        for i in 0..<77 { input[i] = NSNumber(value: tokens[i]) }
        let prediction = try text.prediction(from: MLDictionaryFeatureProvider(dictionary: ["text": MLFeatureValue(multiArray: input)]))
        guard let value = prediction.featureValue(for: "final_emb_1")?.multiArrayValue else { throw NSError(domain: "IntroModel", code: 4) }
        vectors.append((label, (0..<value.count).map { value[$0].doubleValue }))
      }
    }
    guard vectors.count >= 4 else { throw NSError(domain: "IntroModel", code: 5) }
    imageModel = try load("mobileclip_s0_image"); textVectors = vectors; modelRoot = root
  }
  private func classify(_ args: [String: Any], _ session: String) throws -> [String: Double] {
    try check(session)
    guard let root = args["root"] as? String, let prompts = args["prompts"] as? [String: [[Int]]], let data = args["jpeg"] as? FlutterStandardTypedData, let image = UIImage(data: data.data)?.cgImage else { throw NSError(domain: "IntroModel", code: 6) }
    let customPackage = URL(fileURLWithPath: root).appendingPathComponent("segment_classifier.mlpackage")
    let customFile = URL(fileURLWithPath: root).appendingPathComponent("segment_classifier.mlmodel")
    if FileManager.default.fileExists(atPath: customPackage.path) || FileManager.default.fileExists(atPath: customFile.path) {
      if modelRoot != root || imageModel == nil {
        let compiled = URL(fileURLWithPath: root).appendingPathComponent("segment_classifier.mlmodelc")
        if !FileManager.default.fileExists(atPath: compiled.path) {
          let temp = try MLModel.compileModel(at: FileManager.default.fileExists(atPath: customPackage.path) ? customPackage : customFile)
          try FileManager.default.moveItem(at: temp, to: compiled)
        }
        let config = MLModelConfiguration()
        if #available(iOS 16.0, *) { config.computeUnits = .cpuAndNeuralEngine } else { config.computeUnits = .cpuOnly }
        imageModel = try MLModel(contentsOf: compiled, configuration: config); modelRoot = root; textVectors = []
      }
      let request = VNCoreMLRequest(model: try VNCoreMLModel(for: imageModel!))
      request.imageCropAndScaleOption = .centerCrop
      try VNImageRequestHandler(cgImage: image).perform([request])
      guard let values = request.results as? [VNClassificationObservation] else { throw NSError(domain: "IntroModel", code: 10) }
      let allowed = Set(["recap", "opening", "main", "ending"])
      var scores: [String: Double] = [:]
      for value in values where allowed.contains(value.identifier) { scores[value.identifier] = Double(value.confidence) }
      guard scores.count == 4 else { throw NSError(domain: "IntroModel", code: 11) }
      return scores
    }
    try loadModels(root, prompts, args["promptsSha256"] as? String)
    try check(session)
    guard let model = imageModel, let constraint = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint else { throw NSError(domain: "IntroModel", code: 7) }
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, constraint.pixelsWide, constraint.pixelsHigh, kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &buffer)
    guard let pixels = buffer else { throw NSError(domain: "IntroModel", code: 8) }
    CVPixelBufferLockBaseAddress(pixels, [])
    if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: constraint.pixelsWide, height: constraint.pixelsHigh, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
      let edge = min(image.width, image.height)
      let rect = CGRect(x: CGFloat(image.width - edge) / 2, y: CGFloat(image.height - edge) / 2, width: CGFloat(edge), height: CGFloat(edge))
      context.draw(image.cropping(to: rect) ?? image, in: CGRect(x: 0, y: 0, width: CGFloat(constraint.pixelsWide), height: CGFloat(constraint.pixelsHigh)))
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: pixels)]))
    guard let values = prediction.featureValue(for: "final_emb_1")?.multiArrayValue else { throw NSError(domain: "IntroModel", code: 9) }
    let embedding = (0..<values.count).map { values[$0].doubleValue }
    let norm = sqrt(embedding.reduce(0) { $0 + $1 * $1 })
    var logits: [String: [Double]] = [:]
    for (label, vector) in textVectors where vector.count == embedding.count {
      let denominator = norm * sqrt(vector.reduce(0) { $0 + $1 * $1 })
      let cosine = zip(embedding, vector).reduce(0) { $0 + $1.0 * $1.1 } / max(denominator, 1e-12)
      logits[label, default: []].append(cosine * 100)
    }
    let means = logits.mapValues { $0.reduce(0, +) / Double($0.count) }
    let maxLogit = means.values.max() ?? 0
    let expScores = means.mapValues { exp($0 - maxLogit) }, total = means.values.reduce(0) { $0 + exp($1 - maxLogit) }
    return expScores.mapValues { $0 / max(total, 1e-12) }
  }
}
