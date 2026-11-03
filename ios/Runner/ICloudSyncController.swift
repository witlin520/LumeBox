import Flutter
import UIKit
import CryptoKit

/// iCloud Drive documents only; no private credentials or media are passed here.
final class ICloudSyncController {
  private let queue = DispatchQueue(label: "lumebox.icloud", qos: .utility)
  func register(with messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "lumebox/icloud", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterError(code: "unavailable", message: "iCloud 不可用", details: nil)); return }
      self.queue.async {
        do {
          guard let token = FileManager.default.ubiquityIdentityToken else { throw NSError(domain: "iCloud", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先在系统设置登录 iCloud 并开启 iCloud Drive"]) }
          guard let root = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.lumebox.app") else { throw NSError(domain: "iCloud", code: 2, userInfo: [NSLocalizedDescriptionKey: "当前签名未启用 LumeBox iCloud 容器，或 iCloud Drive 不可用"]) }
          let tokenData = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
          let account = SHA256.hash(data: tokenData).map { String(format: "%02x", $0) }.joined()
          let directory = root.appendingPathComponent("Documents/Sync-v1", isDirectory: true)
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          var response: Any? = nil
          switch call.method {
          case "status": response = ["available": true, "account": account]
          case "read":
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])
              .filter { $0.lastPathComponent.hasPrefix("device-") && $0.pathExtension == "json" }
            guard files.count <= 100 else { throw NSError(domain: "iCloud", code: 3, userInfo: [NSLocalizedDescriptionKey: "云端设备快照过多，请检查 iCloud Drive"]) }
            var documents = [String](); var total = 0
            for file in files {
              let values = try file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
              if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                try FileManager.default.startDownloadingUbiquitousItem(at: file)
                throw NSError(domain: "iCloud", code: 4, userInfo: [NSLocalizedDescriptionKey: "iCloud 正在下载同步数据，请稍后重试"])
              }
              let urls = [file] + (NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []).map { $0.url }
              for url in urls {
                var coordinationError: NSError?; var readError: Error?; var text: String?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { location in
                  do {
                    let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= 10 * 1024 * 1024 else { throw NSError(domain: "iCloud", code: 5, userInfo: [NSLocalizedDescriptionKey: "云端快照过大"] ) }
                    text = try String(contentsOf: location, encoding: .utf8)
                  } catch { readError = error }
                }
                if let error = coordinationError { throw error }; if let error = readError { throw error }
                if let text = text { total += text.utf8.count; guard total <= 50 * 1024 * 1024 else { throw NSError(domain: "iCloud", code: 5) }; documents.append(text) }
              }
            }
            response = ["account": account, "documents": documents]
          case "write":
            guard let args = call.arguments as? [String: Any], let device = args["device"] as? String,
              device.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil,
              let text = args["text"] as? String, text.utf8.count <= 10 * 1024 * 1024,
              args["account"] as? String == account else { throw NSError(domain: "iCloud", code: 6, userInfo: [NSLocalizedDescriptionKey: "账号已变化或同步参数无效"]) }
            let file = directory.appendingPathComponent("device-\(device).json")
            var coordinationError: NSError?; var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &coordinationError) { location in
              do {
                if (try? String(contentsOf: location, encoding: .utf8)) != text {
                  try text.write(to: location, atomically: true, encoding: .utf8)
                }
              } catch { writeError = error }
            }
            if let error = coordinationError { throw error }; if let error = writeError { throw error }
            response = true
          default:
            DispatchQueue.main.async { result(FlutterMethodNotImplemented) }; return
          }
          DispatchQueue.main.async { result(response) }
        } catch { DispatchQueue.main.async { result(FlutterError(code: "icloud", message: error.localizedDescription, details: nil)) } }
      }
    }
  }
}
