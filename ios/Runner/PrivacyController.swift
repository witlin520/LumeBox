import Flutter
import UIKit
import LocalAuthentication
import Security

final class PrivacyController {
  private var context: LAContext?
  private var covers: [UIView] = []
  private var observers: [NSObjectProtocol] = []
  private var enabled = UserDefaults.standard.bool(forKey: "lumebox.appLock")
  private let queue = DispatchQueue(label: "lumebox.privacy.authentication")

  func register(with messenger: FlutterBinaryMessenger) {
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.cover() })
    observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.uncover() })
    FlutterMethodChannel(name: "lumebox/privacy", binaryMessenger: messenger).setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(false); return }
      let args = call.arguments as? [String: Any] ?? [:]
      if call.method == "setEnabled" {
        self.enabled = args["enabled"] as? Bool ?? false
        UserDefaults.standard.set(self.enabled, forKey: "lumebox.appLock")
        if !self.enabled { self.uncover() }
        result(nil); return
      }
      guard call.method == "authenticate" else { result(FlutterMethodNotImplemented); return }
      guard self.context == nil else { result(FlutterError(code: "busy", message: "验证正在进行", details: nil)); return }
      let context = LAContext()
      context.localizedCancelTitle = "取消"
      context.touchIDAuthenticationAllowableReuseDuration = 0
      self.context = context
      if args["method"] as? String == "face" {
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID else {
          self.context = nil
          result(FlutterError(code: "face_unavailable", message: "面容识别不可用，请检查 Face ID 设置与权限，或使用锁屏密码", details: nil)); return
        }
        context.localizedFallbackTitle = ""
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "解锁 LumeBox 或修改应用锁设置") { success, _ in
          DispatchQueue.main.async { self.context = nil; result(success) }
        }
      } else {
        // A devicePasscode ACL requires the real system passcode, rather than
        // deviceOwnerAuthentication's automatic biometric-first behavior.
        self.queue.async {
          var error: NSError?
          guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            DispatchQueue.main.async { self.context = nil; result(FlutterError(code: "passcode_unavailable", message: "请先在系统设置中设置本机锁屏密码", details: nil)) }; return
          }
          let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "lumebox.privacy", kSecAttrAccount as String: "device-passcode-challenge"]
          var read = query
          read[kSecReturnData as String] = true
          read[kSecUseAuthenticationContext as String] = context
          read[kSecUseOperationPrompt as String] = "使用本机锁屏密码解锁 LumeBox"
          var item: CFTypeRef?
          var status = SecItemCopyMatching(read as CFDictionary, &item)
          if status == errSecItemNotFound {
            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .devicePasscode, nil) else {
              DispatchQueue.main.async { self.context = nil; result(false) }; return
            }
            var create = query
            create[kSecAttrAccessControl as String] = access
            create[kSecValueData as String] = Data(UUID().uuidString.utf8)
            let added = SecItemAdd(create as CFDictionary, nil)
            if added == errSecSuccess || added == errSecDuplicateItem { status = SecItemCopyMatching(read as CFDictionary, &item) }
            else { status = added }
          }
          DispatchQueue.main.async {
            self.context = nil
            if status == errSecSuccess { result(true) }
            else if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed { result(false) }
            else { result(FlutterError(code: "passcode_failed", message: "锁屏密码验证未完成，请检查设备锁屏设置", details: nil)) }
          }
        }
      }
    }
  }

  private func cover() {
    guard enabled, covers.isEmpty else { return }
    for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }).filter({ !$0.isHidden }) {
      let view = UIView(frame: window.bounds)
      view.backgroundColor = .systemBackground
      view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      let label = UILabel(frame: view.bounds)
      label.text = "LumeBox 已锁定"; label.textAlignment = .center
      label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(label); window.addSubview(view); covers.append(view)
    }
  }
  private func uncover() { covers.forEach { $0.removeFromSuperview() }; covers.removeAll() }
  deinit { context?.invalidate(); observers.forEach { NotificationCenter.default.removeObserver($0) } }
}
