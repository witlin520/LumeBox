import Flutter
import UIKit
import Vision
import ImageIO
import CoreML
import CryptoKit
import Security
import SwiftUI
import NaturalLanguage
#if canImport(Translation)
import Translation
@available(iOS 18.0, *)
private struct TranslationLanguagePreparationView: View {
  let languages: [String]
  let target: String
  let completion: ([String]?, String?) -> Void
  @State private var index = 0
  @State private var installed: [String] = []
  @State private var failures: [String] = []

  var body: some View {
    VStack(spacing: 24) {
      Text("下载翻译语言包").font(.headline)
      ProgressView(value: Double(index), total: Double(max(1, languages.count)))
      Text("\(min(index + 1, languages.count)) / \(languages.count)")
      Text("语言包供所有源共用。请按 iOS 提示确认下载，保持此页面打开。")
        .font(.footnote)
      if index < languages.count {
        let source = languages[index]
        TranslationLanguagePreparationStep(source: source, target: target) { error in
          if let error = error { failures.append(error) }
          else { installed.append(source) }
          if index + 1 < languages.count { index += 1 }
          else {
            completion(installed, failures.isEmpty ? nil : "部分语言包未就绪：" + failures.joined(separator: "；"))
          }
        }.id(index)
      }
      Button("取消下载") { completion(nil, "语言包下载已取消，已安装的语言包会保留") }
    }.padding(24)
  }
}

@available(iOS 18.0, *)
private struct TranslationLanguagePreparationStep: View {
  let source: String
  let target: String
  let completion: (String?) -> Void
  @State private var started = false

  var body: some View {
    Text(Locale(identifier: "zh-Hans").localizedString(forIdentifier: source) ?? source)
      .translationTask(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)) { session in
        guard !started else { return }; started = true
        do {
          let availability = LanguageAvailability()
          let from = Locale.Language(identifier: source)
          let to = Locale.Language(identifier: target)
          let status = await availability.status(from: from, to: to)
          if case .unsupported = status {
            await MainActor.run { completion("\(source)：系统不支持此语言组合") }
            return
          }
          if case .supported = status { try await session.prepareTranslation() }
          try Task.checkCancellation()
          let ready = await availability.status(from: from, to: to)
          await MainActor.run {
            completion(ready == .installed ? nil : "\(source)：下载尚未完成，请稍后刷新")
          }
        } catch {
          if !Task.isCancelled {
            await MainActor.run { completion("\(source)：\(error.localizedDescription)") }
          }
        }
      }
  }
}
#endif

/// Reader-owned jobs; originals never leave the device on this channel.
final class ComicImageToolsController: NSObject, UIAdaptivePresentationControllerDelegate {
  // 并发队列：Dart 侧的并发闸门（1–4）决定同时发多少张；原生不再串行排队。
  private let queue = DispatchQueue(
    label: "lumebox.comicImages",
    qos: .userInitiated,
    attributes: .concurrent
  )
  private let lock = NSLock()
  // 模型加载、编译和磁盘替换串行化；不锁推理。
  private let modelLock = NSLock()
  private var cancelled = Set<String>()
  private var active = Set<String>()
  private var models: [String: MLModel] = [:]
  private var modelOrder: [String] = []
  private var translationID: String?
  private var translationResult: FlutterResult?
  private var translationHost: UIViewController?

  func register(with registrar: FlutterPluginRegistrar) {
    FlutterMethodChannel(name: "lumebox/comicImages", binaryMessenger: registrar.messenger())
      .setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let id = args["id"] as? String ?? UUID().uuidString
    if call.method == "cancel" {
      if let target = args["id"] as? String {
        lock.lock(); if active.contains(target) { cancelled.insert(target) }; lock.unlock()
        if translationID == target { finishTranslation(nil, error: "翻译已取消") }
      }
      result(nil); return
    }
    if call.method == "getKey" || call.method == "setKey" {
      let requestedSlot = args["slot"] as? String ?? "apiKey"
      let keySlot = ["imageServer", "colorize", "colorizeSeedream"].contains(requestedSlot) ? requestedSlot : "apiKey"
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "lumebox.comicTranslation", kSecAttrAccount as String: keySlot]
      if call.method == "getKey" {
        var read = query; read[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &value)
        guard status == errSecSuccess || status == errSecItemNotFound else { result(FlutterError(code: "keychain", message: "无法读取钥匙串", details: nil)); return }
        result((value as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? "")
      } else {
        let key = args["key"] as? String ?? ""
        if key.isEmpty {
          let status = SecItemDelete(query as CFDictionary)
          guard status == errSecSuccess || status == errSecItemNotFound else { result(FlutterError(code: "keychain", message: "无法删除密钥", details: nil)); return }
        } else {
          let data = Data(key.utf8)
          let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
          if status == errSecItemNotFound {
            var write = query; write[kSecValueData as String] = data
            write[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(write as CFDictionary, nil) == errSecSuccess else { result(FlutterError(code: "keychain", message: "无法保存密钥", details: nil)); return }
          } else if status != errSecSuccess { result(FlutterError(code: "keychain", message: "无法更新密钥", details: nil)); return }
        }
        result(nil)
      }
      return
    }
    if call.method == "translationLanguages" { translationLanguages(result: result); return }
    if call.method == "prepareTranslationLanguages" {
      var preparation = args
      preparation["texts"] = args["languages"]
      preparation["prepareOnly"] = true
      startTranslation(preparation, id: id, result: result); return
    }
    if call.method == "translate" { startTranslation(args, id: id, result: result); return }
    guard ["recognize", "superResolve", "prepareModel", "clearModels", "importModel"].contains(call.method) else { result(FlutterMethodNotImplemented); return }
    lock.lock(); active.insert(id); lock.unlock()
    queue.async {
      do {
        try self.check(id)
        let value: Any? = try autoreleasepool {
          switch call.method {
          case "importModel":
            guard let name = args["name"] as? String,
                  (0...3).flatMap({ ["noise\($0).mlmodel", "photo\($0).mlmodel"] }).contains(name),
                  let bytes = args["bytes"] as? FlutterStandardTypedData,
                  bytes.data.count <= 3 * 1024 * 1024 else { throw self.failure("模型文件无效") }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mlmodel")
            defer { try? FileManager.default.removeItem(at: staging) }
            try bytes.data.write(to: staging, options: .atomic)
            let compiled = try MLModel.compileModel(at: staging)
            defer { try? FileManager.default.removeItem(at: compiled) }
            let configuration = MLModelConfiguration()
            _ = try MLModel(contentsOf: compiled, configuration: configuration)
            self.modelLock.lock()
            defer { self.modelLock.unlock() }
            let directory = try self.modelDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(String(name.dropLast(8)) + ".mlmodelc")
            try bytes.data.write(to: directory.appendingPathComponent(name), options: .atomic)
            self.models.removeAll(); self.modelOrder.removeAll()
            if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: compiled) }
            else { try FileManager.default.copyItem(at: compiled, to: target) }
            try self.modelFingerprint(bytes.data).write(to: directory.appendingPathComponent(String(name.dropLast(8)) + ".sha256"), atomically: true, encoding: .utf8)
            return nil
          case "prepareModel": _ = try self.model(args["noise"] as? Int ?? 0, style: args["imageStyle"] as? String ?? "anime"); return nil
          case "clearModels":
            self.modelLock.lock()
            defer { self.modelLock.unlock() }
            self.models.removeAll(); self.modelOrder.removeAll()
            let directory = try self.modelDirectory()
            if FileManager.default.fileExists(atPath: directory.path) {
              for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where ["mlmodelc", "sha256"].contains(file.pathExtension) {
                try FileManager.default.removeItem(at: file)
              }
            }
            return nil
          default:
            guard let bytes = args["bytes"] as? FlutterStandardTypedData, bytes.data.count <= 32 * 1024 * 1024,
                  let source = CGImageSourceCreateWithData(bytes.data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 20000, height <= 100000 else { throw self.failure("图片过大或格式不支持，原图保留") }
            if call.method == "recognize" {
              return try self.recognizeSource(source, width: width, height: height,
                sourceLanguage: args["source"] as? String ?? "auto", id: id)
            }
            if call.method == "superResolve", let threshold = args["threshold"] as? Int, width >= threshold {
              return ["bytes": bytes, "status": "skipped", "width": width, "height": height,
                "reason": "原图宽度已达到 \(threshold)px 阈值"] as [String: Any]
            }
            guard width * height <= 4_000_000 else { throw self.failure("当前页超过超分内存限制，原图保留") }
            guard let decoded = UIImage(data: bytes.data) else { throw self.failure("图片解码失败") }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let normalized = UIGraphicsImageRenderer(size: CGSize(width: CGFloat(width), height: CGFloat(height)), format: format).image { context in
              UIColor.white.setFill(); context.cgContext.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
              decoded.draw(in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            }
            guard let image = normalized.cgImage else { throw self.failure("图片解码失败") }
            let enlarged = try self.enlarge(image, noise: args["noise"] as? Int ?? 0, style: args["imageStyle"] as? String ?? "anime", id: id)
            return ["bytes": FlutterStandardTypedData(bytes: enlarged), "status": "processed",
              "width": width, "height": height, "outputWidth": width * 2, "outputHeight": height * 2] as [String: Any]
          }
        }
        self.end(id)
        DispatchQueue.main.async { result(value) }
      } catch {
        self.end(id)
        DispatchQueue.main.async { result(FlutterError(code: "image_processing", message: error.localizedDescription, details: nil)) }
      }
    }
  }

  private func failure(_ message: String) -> NSError { NSError(domain: "LumeComicImageTools", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
  private func check(_ id: String) throws { lock.lock(); let stop = cancelled.contains(id); lock.unlock(); if stop { throw failure("处理已取消") } }
  private func end(_ id: String) { lock.lock(); cancelled.remove(id); active.remove(id); lock.unlock() }
  private func modelDirectory() throws -> URL { try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("comic-super-resolution", isDirectory: true) }
  private func modelFingerprint(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func model(_ noise: Int, style: String = "anime") throws -> MLModel {
    // 并发推理时可能同时请求同一个/不同模型：加载与字典访问串行化。
    modelLock.lock()
    defer { modelLock.unlock() }
    guard ["anime", "photo"].contains(style) else { throw failure("模型类型无效") }
    let modelKey = "\(style == "photo" ? "photo" : "noise")\(noise)"
    guard (0...3).contains(noise) else { throw failure("降噪级别无效") }
    if let loaded = models[modelKey] {
      modelOrder.removeAll { $0 == modelKey }; modelOrder.append(modelKey)
      return loaded
    }
    let directory = try modelDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let compiled = directory.appendingPathComponent("\(modelKey).mlmodelc")
    let custom = directory.appendingPathComponent("\(modelKey).mlmodel")
    let assetKey = FlutterDartProject.lookupKey(forAsset: "assets/models/waifu2x/\(modelKey).mlmodel")
    let source: URL
    if FileManager.default.fileExists(atPath: custom.path) {
      source = custom
    } else if let bundledPath = Bundle.main.path(forResource: assetKey, ofType: nil) {
      source = URL(fileURLWithPath: bundledPath)
    } else {
      throw failure("App 内置模型文件缺失，请重新安装完整安装包")
    }
    let fingerprint = modelFingerprint(try Data(contentsOf: source))
    let stamp = directory.appendingPathComponent("\(modelKey).sha256")
    func compile() throws {
      let temporary = try MLModel.compileModel(at: source)
      defer { try? FileManager.default.removeItem(at: temporary) }
      if FileManager.default.fileExists(atPath: compiled.path) {
        try FileManager.default.removeItem(at: compiled)
      }
      try FileManager.default.copyItem(at: temporary, to: compiled)
      try fingerprint.write(to: stamp, atomically: true, encoding: .utf8)
    }
    if !FileManager.default.fileExists(atPath: compiled.path) ||
        (try? String(contentsOf: stamp, encoding: .utf8)) != fingerprint {
      try compile()
    }
    let config = MLModelConfiguration(); config.computeUnits = .all
    let loaded: MLModel
    do { loaded = try MLModel(contentsOf: compiled, configuration: config) }
    catch {
      // 系统升级或缓存损坏时自动重新准备一次，不要求用户重新安装模型。
      try compile()
      loaded = try MLModel(contentsOf: compiled, configuration: config)
    }
    // 漫画正文和照片海报常交替使用；最多留两个，避免反复加载且不常驻全部八个。
    models[modelKey] = loaded
    modelOrder.append(modelKey)
    while modelOrder.count > 2 { models.removeValue(forKey: modelOrder.removeFirst()) }
    return loaded
  }

  /// Decode a bounded, orientation-correct working image. Vision only receives
  /// overlapping tiles; coordinates are mapped back to the complete page.
  /// Ownership by each tile's core prevents overlap text from being read twice.
  private func recognizeSource(_ source: CGImageSource, width: Int, height: Int,
    sourceLanguage: String, id: String) throws -> [[String: Any]] {
    try check(id)
    let scale = min(1.0, min(sqrt(16_000_000.0 / (Double(width) * Double(height))),
      65536.0 / Double(max(width, height))))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(max(width, height)) * scale)),
      kCGImageSourceShouldCacheImmediately: false,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      else { throw failure("文字识别图片解码失败") }
    let fullWidth = CGFloat(image.width), fullHeight = CGFloat(image.height)
    let coreSize = 1792, overlap = 128
    var output = [[String: Any]]()
    for top in stride(from: 0, to: image.height, by: coreSize) {
      for left in stride(from: 0, to: image.width, by: coreSize) {
        try check(id)
        let core = CGRect(x: CGFloat(left), y: CGFloat(top),
          width: CGFloat(min(coreSize, image.width - left)),
          height: CGFloat(min(coreSize, image.height - top)))
        let crop = core.insetBy(dx: -CGFloat(overlap), dy: -CGFloat(overlap))
          .intersection(CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight)).integral
        let found: [[String: Any]] = try autoreleasepool {
          guard let tile = image.cropping(to: crop) else { throw self.failure("文字识别分块失败") }
          return try self.recognize(tile, source: sourceLanguage, id: id)
        }
        for var region in found {
          guard let x = region["x"] as? CGFloat, let y = region["y"] as? CGFloat,
            let w = region["width"] as? CGFloat, let h = region["height"] as? CGFloat else { continue }
          let box = CGRect(x: crop.minX + x * crop.width, y: crop.minY + y * crop.height,
            width: w * crop.width, height: h * crop.height)
          guard box.midX >= core.minX, box.midX < core.maxX,
            box.midY >= core.minY, box.midY < core.maxY else { continue }
          region["x"] = box.minX / fullWidth; region["y"] = box.minY / fullHeight
          region["width"] = box.width / fullWidth; region["height"] = box.height / fullHeight
          output.append(region)
          guard output.count <= 2000 else { throw failure("当前长图文字超过 2000 个区域，请分段处理") }
        }
      }
    }
    try check(id)
    return output
  }

  private func recognize(_ image: CGImage, source: String, id: String) throws -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
    if #available(iOS 16.0, *) { request.automaticallyDetectsLanguage = true }
    let supported: [String]
    if #available(iOS 15.0, *) { supported = try request.supportedRecognitionLanguages() }
    else { supported = try VNRecognizeTextRequest.supportedRecognitionLanguages(for: .accurate, revision: request.revision) }
    let preferred = source == "auto" ? ["ja-JP", "en-US", "zh-Hans", "zh-Hant", "ko-KR", "es", "fr", "de", "it", "pt"] : [source]
    let matching = preferred.compactMap { candidate in supported.first { $0 == candidate || $0.hasPrefix(candidate + "-") } }
    if !matching.isEmpty { request.recognitionLanguages = matching }
    try VNImageRequestHandler(cgImage: image).perform([request])
    try check(id)
    let found = request.results ?? []
    guard found.count <= 250 else { throw failure("当前页文字过多，请分段处理") }
    return found.compactMap { observation in
      guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
      let box = observation.boundingBox
      return ["text": text, "x": box.minX, "y": 1 - box.maxY, "width": box.width, "height": box.height]
    }
  }

  private func enlarge(_ image: CGImage, noise: Int, style: String, id: String) throws -> Data {
    let model = try self.model(noise, style: style)
    guard let inputName = model.modelDescription.inputDescriptionsByName.keys.first,
          let inputShape = model.modelDescription.inputDescriptionsByName[inputName]?.multiArrayConstraint?.shape,
          inputShape.map({ $0.intValue }) == [3, 156, 156],
          let outputName = model.modelDescription.outputDescriptionsByName.keys.first else { throw failure("超分模型结构不兼容") }
    let width = image.width, height = image.height, outWidth = width * 2, outHeight = height * 2
    var source = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    let drawn = source.withUnsafeMutableBytes { ptr -> Bool in
      guard let context = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))); return true
    }
    guard drawn else { throw failure("无法分配图片内存") }
    var output = [UInt8](repeating: 255, count: outWidth * outHeight * 4)
    func reflect(_ position: Int, limit: Int) -> Int {
      if limit <= 1 { return 0 }
      let period = 2 * (limit - 1)
      let positive = ((position % period) + period) % period
      return positive < limit ? positive : period - positive
    }
    for top in stride(from: 0, to: height, by: 142) {
      for left in stride(from: 0, to: width, by: 142) {
        try check(id)
        try autoreleasepool {
          let input = try MLMultiArray(shape: inputShape, dataType: .float32)
          let values = input.dataPointer.assumingMemoryBound(to: Float.self)
          let strides = input.strides.map { $0.intValue }
          for y in 0..<156 {
            for x in 0..<156 {
              let pixel = (reflect(top + y - 7, limit: height) * width + reflect(left + x - 7, limit: width)) * 4
              for channel in 0..<3 { values[channel * strides[0] + y * strides[1] + x * strides[2]] = Float(source[pixel + channel]) / 255 }
            }
          }
          let features = try MLDictionaryFeatureProvider(dictionary: [inputName: MLFeatureValue(multiArray: input)])
          let prediction = try model.prediction(from: features)
          guard let pixels = prediction.featureValue(for: outputName)?.multiArrayValue,
                pixels.shape.map({ $0.intValue }) == [3, 284, 284] else { throw failure("超分模型输出不兼容") }
          let steps = pixels.strides.map { $0.intValue }
          let doubleValues = pixels.dataType == .double ? pixels.dataPointer.assumingMemoryBound(to: Double.self) : nil
          let floatValues = pixels.dataType == .float32 ? pixels.dataPointer.assumingMemoryBound(to: Float.self) : nil
          for y in 0..<min(284, (height - top) * 2) {
            for x in 0..<min(284, (width - left) * 2) {
              let destination = ((top * 2 + y) * outWidth + left * 2 + x) * 4
              for channel in 0..<3 {
                let offset = channel * steps[0] + y * steps[1] + x * steps[2]
                let value: Double
                if let doubleValues = doubleValues { value = doubleValues[offset] }
                else if let floatValues = floatValues { value = Double(floatValues[offset]) }
                else { value = pixels[offset].doubleValue }
                output[destination + channel] = value.isFinite ? UInt8(max(0, min(255, (value * 255).rounded()))) : 0
              }
            }
          }
        }
      }
    }
    try check(id)
    let provider = CGDataProvider(data: Data(output) as CFData)
    guard let provider = provider,
          let result = CGImage(width: outWidth, height: outHeight, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: outWidth * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let data = UIImage(cgImage: result).pngData() else { throw failure("无法生成超分图片") }
    return data
  }

  private func translationLanguages(result: @escaping FlutterResult) {
    #if canImport(Translation)
    if #available(iOS 18.0, *) {
      Task {
        let availability = LanguageAvailability()
        let target = Locale.Language(identifier: "zh-Hans")
        let languages = await availability.supportedLanguages
        var rows: [[String: String]] = []
        for language in languages {
          let code = language.minimalIdentifier
          if code.lowercased().split(separator: "-").first == "zh" { continue }
          let status = await availability.status(from: language, to: target)
          let state: String
          switch status {
          case .installed: state = "installed"
          case .supported: state = "supported"
          case .unsupported: continue
          @unknown default: continue
          }
          rows.append(["code": code,
            "name": Locale(identifier: "zh-Hans").localizedString(forIdentifier: code) ?? code,
            "status": state])
        }
        let sorted = rows.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }
        await MainActor.run { result(sorted) }
      }
      return
    }
    #endif
    result(FlutterError(code: "unsupported", message: "系统翻译语言包需要 iOS 18 或以上", details: nil))
  }

  private func startTranslation(_ args: [String: Any], id: String, result: @escaping FlutterResult) {
    #if canImport(Translation)
    if #available(iOS 18.0, *) {
      guard translationResult == nil else { result(FlutterError(code: "busy", message: "已有翻译任务正在进行", details: nil)); return }
      guard let texts = args["texts"] as? [String], !texts.isEmpty, texts.count <= 250,
            texts.reduce(0, { $0 + $1.count }) <= 50000,
            let target = args["target"] as? String else { result(FlutterError(code: "arguments", message: "翻译参数无效", details: nil)); return }
      guard var root = (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first { $0.isKeyWindow })?.rootViewController else { result(FlutterError(code: "window", message: "无法打开翻译", details: nil)); return }
      while let presented = root.presentedViewController { root = presented }
      translationID = id; translationResult = result
      lock.lock(); active.insert(id); lock.unlock()
      let source = args["source"] as? String ?? "auto"
      let preparing = args["prepareOnly"] as? Bool == true
      let targetFamily = target.lowercased().split(separator: "-").first
      let alreadyTarget = source == "auto" && texts.allSatisfy { text in
        if !text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) { return true }
        guard let detected = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue else { return false }
        return detected.lowercased().split(separator: "-").first == targetFamily &&
          !(targetFamily == "zh" && hasForeignChineseTargetText(text))
      }
      if !preparing && (source == target || alreadyTarget) {
        finishTranslation(texts, error: nil)
        return
      }
      let completion: ([String]?, String?) -> Void = { [weak self] strings, error in
        guard self?.translationID == id else { return }
        self?.finishTranslation(strings, error: error)
      }
      let view = preparing
        ? AnyView(TranslationLanguagePreparationView(languages: texts, target: target, completion: completion))
        : AnyView(ComicTranslationTaskView(texts: texts, source: source, target: target, completion: completion))
      let host = UIHostingController(rootView: view)
      translationHost = host
      if preparing {
        root.present(host, animated: true) { [weak self, weak host] in host?.presentationController?.delegate = self }
      } else {
        // Keep SwiftUI's translation task attached without a blocking sheet.
        root.addChild(host)
        host.view.backgroundColor = .clear
        host.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        host.view.clipsToBounds = true
        host.view.isUserInteractionEnabled = false
        host.view.accessibilityElementsHidden = true
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
      }
      return
    }
    #endif
    result(FlutterError(code: "unsupported", message: "设备端翻译需要 iOS 18 或以上；也可配置 AI 翻译", details: nil))
  }

  private func finishTranslation(_ strings: [String]?, error: String?) {
    guard let result = translationResult else { return }
    translationResult = nil
    if let id = translationID { end(id) }; translationID = nil
    let host = translationHost; translationHost = nil
    // Complete only after dismissal; the next queued batch must not present
    // its controller on top of a sheet still being dismissed.
    let complete = {
      if let strings = strings, let error = error {
        result(FlutterError(code: "translation_partial", message: error, details: strings))
      }
      else if let strings = strings { result(strings) }
      else { result(FlutterError(code: error == "翻译已取消" ? "translation_cancelled" : "translation", message: error ?? "翻译失败", details: nil)) }
    }
    if let host = host, host.presentingViewController != nil {
      host.dismiss(animated: true, completion: complete)
    } else {
      host?.willMove(toParent: nil)
      host?.view.removeFromSuperview()
      host?.removeFromParent()
      complete()
    }
  }
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finishTranslation(nil, error: "翻译已取消") }
}

#if canImport(Translation)
// Short and mixed titles can be guessed as Chinese despite foreign script.
private func hasForeignChineseTargetText(_ text: String) -> Bool {
  text.range(of: "[A-Za-z]{3,}|[\\u3040-\\u30ff\\uac00-\\ud7af\\u0400-\\u052f\\u0600-\\u06ff\\u0900-\\u097f\\u0e00-\\u0e7f]", options: .regularExpression) != nil
}

@available(iOS 18.0, *)
private struct ComicTranslationTaskView: View {
  struct Group {
    let language: String
    var indices: [Int]
  }
  let texts: [String]
  let source: String
  let target: String
  let completion: ([String]?, String?) -> Void
  @State private var groups: [Group] = []
  @State private var groupIndex = 0
  @State private var output: [String] = []
  @State private var prepared = false
  @State private var failures: [String] = []

  private func family(_ language: String) -> String {
    language.lowercased().split(separator: "-").first.map(String.init) ?? language
  }
  private func prepare() {
    guard !prepared else { return }
    output = texts
    var plan: [Group] = []
    // Short titles are ambiguous in isolation. Only use the page's language
    // when it is also a plausible candidate for this individual title.
    let context = NLLanguageRecognizer()
    context.processString(String(texts.joined(separator: "\n").prefix(12000)))
    let contextLanguage = context.dominantLanguage
    let contextConfidence = contextLanguage.flatMap { context.languageHypotheses(withMaximum: 1)[$0] } ?? 0
    for (index, text) in texts.enumerated() {
      guard text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { continue }
      let recognizer = NLLanguageRecognizer()
      recognizer.processString(text)
      let hypotheses = recognizer.languageHypotheses(withMaximum: 10)
      var detected = source == "auto" ? recognizer.dominantLanguage?.rawValue : source
      let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
      let latin = !letters.isEmpty && letters.allSatisfy { $0.value <= 0x024F || (0x1E00...0x1EFF).contains($0.value) }
      let latinLanguages: Set<String> = ["en", "es", "fr", "de", "it", "pt", "nl", "nb", "no", "ca", "ro", "da", "sv", "pl", "cs", "fi", "tr"]
      // All-caps speech bubbles are often individually guessed as Norwegian,
      // Catalan or Romanian. Prefer a confident page-level Latin language.
      if source == "auto", latin, text.count <= 160, let candidate = contextLanguage,
         latinLanguages.contains(candidate.rawValue), contextConfidence >= 0.65 {
        detected = candidate.rawValue
      }
      if source == "auto", text.count <= 80, let candidate = contextLanguage,
         (context.languageHypotheses(withMaximum: 1)[candidate] ?? 0) >= 0.8,
         (hypotheses[recognizer.dominantLanguage ?? .undetermined] ?? 0) < 0.8,
         (hypotheses[candidate] ?? 0) >= 0.05 {
        detected = candidate.rawValue
      }
      // Apple cannot translate a language to itself, including regional variants.
      // Chinese content already meets the Chinese-display request.
      if source == "auto", family(target) == "zh",
         detected.map({ family($0) == "zh" }) == true,
         hasForeignChineseTargetText(text) {
        if text.range(of: "[\\u3040-\\u30ff]", options: .regularExpression) != nil { detected = "ja" }
        else if text.range(of: "[\\uac00-\\ud7af]", options: .regularExpression) != nil { detected = "ko" }
        else {
          // Re-detect the foreign portion without the Chinese page labels.
          let foreign = text.replacingOccurrences(of: "[\\u3400-\\u9fff]", with: " ", options: .regularExpression)
          detected = NLLanguageRecognizer.dominantLanguage(for: foreign)?.rawValue ?? "en"
          if detected.map({ family($0) == "zh" }) == true { detected = "en" }
        }
      }
      if let detected, family(detected) == family(target) { continue }
      let language = detected ?? "en"
      if let found = plan.firstIndex(where: { $0.language == language }) {
        plan[found].indices.append(index)
      } else {
        plan.append(Group(language: language, indices: [index]))
      }
    }
    groups = plan
    prepared = true
    if plan.isEmpty { completion(output, nil) }
  }
  var body: some View {
    VStack(spacing: 24) {
      Text("设备端翻译").font(.headline)
      ProgressView("正在翻译…")
      if prepared && groupIndex < groups.count {
        let group = groups[groupIndex]
        ComicTranslationBatchView(texts: group.indices.map { texts[$0] },
          source: group.language, target: target) { values, error in
          guard let values, values.count == group.indices.count else {
            // Empty slots identify failures; Dart caches only successful slots.
            // Continue other languages instead of discarding the whole page.
            for index in group.indices { output[index] = "" }
            failures.append(error ?? "翻译结果不完整，请重试")
            advance()
            return
          }
          for (offset, index) in group.indices.enumerated() { output[index] = values[offset] }
          if let error { failures.append(error) }
          advance()
        }.id(groupIndex)
      }
      Button("取消") { completion(nil, "翻译已取消") }
    }.padding(24).task { prepare() }
  }
  private func advance() {
    if groupIndex + 1 < groups.count { groupIndex += 1 }
    else {
      completion(output, failures.isEmpty ? nil : "部分内容未翻译，成功译文已保留。" + failures.joined(separator: "；"))
    }
  }
}

@available(iOS 18.0, *)
private struct ComicTranslationBatchView: View {
  let texts: [String]
  let source: String
  let target: String
  let completion: ([String]?, String?) -> Void
  @State private var started = false
  var body: some View {
    Text("\(source) → \(target)").font(.caption)
      .translationTask(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target)) { session in
        guard !started else { return }; started = true
        do {
          let status = await LanguageAvailability().status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
          if case .unsupported = status {
            await MainActor.run { completion(nil, "系统不支持 \(source) → \(target) 翻译，可更换原文语言或使用 AI 翻译") }
            return
          }
          if case .supported = status {
            await MainActor.run { completion(nil, "请先在翻译设置下载 \(source) → \(target) 语言包，或选择 AI 翻译") }
            return
          }
          var translated = [String](repeating: "", count: texts.count)
          var failed = 0
          for (index, text) in texts.enumerated() {
            try Task.checkCancellation()
            do {
              let response = try await session.translate(text)
              translated[index] = response.targetText
            } catch {
              try Task.checkCancellation()
              // One rejected title must not erase this language's completed work.
              failed += 1
            }
          }
          let message = failed == 0 ? nil : "\(source) → \(target) 有 \(failed) 条翻译失败，成功译文已保留"
          await MainActor.run { completion(translated, message) }
        } catch {
          await MainActor.run { completion(nil, "\(source) → \(target) 翻译失败：\(error.localizedDescription)") }
        }
      }
  }
}
#endif
