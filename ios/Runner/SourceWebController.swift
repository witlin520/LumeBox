import Flutter
import Foundation
import WebKit
import SwiftSoup
import UIKit
import CoreFoundation

/// Shared by all managed off-screen WebKit readers, including legacy fallbacks.
enum SourceWebBudget {
  private(set) static var active = 0
  static func take() -> Bool { if active >= 3 { return false }; active += 1; return true }
  static func release() { active = max(0,active - 1) }
}

/// On-device source primitives. Uses the same persistent WebKit store as the
/// visible login page. No browser process, downloaded runtime or remote service.
final class SourceWebController {
  private var tasks: [String: SourceWebTask] = [:]
  private var parsingCount = 0
  private var verified: [String:SourceWebTask] = [:]
  private var retained: SourceWebTask?
  private var retainedID: String?
  private var retainedExpiry: DispatchWorkItem?
  private var memoryObserver: NSObjectProtocol?
  private var sessionObservers: [NSObjectProtocol] = []
  private var inspectable = false
  private static var seededCookies: Set<String> = []

  init() {
    for name in [Notification.Name("LumeWebSessionsInvalidated"), UIApplication.didEnterBackgroundNotification] {
      sessionObservers.append(NotificationCenter.default.addObserver(forName:name, object:nil, queue:.main) { [weak self] note in
        if note.name == UIApplication.didEnterBackgroundNotification { self?.retained?.setApplicationActive(false) }
        self?.invalidate(hosts:note.userInfo?["hosts"] as? [String], includePresented:note.name != UIApplication.didEnterBackgroundNotification)
      })
    }
    sessionObservers.append(NotificationCenter.default.addObserver(forName:UIApplication.didBecomeActiveNotification,object:nil,queue:.main) { [weak self] _ in
      self?.retained?.setApplicationActive(true)
    })
    memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil, queue: .main) { [weak self] _ in
        guard let self = self else { return }
        for task in Array(self.tasks.values) { task.cancel() }
        for task in self.verified.values { task.destroy() }; self.verified.removeAll()
        if self.retained?.isPresented != true { self.retained?.destroy(); self.retained = nil }
        Self.clearTransientData(force:true)
      }
  }
  deinit {
    if let observer = memoryObserver { NotificationCenter.default.removeObserver(observer) }
    for observer in sessionObservers { NotificationCenter.default.removeObserver(observer) }
  }
  private func invalidate(hosts: [String]?, includePresented: Bool = true) {
    func matches(_ task: SourceWebTask) -> Bool { hosts == nil || hosts!.contains(task.host ?? "") }
    for (key,task) in Array(verified) where matches(task) { verified.removeValue(forKey:key); task.cancel() }
    for task in Array(tasks.values) where matches(task) { task.cancel() }
    if let task=retained, matches(task), includePresented || !task.isPresented {
      retained=nil; retainedID=nil; retainedExpiry?.cancel(); task.cancel()
    }
  }
  private static var lastCleanup = Date.distantPast
  private static func clearTransientData(force: Bool = false) {
    if !force && (SourceWebBudget.active > 0 || Date().timeIntervalSince(lastCleanup) < 300) { return }
    lastCleanup = Date()
    URLCache.shared.removeAllCachedResponses()
    // Login cookies and local storage are intentionally retained.
    WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache],
      modifiedSince: .distantPast) {}
  }

  private let parsing = DispatchQueue(label: "lumebox.source.html", qos: .userInitiated)

  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lumebox/source_web", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "arguments", message: "网页请求参数无效", details: nil)); return
      }
      let id = args["requestId"] as? String ?? ""
      switch call.method {
      case "session.invalidate":
        self.invalidate(hosts:args["hosts"] as? [String]); result(nil)
      case "configure":
        self.inspectable = args["inspectable"] as? Bool == true
        for task in self.tasks.values { task.setInspectable(self.inspectable) }
        self.retained?.setInspectable(self.inspectable)
        let hosts = args["clearVerificationHosts"] as? [String] ?? []
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
          let group = DispatchGroup()
          for cookie in cookies where ["cf_clearance","__cf_bm"].contains(cookie.name) {
            let domain = cookie.domain.trimmingCharacters(in:CharacterSet(charactersIn:"."))
            if hosts.contains(where: { $0==domain || (cookie.domain.hasPrefix(".") && $0.hasSuffix("."+domain)) }) {
              group.enter(); WKWebsiteDataStore.default().httpCookieStore.delete(cookie) { group.leave() }
            }
          }
          group.notify(queue:.main) { result(nil) }
        }
      case "session":
        self.inspectable = args["inspectable"] as? Bool ?? self.inspectable
        Self.session(args, result: result)
      case "decodeText":
        guard let encoded = args["body"] as? String, encoded.count <= 12 * 1024 * 1024,
          let data = Data(base64Encoded: encoded) else {
          result(FlutterError(code: "encoding", message: "文本编码输入无效", details: nil)); return
        }
        let label = args["charset"] as? String ?? "gb18030"
        guard let text = Self.decodeText(data, charset:label) else {
          result(FlutterError(code: "encoding", message: "无法识别或转换网页编码", details: nil)); return
        }
        result(text)
      case "openExternal":
        guard let text=args["url"] as? String, let url=URL(string:text), ["http","https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil else {
          result(FlutterError(code:"invalid_url",message:"浏览器地址无效",details:nil)); return
        }
        UIApplication.shared.open(url,options:[:]) { result($0) }
      case "bridge.close":
        let scope=args["scope"] as? String ?? ""
        self.verified.removeValue(forKey:scope)?.cancel()
        for task in Array(self.tasks.values) where task.scope == scope { task.cancel() }
        if let task=self.retained, task.scope == scope {
          self.retained=nil; self.retainedID=nil; self.retainedExpiry?.cancel(); task.cancel()
        }
        result(nil)
      case "bridge.configure", "bridge.request":
        guard let task=self.verified[args["scope"] as? String ?? ""] else {
          result(FlutterError(code:"bridge_unverified",message:"请求桥仅在该源验证成功后可用",details:nil)); return
        }
        task.bridge(call.method,arguments:args,completion:result)
      case "verify":
        guard let task = self.retained, self.retainedID == id else { result(nil); return }
        self.retainedExpiry?.cancel()
        task.presentVerification { value in
          self.retained = nil; self.retainedID = nil
          if let reply = value as? [String:Any], reply["verified"] as? Bool == true {
            self.verified.removeValue(forKey:task.scope)?.destroy()
            if self.verified.count >= 2, let key = self.verified.keys.sorted().first { self.verified.removeValue(forKey:key)?.destroy() }
            self.verified[task.scope] = task
          }
          result(value)
          Self.clearTransientData()
        }
      case "cancel":
        self.tasks[id]?.cancel()
        if self.retainedID == id { self.retained?.cancel(); self.retained=nil; self.retainedID=nil }
        result(nil)
      case "extract":
        guard self.parsingCount < 4 else {
          result(FlutterError(code: "html_busy", message: "HTML 解析队列忙，请稍后重试", details: nil)); return
        }
        self.parsingCount += 1
        self.parsing.async {
          do {
            let rows = try SourceWebController.extract(args)
            DispatchQueue.main.async { self.parsingCount -= 1; result(rows) }
          } catch {
            DispatchQueue.main.async {
              self.parsingCount -= 1
              result(FlutterError(code: "html_extract", message: "HTML 或 CSS 提取规则无效", details: nil))
            }
          }
        }
      case "render":
        guard !id.isEmpty, self.tasks.count < 2, self.tasks[id] == nil,
              let text = args["url"] as? String, let url = URL(string: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil,
              (args["steps"] as? [Any] ?? []).count <= 16 else {
          result(FlutterError(code: "browser_busy", message: "网页会话忙或地址无效", details: nil)); return
        }
        guard self.tasks.values.filter({ $0.host == url.host }).count < 2 else {
          result(FlutterError(code: "browser_busy", message: "该站点网页请求过于频繁，请稍后重试", details: nil)); return
        }
        var settings = args
        settings["inspectable"] = self.inspectable
        let task = SourceWebTask(url: url, options: settings) { [weak self] value in
          guard let self = self else { return }
          let finished = self.tasks.removeValue(forKey: id)
          if let error = value as? FlutterError, error.code == "verification", let task = finished {
            self.verified.removeValue(forKey: task.scope)?.destroy()
            self.retained?.destroy()
            self.retained = task; self.retainedID = id
            self.retainedExpiry?.cancel()
            let expiry = DispatchWorkItem { [weak self] in
              guard self?.retainedID == id else { return }
              self?.retained?.destroy(); self?.retained = nil; self?.retainedID = nil
            }
            self.retainedExpiry = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: expiry)
          } else if self.tasks.isEmpty && self.retained == nil { Self.clearTransientData() }
          result(value)
        }
        self.tasks[id] = task
        task.start()
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  static func decodeText(_ data: Data, charset: String) -> String? {
    if data.starts(with:[0xff,0xfe]) { return String(data:data,encoding:.utf16LittleEndian) }
    if data.starts(with:[0xfe,0xff]) { return String(data:data,encoding:.utf16BigEndian) }
    let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    guard cf != kCFStringEncodingInvalidId else { return nil }
    return String(data:data,encoding:String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(cf)))
  }

  private static func session(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let address = args["url"] as? String, let url = URL(string: address),
      ["http","https"].contains(url.scheme ?? ""), let host = url.host else {
      result(FlutterError(code: "arguments", message: "站点地址无效", details: nil)); return
    }
    let store = WKWebsiteDataStore.default().httpCookieStore
    let headers = args["headers"] as? [String:String] ?? [:]
    store.getAllCookies { current in
    let group = DispatchGroup()
    // Explicit script/config cookies are host-only; never broaden their domain.
    for pair in (headers.first { $0.key.lowercased() == "cookie" }?.value ?? "").split(separator: ";").prefix(128) {
      let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count != 2 { continue }
      let name = parts[0].trimmingCharacters(in: .whitespaces)
      let identity = host + "|" + name
      if seededCookies.contains(identity) && args["forceCookies"] as? Bool != true { continue }
      if seededCookies.count >= 1024 { seededCookies.removeAll() }
      seededCookies.insert(identity)
      let existing = current.first { $0.name == name && ($0.domain == host || ($0.domain.hasPrefix(".") && host.hasSuffix($0.domain))) }
      if let existing=existing {
        if args["forceCookies"] as? Bool == true, existing.value != String(parts[1]), var properties=existing.properties {
          properties[.value]=String(parts[1])
          if let cookie=HTTPCookie(properties:properties) { group.enter(); store.setCookie(cookie) { group.leave() } }
        }
        continue
      }
      var properties: [HTTPCookiePropertyKey: Any] = [.name: parts[0].trimmingCharacters(in: .whitespaces),
        .value: String(parts[1]), .domain: host, .path: "/"]
      if url.scheme == "https" { properties[.secure] = "TRUE" }
      if let cookie = HTTPCookie(properties: properties) {
        group.enter(); store.setCookie(cookie) { group.leave() }
      }
    }
    group.notify(queue: .main) {
      store.getAllCookies { cookies in
        let selected = cookies.filter { cookie in
          let bare = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
          return host.lowercased() == bare || (cookie.domain.hasPrefix(".") && host.lowercased().hasSuffix("." + bare))
        }.prefix(256)
        result(["cookies": selected.map { cookie -> [String:Any] in
          ["name":cookie.name, "value":cookie.value, "domain":cookie.domain, "path":cookie.path,
           "secure":cookie.isSecure, "httpOnly":cookie.isHTTPOnly, "expires":cookie.expiresDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull()]
        }])
      }
    }
    }
  }

  static func extract(_ args: [String: Any]) throws -> [[String: Any]] {
    guard let html = args["html"] as? String, html.utf8.count <= 2 * 1024 * 1024,
          let fields = args["fields"] as? [String: [String: Any]],
          !fields.isEmpty, fields.count <= 32 else { throw SourceWebError.invalid }
    let document = try SwiftSoup.parse(html, args["baseUrl"] as? String ?? "")
    let selector = args["rowSelector"] as? String ?? ""
    let roots: [Element]
    if selector.isEmpty { roots = [document] }
    else { roots = try document.select(selector).array() }
    var rows: [[String: Any]] = []
    for root in roots.prefix(500) {
      var row: [String: Any] = [:]
      for (name, field) in fields {
        let css = field["selector"] as? String ?? ""
        let matches = css.isEmpty ? [root] : try root.select(css).array()
        var values: [String] = []
        for element in matches.prefix(500) {
          if let attribute = field["attribute"] as? String {
            values.append(try element.attr(attribute))
          } else if field["html"] as? Bool == true {
            values.append(try element.html())
          } else {
            values.append(try element.text())
          }
          if field["all"] as? Bool != true { break }
        }
        if field["all"] as? Bool == true { row[name] = values }
        else { row[name] = values.first ?? (field["defaultValue"] as? String ?? "") }
      }
      rows.append(row)
    }
    guard try JSONSerialization.data(withJSONObject: rows).count <= 1024 * 1024 else {
      throw SourceWebError.invalid
    }
    return rows
  }
}

private enum SourceWebError: Error { case invalid }

final class SourceWebTask: NSObject, WKNavigationDelegate, WKUIDelegate {
  private let webView: WKWebView
  private let url: URL
  var host: String? { url.host }
  private let options: [String: Any]
  private var callback: ((Any) -> Void)?
  private var timeout: DispatchWorkItem?
  private var status = 200
  private var responseMarkers: [String:String] = [:]
  private var holdsPermit = false
  deinit { if holdsPermit { SourceWebBudget.release() } }
  private var navigating = false
  private var evaluating = false
  private var generation = 0
  private var index = 0
  private var verificationController: UINavigationController?
  private var verificationPoll: DispatchWorkItem?
  private var verificationResult: ((Any) -> Void)?
  private var verificationBaseline: [String: Any] = [:]
  private var verificationCookies = ""
  private var verificationStarted = Date()
  private var verificationEpoch = 0
  private var verificationReading = false
  private var verificationConfirmed = false
  private var verificationFinished = false
  private var verifiedSnapshot: [String: Any] = [:]
  var scope: String { options["scope"] as? String ?? "" }
  private var verifiedAt: Date?
  private var bridgeCancellations: [UUID:()->Void] = [:]
  private var applicationActive = true
  func setApplicationActive(_ active: Bool) {
    applicationActive=active; verificationEpoch+=1; verificationReading=false
    verificationPoll?.cancel()
    if active, verificationResult != nil, !verificationFinished {
      if Date().timeIntervalSince(verificationStarted)>=120 { verificationDecision("验证超时（120 秒），可重试或跳过当前源") }
      else { pollVerification() }
    }
  }
  private var bridgePaths = Set<String>()
  private var bridgeActive = 0
  private static let verificationProbe: String = {
    let key = FlutterDartProject.lookupKey(forAsset: "assets/js/verification_probe.js")
    guard let path = Bundle.main.path(forResource:key,ofType:nil), let text = try? String(contentsOfFile:path,encoding:.utf8) else { return "" }
    return text
  }()
  private var businessSelectors: [String] {
    var selectors = steps.filter { $0["type"] as? String == "wait" }.compactMap { $0["selector"] as? String }
    if let selector = options["waitForSelector"] as? String, !selector.isEmpty { selectors.append(selector) }
    return Array(Set(selectors)).sorted()
  }
  private static func origin(_ url: URL) -> String {
    var parts = URLComponents()
    parts.scheme = url.scheme?.lowercased(); parts.host = url.host?.lowercased()
    let port = url.port
    parts.port = (parts.scheme == "https" && port == 443) || (parts.scheme == "http" && port == 80) ? nil : port
    return parts.string ?? ""
  }
  private func probeProgram() -> String {
    let selectors = String(data:try! JSONSerialization.data(withJSONObject:businessSelectors),encoding:.utf8)!
    let markers=String(data:try! JSONSerialization.data(withJSONObject:responseMarkers),encoding:.utf8)!
    return "(\(Self.verificationProbe))(\(selectors),\(status),\(verificationConfirmed),\(Int(Date().timeIntervalSince(verificationStarted)*1000)),\(markers))"
  }
  private func readVerification(_ done: @escaping ([String:Any]?) -> Void) {
    webView.evaluateJavaScript(probeProgram()) { value, _ in done(value as? [String:Any]) }
  }
  private func scopedCookies(_ done: @escaping ([[String:Any]]) -> Void) {
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
      let host = (self.url.host ?? "").lowercased()
      done(cookies.filter { c in
        let domain = c.domain.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:"."))
        return host == domain || (c.domain.hasPrefix(".") && host.hasSuffix("."+domain))
      }.map { c in ["name":c.name,"value":c.value,"domain":c.domain,"path":c.path,
        "secure":c.isSecure,"httpOnly":c.isHTTPOnly,
        "expires":c.expiresDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull()] })
    }
  }
  private static func fingerprint(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]) else { return "" }
    return String(data:data,encoding:.utf8) ?? ""
  }
  private func pauseVerification(_ snapshot: [String:Any]?) {
    timeout?.cancel(); loadTimeout?.cancel()
    verificationStarted = Date()
    if let snapshot = snapshot { verificationBaseline = snapshot }
    scopedCookies { [weak self] cookies in
      guard let self=self, self.callback != nil else { return }
      self.verificationCookies = Self.fingerprint(cookies.sorted { "\($0["domain"] ?? "")|\($0["path"] ?? "")|\($0["name"] ?? "")" < "\($1["domain"] ?? "")|\($1["path"] ?? "")|\($1["name"] ?? "")" })
      self.fail("verification", "网页需要人工验证")
    }
  }
  var isPresented: Bool { verificationController != nil }
  private var loadTimeout: DispatchWorkItem?
  private var loadBudget: Double { min(30000,max(100,(options["pageTimeoutMs"] as? NSNumber)?.doubleValue ?? 6000)) }
  private var elementBudget: Double { min(30000,max(100,(options["elementTimeoutMs"] as? NSNumber)?.doubleValue ?? 4000)) }

  private var steps: [[String: Any]] {
    var values = options["steps"] as? [[String: Any]] ?? []
    if let selector = options["waitForSelector"] as? String, !selector.isEmpty {
      values.insert(["type": "wait", "selector": selector], at: 0)
    }
    return values
  }

  init(url: URL, options: [String: Any], completion: @escaping (Any) -> Void) {
    self.url = url
    self.options = options
    self.callback = completion
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .default()
    config.defaultWebpagePreferences.allowsContentJavaScript = true
    config.mediaTypesRequiringUserActionForPlayback = .all
    config.userContentController.addUserScript(WKUserScript(source: Self.helpers,
      injectionTime: .atDocumentStart, forMainFrameOnly: true))
    if let storage = options["verificationStorage"] as? [String:Any],
       let data = try? JSONSerialization.data(withJSONObject:["origin":Self.origin(url),"storage":storage]),
       let encoded = String(data:data,encoding:.utf8) {
      let seed = "(()=>{const data="+encoded+";if(location.origin!==data.origin)return;for(const area of ['localStorage','sessionStorage']){try{for(const [key,value] of Object.entries(data.storage[area]||{}))window[area].setItem(key,value)}catch(_){}}})()"
      config.userContentController.addUserScript(WKUserScript(source:seed,injectionTime:.atDocumentStart,forMainFrameOnly:true))
    }
    webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
    super.init()
    webView.navigationDelegate = self
    webView.uiDelegate = self
    webView.customUserAgent = options["userAgent"] as? String
    if #available(iOS 16.4, *) { webView.isInspectable = options["inspectable"] as? Bool == true }
  }

  func start(html: String? = nil) {
    guard !Self.verificationProbe.isEmpty else { fail("verification_probe", "网页验证组件缺失，请更新安装包"); return }
    guard SourceWebBudget.take() else { fail("browser_busy","网页会话数量已达上限"); return }
    holdsPermit = true
    let budget = min(8000, max(100, (options["timeoutMs"] as? NSNumber)?.doubleValue ?? 6000))
    let work = DispatchWorkItem { [weak self] in self?.expire("total_timeout", "网页操作总预算已用完") }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + budget / 1000, execute: work)
    var request = URLRequest(url: url)
    request.timeoutInterval = budget / 1000
    request.allHTTPHeaderFields = options["headers"] as? [String: String]
    request.httpMethod = options["method"] as? String ?? "GET"
    request.httpBody = (options["body"] as? String)?.data(using: .utf8)
    let load = {
      if let html = html { self.webView.loadHTMLString(html, baseURL: self.url) }
      else { self.webView.load(request) }
    }
    var rules: [[String:Any]] = []
    if options["blockAds"] as? Bool != false {
      rules.append(["trigger":["url-filter":"^https?://([^/]+\\.)?(doubleclick\\.net|google-analytics\\.com|googlesyndication\\.com)/", "load-type":["third-party"]],"action":["type":"block"]])
    }
    if options["blockImages"] as? Bool == true {
      rules.append(["trigger":["url-filter":".*", "resource-type":["image"]],"action":["type":"block"]])
    }
    if rules.isEmpty { load(); return }
    let key = "lume-source-\(options["blockAds"] as? Bool != false)-\(options["blockImages"] as? Bool == true)"
    let encoded = String(data: try! JSONSerialization.data(withJSONObject: rules), encoding: .utf8)!
    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: key, encodedContentRuleList: encoded) { [weak self] list, _ in
      guard let self = self, self.callback != nil else { return }
      if let list = list { self.webView.configuration.userContentController.add(list) }
      load()
    }
  }

  func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
               for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
    if action.targetFrame == nil, let address = action.request.url,
       ["http", "https"].contains(address.scheme?.lowercased() ?? "") {
      webView.load(action.request)
    }
    return nil
  }

  func cancel() {
    if verificationResult != nil { completeVerification(false) }
    else if callback == nil { destroy() }
    else { fail("cancelled", "网页请求已取消") }
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let scheme = action.request.url?.scheme?.lowercased() ?? ""
    decisionHandler(["http", "https", "about"].contains(scheme) ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if response.isForMainFrame, let http = response.response as? HTTPURLResponse {
      status = http.statusCode; responseMarkers.removeAll()
      for (key,value) in http.allHeaderFields {
        let name=String(describing:key).lowercased()
        if ["server","x-powered-by","x-waf","x-waf-status","x-cdn","x-via"].contains(name) { responseMarkers[name]=String(String(describing:value).prefix(2048)) }
      }
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    navigating = true
    if verificationResult != nil { return }
    loadTimeout?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.expire("page_timeout", "页面加载超时") }
    loadTimeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + loadBudget / 1000, execute: work)
    generation += 1
    evaluating = false
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    navigating = false
    loadTimeout?.cancel()
    if verificationResult != nil { return }
    advance()
  }

  private func advance() {
    guard callback != nil, !navigating, !evaluating else { return }
    let items = steps
    let step = index < items.count ? items[index] : nil
    let type = step?["type"] as? String
    var program = "const inspectVerification = () => " + probeProgram() + ";\n" + Self.prelude
    var arguments: [String: Any] = ["includeHTML": options["includeHtml"] as? Bool != false, "elementTimeout":elementBudget,
      "apiTimeout": min(30000,max(100,(options["apiTimeoutMs"] as? NSNumber)?.doubleValue ?? 6000))]
    if let step = step {
      arguments["step"] = step
      switch type {
      case "wait": program += "await find(step.selector); return null;"
      case "click": program += "(await find(step.selector)).click(); return null;"
      case "fill": program += #"""
        const element = await find(step.selector);
        const proto = element.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
        Object.getOwnPropertyDescriptor(proto, 'value').set.call(element, String(step.value == null ? '' : step.value));
        element.dispatchEvent(new Event('input', {bubbles: true}));
        element.dispatchEvent(new Event('change', {bubbles: true})); return null;
        """#
      case "evaluate": program += step["script"] as? String ?? "return null;"
      default: fail("arguments", "不支持的网页交互步骤"); return
      }
    } else {
      // This is intentionally source JavaScript, not interpolated form values.
      program += "const result = await (async()=>{\n" + (options["script"] as? String ?? "return null;") + "\n})();\n"
      program += Self.capture
    }
    // Navigation-producing operations are consumed once, even when WebKit
    // destroys the old JS context. Waits resume against the new document.
    let consumed = type == "click" || type == "evaluate"
    if consumed { index += 1 }
    evaluating = true
    generation += 1
    let current = generation
    webView.callAsyncJavaScript(program, arguments: arguments, in: nil, in: .page) { [weak self] response in
      guard let self = self, self.callback != nil, current == self.generation else { return }
      self.evaluating = false
      switch response {
      case .failure(let error):
        let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? ""
        if message.contains("NEED_WEBVIEW_VERIFY") { self.readVerification { self.pauseVerification($0) } }
        else if message.contains("ELEMENT_NOT_FOUND") { self.fail("element_not_found", "目标元素未找到或等待超时") }
        else if message.contains("API_TIMEOUT") { self.fail("api_timeout", "异步接口请求超时") }
        else { self.fail("javascript", "网页交互或 JavaScript 执行失败") }
      case .success(let value):
        if let info = value as? [String: Any], info["requiresVerification"] as? Bool == true {
          self.pauseVerification(info["snapshot"] as? [String:Any]); return
        }
        if step != nil {
          if !consumed { self.index += 1 }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.advance() }
        } else {
          guard var result = value as? [String: Any],
                let html = result["html"] as? String, html.utf8.count <= 512 * 1024,
                let data = try? JSONSerialization.data(withJSONObject: result), data.count <= 768 * 1024 else {
            self.fail("result_size", "网页结果超过上限或不能转换为 JSON"); return
          }
          result["status"] = self.status
          if !self.verifiedSnapshot.isEmpty { result["verificationSession"] = self.verifiedSnapshot }
          self.finish(result)
        }
      }
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if (error as NSError).code != NSURLErrorCancelled { fail("navigation", "网页加载失败") }
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    if (error as NSError).code != NSURLErrorCancelled { fail("navigation", "网页加载失败") }
  }
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail("terminated", "网页进程已结束，请重试") }

  private func expire(_ code: String, _ message: String) {
    guard callback != nil else { return }
    readVerification { [weak self] snapshot in
      guard let self=self, self.callback != nil else { return }
      if snapshot?["challenge"] as? Bool == true { self.pauseVerification(snapshot) }
      else { self.fail(code,message) }
    }
  }
  private func fail(_ code: String, _ message: String) {
    finish(FlutterError(code: code, message: message, details: nil))
  }
  private func finish(_ value: Any) {
    guard let done = callback else { return }
    callback = nil
    timeout?.cancel(); loadTimeout?.cancel()
    if let error = value as? FlutterError, error.code == "verification" {
      // Retain the exact challenge document for a bounded manual handoff.
      done(value); return
    }
    destroy()
    done(value)
  }
  func destroy() {
    verifiedAt=nil; bridgePaths.removeAll()
    let cancellations=Array(bridgeCancellations.values); bridgeCancellations.removeAll()
    for cancel in cancellations { cancel() }
    if holdsPermit { SourceWebBudget.release(); holdsPermit=false }
    timeout?.cancel(); loadTimeout?.cancel(); verificationPoll?.cancel()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.removeFromSuperview()
    // Stop pending JS polling/media and release the document on cancellation.
    webView.loadHTMLString("", baseURL: nil)
    webView.configuration.userContentController.removeAllUserScripts()
    webView.configuration.userContentController.removeAllContentRuleLists()
    verificationController?.dismiss(animated: true)
    verificationController = nil
  }

  func setInspectable(_ value: Bool) {
    if #available(iOS 16.4, *) { webView.isInspectable=value }
  }
  func bridge(_ method: String, arguments args: [String:Any], completion: @escaping (Any)->Void) {
    guard verifiedAt != nil,
      let current=webView.url, Self.origin(current)==Self.origin(url) else {
      completion(FlutterError(code:"bridge_unverified",message:"验证页面已失效，请重新验证",details:nil)); return
    }
    if method == "bridge.configure" {
      guard args["origin"] as? String == Self.origin(url), let paths=args["paths"] as? [String],
        !paths.isEmpty,paths.count<=32,paths.allSatisfy({ p in
          p.hasPrefix("/") && !p.hasPrefix("//") && !p.contains("%") && !p.contains("\\") &&
          !p.contains("?") && !p.contains("#") && !p.contains("*") && !p.split(separator:"/").contains(where: { $0 == "." || $0 == ".." })
        }) else { completion(FlutterError(code:"bridge_scope",message:"请求桥白名单无效",details:nil)); return }
      bridgePaths=Set(paths); completion(true); return
    }
    guard let text=args["url"] as? String, let address=URL(string:text),
      Self.origin(address)==Self.origin(url), address.user==nil,address.password==nil,address.fragment==nil,
      !(URLComponents(url:address,resolvingAgainstBaseURL:false)?.percentEncodedPath.contains("%") ?? true),
      bridgePaths.contains(address.path), let verb=args["method"] as? String,["GET","POST"].contains(verb),
      let headers=args["headers"] as? [String:String],headers.count<=32,bridgeActive<2,
      (args["body"] == nil || args["body"] is NSNull || args["body"] is String),
      (args["body"] as? String ?? "").utf8.count<=65536 else {
      completion(FlutterError(code:"bridge_scope",message:"请求桥仅允许当前源声明的 GET／POST 路径",details:nil)); return
    }
    let denied=Set(["cookie","authorization","proxy-authorization","host","origin","referer","set-cookie","content-length","connection"])
    guard headers.allSatisfy({ key,value in
      !denied.contains(key.lowercased()) && !key.lowercased().hasPrefix("sec-") && value.count<=8192 &&
      value.rangeOfCharacter(from:.newlines)==nil && key.range(of:#"^[!#$%&'*+.^_`|~0-9a-zA-Z-]+$"#,options:.regularExpression) != nil
    }) else { completion(FlutterError(code:"bridge_headers",message:"请求桥不接受凭据请求头",details:nil)); return }
    let key=FlutterDartProject.lookupKey(forAsset:"assets/js/verified_page_request.js")
    guard let path=Bundle.main.path(forResource:key,ofType:nil),let program=try? String(contentsOfFile:path,encoding:.utf8) else {
      completion(FlutterError(code:"bridge_asset",message:"请求桥组件缺失",details:nil)); return
    }
    let requestedTimeout=(args["timeoutMs"] as? NSNumber)?.doubleValue ?? 6000
    guard requestedTimeout.isFinite else {
      completion(FlutterError(code:"bridge_timeout",message:"请求桥超时参数无效",details:nil)); return
    }
    let milliseconds=min(8000,max(100,requestedTimeout))
    let payload: [String:Any] = ["url":text,"method":verb,"headers":headers,
      "body":args["body"] ?? NSNull(),"paths":Array(bridgePaths),"timeoutMs":milliseconds]
    bridgeActive+=1
    let requestID=UUID()
    var finished=false
    let deadline=DispatchWorkItem { [weak self] in
      guard !finished else { return }; finished=true
      self?.bridgeCancellations.removeValue(forKey:requestID)
      self?.bridgeActive=max(0,(self?.bridgeActive ?? 1)-1); self?.destroy()
      completion(FlutterError(code:"bridge_timeout",message:"页面请求超时，验证页面已释放",details:nil))
    }
    bridgeCancellations[requestID] = { [weak self] in
      guard !finished else { return }; finished=true; deadline.cancel()
      self?.bridgeActive=max(0,(self?.bridgeActive ?? 1)-1)
      completion(FlutterError(code:"cancelled",message:"网页会话已撤销，请重新打开源",details:nil))
    }
    DispatchQueue.main.asyncAfter(deadline:.now()+milliseconds/1000+0.25,execute:deadline)
    webView.callAsyncJavaScript("return await ("+program+")(request)",arguments:["request":payload],in:nil,in:.page) { [weak self] value in
      guard !finished else { return }; finished=true; deadline.cancel()
      self?.bridgeCancellations.removeValue(forKey:requestID)
      self?.bridgeActive=max(0,(self?.bridgeActive ?? 1)-1)
      switch value {
      case .success(let reply):
        if let data=reply as? [String:Any] { completion(data) }
        else { completion(FlutterError(code:"bridge_response",message:"页面请求返回格式无效",details:nil)) }
      case .failure: completion(FlutterError(code:"bridge_request",message:"页面请求失败；验证通过不代表指纹或源签名有效",details:nil))
      }
    }
  }

  private func presenter() -> UIViewController? {
    var view = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
    while let next = view?.presentedViewController { view = next }
    return view
  }
  func presentVerification(completion: @escaping (Any) -> Void) {
    guard verificationController == nil, let presenter = presenter() else {
      completion(FlutterError(code:"browser_busy",message:"无法打开验证窗口",details:nil)); return
    }
    verificationResult = completion
    verificationFinished = false
    webView.configuration.userContentController.removeAllContentRuleLists()
    let content = UIViewController()
    content.title = "请在页面完成验证"
    content.view.backgroundColor = .systemBackground
    content.view.addSubview(webView)
    webView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([webView.topAnchor.constraint(equalTo:content.view.safeAreaLayoutGuide.topAnchor),
      webView.bottomAnchor.constraint(equalTo:content.view.bottomAnchor),webView.leadingAnchor.constraint(equalTo:content.view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo:content.view.trailingAnchor)])
    content.navigationItem.leftBarButtonItem = UIBarButtonItem(title:"跳过当前源",style:.plain,target:self,action:#selector(cancelVerification))
    content.navigationItem.rightBarButtonItem = UIBarButtonItem(title:"这是验证页",style:.plain,target:self,action:#selector(confirmVerification))
    let nav = UINavigationController(rootViewController:content)
    nav.isModalInPresentation = true
    verificationController = nav
    let risk = verificationBaseline["heavy"] as? Bool == true
    presenter.present(nav,animated:true) {
      if risk { self.verificationDecision("该站点验证风险较高或没有可操作的验证入口，建议更换网络或代理") }
      else { self.pollVerification() }
    }
    if risk { return }
    // The deadline starts at detection and never resets on navigation or retry text.
    let remaining = max(0,120-Date().timeIntervalSince(verificationStarted))
    let work = DispatchWorkItem { [weak self] in self?.verificationDecision("验证超时（120 秒），可重试或跳过当前源") }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline:.now()+remaining,execute:work)
  }
  @objc private func confirmVerification() { verificationConfirmed = true }
  @objc private func cancelVerification() { completeVerification(false) }
  private func verificationDecision(_ message: String) {
    guard applicationActive else { return }
    guard verificationResult != nil, !verificationFinished else { return }
    verificationFinished = true
    verificationEpoch += 1
    timeout?.cancel(); verificationPoll?.cancel()
    let alert = UIAlertController(title:"网页验证未完成",message:message,preferredStyle:.alert)
    alert.addAction(UIAlertAction(title:"跳过当前源",style:.cancel) { [weak self] _ in self?.completeVerification(false) })
    alert.addAction(UIAlertAction(title:"重试",style:.default) { [weak self] _ in
      guard let self=self else { return }
      self.verificationFinished = false; self.verificationReading = false
      self.verificationStarted = Date(); self.verificationConfirmed = false
      self.webView.reload()
      let work=DispatchWorkItem { [weak self] in self?.verificationDecision("验证超时（120 秒）") }
      self.timeout=work; DispatchQueue.main.asyncAfter(deadline:.now()+120,execute:work)
      self.pollVerification()
    })
    verificationController?.present(alert,animated:true)
  }
  private func completeVerification(_ passed: Bool) {
    guard let done = verificationResult else { return }
    verificationResult = nil
    var value: [String:Any] = ["verified":passed,"url":url.absoluteString,"userAgent":webView.customUserAgent ?? ""]
    if passed { value["verificationSession"] = verifiedSnapshot }
    if passed {
      verifiedAt=Date(); timeout?.cancel(); verificationPoll?.cancel()
      webView.removeFromSuperview(); verificationController?.dismiss(animated:true); verificationController=nil
    } else { destroy() }
    done(value)
  }
  private func pollVerification() {
    guard applicationActive, verificationResult != nil, !verificationReading, !verificationFinished else { return }
    verificationReading = true
    if verificationBaseline["kind"] as? String == "cloudflare" {
      pollCloudflareVerification()
      return
    }
    let epoch = verificationEpoch
    readVerification { [weak self] snapshot in
      guard let self=self, self.verificationResult != nil, !self.verificationFinished, self.verificationEpoch == epoch else { return }
      guard let snapshot=snapshot else { self.scheduleVerification(); return }
      if snapshot["heavy"] as? Bool == true {
        self.verificationDecision("该站点验证风险较高或没有可操作的验证入口，建议更换网络或代理"); return
      }
      self.scopedCookies { [weak self] cookies in
        guard let self=self, self.verificationResult != nil, !self.verificationFinished, self.verificationEpoch == epoch else { return }
        let ordered = cookies.sorted { "\($0["domain"] ?? "")|\($0["path"] ?? "")|\($0["name"] ?? "")" < "\($1["domain"] ?? "")|\($1["path"] ?? "")|\($1["name"] ?? "")" }
        let sameOrigin = (snapshot["origin"] as? String) == Self.origin(self.url)
        let cookieChanged = Self.fingerprint(ordered) != self.verificationCookies
        let storageChanged = ["localStorage","sessionStorage"].contains { Self.fingerprint(snapshot[$0] ?? [:]) != Self.fingerprint(self.verificationBaseline[$0] ?? [:]) }
        let urlChanged = snapshot["url"] as? String != self.verificationBaseline["url"] as? String
        let business = snapshot["business"] as? Bool == true
        let restored = business && self.verificationBaseline["business"] as? Bool != true
        let known = self.verificationBaseline["kind"] as? String != "unknown"
        let iframeLeft = !(self.verificationBaseline["verificationFrames"] as? [String] ?? []).isEmpty && (snapshot["verificationFrames"] as? [String] ?? []).isEmpty
        let signal = known ? (urlChanged || iframeLeft || cookieChanged || storageChanged || snapshot["token"] as? Bool == true || snapshot["success"] as? Bool == true) : (urlChanged || restored)
        let clear = snapshot["blocking"] as? Bool != true || snapshot["token"] as? Bool == true || snapshot["success"] as? Bool == true
        if sameOrigin && business && signal && clear && snapshot["retry"] as? Bool != true && snapshot["ready"] as? Bool == true {
          self.verifiedSnapshot = ["url":self.url.absoluteString,"cookies":cookies,"localStorage":snapshot["localStorage"] ?? [:],"sessionStorage":snapshot["sessionStorage"] ?? [:]]
          self.verificationFinished = true; self.timeout?.cancel()
          DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { [weak self] in self?.completeVerification(true) }
        } else { self.scheduleVerification() }
      }
    }
  }
  /// Preserve the 1.0.193 Cloudflare completion contract. A successful page
  /// does not have to match a source parser's optional business selectors.
  /// The retained browser is kept alive for the newer request bridge.
  private func pollCloudflareVerification() {
    let epoch = verificationEpoch
    let program = #"""
    (()=>({ready:document.readyState==='complete',url:location.href,
      text:(document.body?.innerText||'').trim(),
      blocked:/just a moment|attention required|checking your browser|正在进行安全验证|正在验证您是否是真人|请稍候/i.test(document.title+'\n'+(document.body?.innerText||''))
        ||!!document.querySelector('#challenge-running,#challenge-stage,#challenge-form')}))()
    """#
    webView.evaluateJavaScript(program) { [weak self] value, _ in
      guard let self=self, self.verificationResult != nil, self.verificationEpoch == epoch else { return }
      guard let page=value as? [String:Any], page["ready"] as? Bool == true,
            page["blocked"] as? Bool != true, (page["text"] as? String ?? "").count > 40,
            let current=URL(string:page["url"] as? String ?? ""), Self.origin(current)==Self.origin(self.url) else {
        self.scheduleVerification(); return
      }
      self.scopedCookies { [weak self] cookies in
        guard let self=self, self.verificationResult != nil, self.verificationEpoch == epoch else { return }
        self.readVerification { [weak self] snapshot in
          guard let self=self, self.verificationResult != nil, self.verificationEpoch == epoch else { return }
          self.verifiedSnapshot = ["url":current.absoluteString,"cookies":cookies,
            "localStorage":snapshot?["localStorage"] ?? [:],"sessionStorage":snapshot?["sessionStorage"] ?? [:]]
          self.verificationFinished=true; self.timeout?.cancel()
          DispatchQueue.main.asyncAfter(deadline:.now()+0.8) { [weak self] in self?.completeVerification(true) }
        }
      }
    }
  }
  private func scheduleVerification() {
    verificationReading = false
    guard verificationResult != nil, !verificationFinished else { return }
    let work=DispatchWorkItem { [weak self] in self?.pollVerification() }
    verificationPoll=work; DispatchQueue.main.asyncAfter(deadline:.now()+0.75,execute:work)
  }

  static let helpers = #"""
  (()=>{
    const api = {
      css: (s,root=document)=>Array.from(root.querySelectorAll(s)),
      xpath: (s,root=document)=>{const r=document.evaluate(s,root,null,XPathResult.ORDERED_NODE_SNAPSHOT_TYPE,null);
        return Array.from({length:r.snapshotLength},(_,i)=>r.snapshotItem(i));},
      request: async (url,options={})=>{const c=new AbortController();
        const timer=setTimeout(()=>c.abort(),Math.min(30000,options.timeoutMs||globalThis.__lumeApiTimeout||6000));
        try{return await fetch(url,{...options,signal:c.signal});}
        catch(e){if(e.name==='AbortError')throw new Error('API_TIMEOUT');throw e;}finally{clearTimeout(timer);}}
    };
    Object.defineProperty(globalThis,'LumeWeb',{value:api,configurable:false});
    const records = globalThis.__lumeRequests=[];
    const record=(url,status,type,body='')=>{
      if(!/^https?:/i.test(url))return;
      if(records.length>=16)records.shift();
      records.push({url,status,type,body:String(body).slice(0,16384)});
    };
    const original=fetch;
    globalThis.fetch=async function(...args){
      const response=await original.apply(this,args);
      const url=response.url;
      // Same-origin readable data only. No CORS bypass or opaque response access.
      if(response.type!=='opaque') {
        record(url,response.status,'fetch');
        const length=Number(response.headers.get('content-length'));
        if(length>0&&length<=16384&&/json|text/.test(response.headers.get('content-type')||'')){
          response.clone().text().then(body=>{const r=records.slice().reverse().find(x=>x.url===url);if(r)r.body=body.slice(0,16384);}).catch(()=>{});
        }
      }
      return response;
    };
    const open=XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open=function(method,url,...args){
      this.__lumeURL=new URL(url,location.href).href;
      return open.call(this,method,url,...args);
    };
    const send=XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send=function(...args){
      this.addEventListener('loadend',()=>{
        let text='';try{if(this.responseType===''||this.responseType==='text')text=this.responseText.slice(0,16384);}catch(_){}
        record(this.responseURL||this.__lumeURL,this.status,'xhr',text);
      },{once:true});
      return send.apply(this,args);
    };
  })();
  """#

  static let prelude = #"""
  globalThis.__lumeApiTimeout = apiTimeout;
  const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
  let lastVerificationProbe = Date.now();
  const needsVerification = () => {
    if (Date.now()-lastVerificationProbe < 750) return false;
    lastVerificationProbe=Date.now();
    const snapshot=inspectVerification(); return snapshot && snapshot.challenge;
  };
  const initialVerification = inspectVerification();
  if (initialVerification && initialVerification.challenge) return {requiresVerification:true,snapshot:initialVerification};
  const find = async selector => {
    const deadline = Date.now() + elementTimeout;
    while (true) {
      if (Date.now() > deadline) throw new Error('ELEMENT_NOT_FOUND');
      if (needsVerification()) throw new Error('NEED_WEBVIEW_VERIFY');
      const element = document.querySelector(selector);
      if (element) return element;
      await sleep(50);
    }
  };
  """#

  static let capture = #"""
  const media = new Set();
  for (const element of document.querySelectorAll('video,audio,source')) {
    const url = element.currentSrc || element.src;
    if (url && /^https?:/i.test(url)) media.add(url);
  }
  for (const entry of performance.getEntriesByType('resource')) {
    if (/\.(m3u8|mpd|mp4|m4a|mp3|flv)([?#]|$)/i.test(entry.name)) media.add(entry.name);
  }
  return {url: location.href, title: document.title, html: includeHTML ? document.documentElement.outerHTML : "",
    result: result == null ? null : JSON.parse(JSON.stringify(result)),
    requests: (globalThis.__lumeRequests || []).slice(-16),
    media: Array.from(media).slice(0, 100).map(url => ({url,
      headers: {'User-Agent': navigator.userAgent, 'Referer': location.href}}))};
  """#
}
