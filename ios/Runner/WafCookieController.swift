import Flutter
import Foundation
import WebKit
import Network
import UIKit

/// 内置网页视图的**原生 Cookie 仓库读取**（iOS）。
///
/// 契约见 Dart 侧 `WafWebViewPage`：方法通道 `lumebox/webview` 的 `allCookies`
/// （返回 `[{name, value, domain, path}]`）。
///
/// ## 为什么必须走原生
///
/// Cloudflare 的 `cf_clearance` 是 **HttpOnly** 的——`document.cookie` 看不见它。
/// 用户在 App 内过完真人校验后，真正能复用的那枚凭证只在 `WKHTTPCookieStore`
/// 里；`webview_flutter` 的 Dart API 只能**写** Cookie、不能枚举，因此这里补一层
/// 只读通道，把整套 Cookie（含 HttpOnly）取回来交给 Dart 存进图源会话。
///
/// 只读、不写、不删：网页视图退出后这些 Cookie 仍留在 WKWebView 的数据仓里，
/// 下次打开网页视图仍是同一个登录态（用户不必反复验证）。
final class WafCookieController: NSObject {
  private let channelName = "lumebox/webview"

  func register(with messenger: FlutterBinaryMessenger) {
    imageNetwork.register(with: messenger)
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "cancelVerifiedRead":
        if let args = call.arguments as? [String: Any], let id = args["requestId"] as? String {
          self.reads[id]?.cancel(); self.imageReads[id]?.cancel()
        }
        result(nil)
      case "readVerifiedResource":
        guard let args = call.arguments as? [String: Any], let text = args["url"] as? String,
              let url = URL(string: text), url.scheme == "https", url.user == nil,
              self.imageReads.count < 4 else {
          result(FlutterError(code: "invalid_image", message: "Image session unavailable", details: nil)); return
        }
        let id = args["requestId"] as? String ?? UUID().uuidString
        guard self.imageReads[id] == nil else { result(FlutterError(code:"duplicate_request",message:"Duplicate image request",details:nil)); return }
        let task = VerifiedImageRead(url: url, userAgent: args["userAgent"] as? String,
                                     method: args["method"] as? String ?? "GET",
                                     headers: args["headers"] as? [String: String] ?? [:],
                                     body: args["body"] as? String) { response in
          self.imageReads.removeValue(forKey: id)
          result(response)
        }
        self.imageReads[id] = task
        task.start()
      case "readVerifiedPage":
        guard let args = call.arguments as? [String: Any], let text = args["url"] as? String,
              let url = URL(string: text), ["https", "http"].contains(url.scheme ?? ""), url.user == nil else {
          result(FlutterError(code: "invalid_url", message: "Invalid page URL", details: nil)); return
        }
        guard self.reads.count < 4 else {
          result(FlutterError(code: "busy", message: "Browser session busy", details: nil)); return
        }
        let id = args["requestId"] as? String ?? UUID().uuidString
        guard self.reads[id] == nil else { result(FlutterError(code:"duplicate_request",message:"Duplicate page request",details:nil)); return }
        let task = VerifiedPageRead(url: url, userAgent: args["userAgent"] as? String) { response in
          self.reads.removeValue(forKey: id)
          result(response)
        }
        self.reads[id] = task
        task.start()
      case "allCookies":
        WafCookieController.allCookies(url: (call.arguments as? [String:Any])?["url"] as? String, result: result)
      case "clearWebsiteDataForHosts":
        let args = call.arguments as? [String: Any] ?? [:]
        WafCookieController.clearWebsiteData(
          hosts: args["hosts"] as? [String] ?? [],
          protectedHosts: args["protectedHosts"] as? [String] ?? [], result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private let imageNetwork = ImageNetworkController()
  private var reads: [String: VerifiedPageRead] = [:]
  private var imageReads: [String: VerifiedImageRead] = [:]

  /// 枚举默认数据仓里的全部 Cookie；`WKHTTPCookieStore` 是异步回调接口。
  ///
  /// A URL limits export to its domain cookies, preserving all paths and
  /// HttpOnly attributes. CAPTCHA iframe cookies never become business cookies.
  /// Clear only requested station domains. Shared domains still used by another section are retained.
  private static func clearWebsiteData(hosts: [String], protectedHosts: [String], result: @escaping FlutterResult) {
    let targets = hosts.map { $0.lowercased() }.filter { !$0.isEmpty }
    let protected = protectedHosts.map { $0.lowercased() }.filter { !$0.isEmpty }
    func matches(_ domain: String, _ host: String) -> Bool {
      let value = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
      return !value.isEmpty && (host == value || host.hasSuffix("." + value))
    }
    func removable(_ domain: String) -> Bool {
      targets.contains { matches(domain, $0) } && !protected.contains { matches(domain, $0) }
    }
    guard !targets.isEmpty else { result(nil); return }
    NotificationCenter.default.post(name:Notification.Name("LumeWebSessionsInvalidated"),object:nil,
      userInfo:["hosts":targets.filter { !protected.contains($0) }])
    let dataStore = WKWebsiteDataStore.default()
    dataStore.httpCookieStore.getAllCookies { cookies in
      let group = DispatchGroup()
      for cookie in cookies where removable(cookie.domain) {
        group.enter()
        dataStore.httpCookieStore.delete(cookie) { group.leave() }
      }
      for cookie in HTTPCookieStorage.shared.cookies ?? [] where removable(cookie.domain) {
        HTTPCookieStorage.shared.deleteCookie(cookie)
      }
      group.notify(queue: .main) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        dataStore.fetchDataRecords(ofTypes: types) { records in
          let selected = records.filter { removable($0.displayName) }
          dataStore.removeData(ofTypes: types, for: selected) { result(nil) }
        }
      }
    }
  }

  private static func allCookies(url: String?, result: @escaping FlutterResult) {
    let store = WKWebsiteDataStore.default().httpCookieStore
    store.getAllCookies { cookies in
      let host = url.flatMap { URL(string:$0)?.host }?.lowercased()
      let list: [[String: Any]] = cookies.filter { cookie in
        guard let host = host else { return true }
        let domain = cookie.domain.lowercased().trimmingCharacters(in:CharacterSet(charactersIn:"."))
        return host == domain || (cookie.domain.hasPrefix(".") && host.hasSuffix("."+domain))
      }.map { cookie in
        [
          "name": cookie.name,
          "value": cookie.value,
          "domain": cookie.domain,
          "path": cookie.path,
          "secure": cookie.isSecure,
          "httpOnly": cookie.isHTTPOnly,
          "expires": cookie.expiresDate.map { $0.timeIntervalSince1970 as Any } ?? NSNull(),
        ]
      }
      DispatchQueue.main.async { result(list) }
    }
  }
}

/// Use Apple's TLS/HTTP stack. Only matching Cloudflare verification cookies may be reused.
private final class ImageNetworkController {
  private var reads: [String: SourceHTTPRead] = [:]
  func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name:"lumebox/image_network",binaryMessenger:messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "cancel", let args = call.arguments as? [String:Any], let id = args["requestId"] as? String {
        self?.reads[id]?.cancel(); result(nil); return
      }
      guard call.method == "get" else { result(FlutterMethodNotImplemented); return }
      guard let self = self, let args = call.arguments as? [String:Any],
        let address = args["url"] as? String, let url = URL(string:address),
        ["http","https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else {
        result(FlutterError(code:"bad_url",message:"HTTP 请求地址无效",details:nil)); return
      }
      guard self.reads.count < 16 else { result(FlutterError(code:"network_busy",message:"系统网络请求队列忙",details:nil)); return }
      let id = args["requestId"] as? String ?? UUID().uuidString
      guard self.reads[id] == nil else { result(FlutterError(code:"duplicate_request",message:"重复请求标识",details:nil)); return }
      let read = SourceHTTPRead(url:url,options:args,state: { waiting in
        channel.invokeMethod("state",arguments:["requestId":id,"waiting":waiting])
      }) { [weak self] value in
        self?.reads.removeValue(forKey:id); result(value)
      }
      self.reads[id] = read; read.start()
    }
  }
}

/// Bounded streaming reader. URLSession uses system proxy/VPN settings directly.
private final class SourceHTTPRead: NSObject, URLSessionDataDelegate {
  private let url: URL
  private let options: [String:Any]
  private var callback: ((Any)->Void)?
  private var session: URLSession?
  private var task: URLSessionDataTask?
  private var response: HTTPURLResponse?
  private var bytes = Data()
  private var finished = false
  private var deadline: DispatchWorkItem?
  private var pathObserver: UUID?
  private let state: (Bool)->Void
  private let limit: Int
  init(url:URL,options:[String:Any],state:@escaping (Bool)->Void,completion:@escaping (Any)->Void) {
    self.url=url; self.options=options; callback=completion
    self.state=state
    limit=min(16*1024*1024+1,max(1,options["maxBytes"] as? Int ?? 8*1024*1024))
    super.init()
  }
  func start() {
    let config=URLSessionConfiguration.ephemeral
    config.httpCookieStorage=nil; config.httpShouldSetCookies=false; config.urlCache=nil
    let timeout=min(120,max(0.1,options["timeoutSeconds"] as? Double ?? 20))
    config.timeoutIntervalForRequest=timeout; config.timeoutIntervalForResource=timeout
    config.waitsForConnectivity=true
    let expiry=DispatchWorkItem { [weak self] in
      self?.finish(FlutterError(code:"api_timeout",message:"等待网络或请求超时",details:nil))
    }
    deadline=expiry; DispatchQueue.main.asyncAfter(deadline:.now()+timeout,execute:expiry)
    pathObserver=SourceNetworkPath.shared.observe { [weak self] available in
      guard let self=self, !self.finished else { return }; self.state(!available)
    }
    // Do not install connectionProxyDictionary, custom sockets or protocol tunnels.
    session=URLSession(configuration:config,delegate:self,delegateQueue:OperationQueue.main)
    var request=URLRequest(url:url)
    request.timeoutInterval=timeout
    request.httpMethod=options["method"] as? String ?? "GET"
    request.allHTTPHeaderFields=options["headers"] as? [String:String]
    if let binary=options["bodyBytes"] as? FlutterStandardTypedData { request.httpBody=binary.data }
    else { request.httpBody=(options["body"] as? String)?.data(using:.utf8) }
    task=session!.dataTask(with:request); task?.resume()
  }
  func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,
    completionHandler:@escaping (URLSession.ResponseDisposition)->Void) {
    self.response=response as? HTTPURLResponse
    state(false)
    completionHandler(.allow)
  }
  func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
    guard !finished else { return }
    let room=limit-bytes.count
    bytes.append(data.prefix(room))
    if data.count>room || (options["maxBytes"] != nil && bytes.count==limit) {
      if options["maxBytes"] == nil { finish(FlutterError(code:"response_size",message:"接口响应超过 8MB",details:nil)) }
      else { succeed() }
    }
  }
  func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
    guard !finished else { return }
    if let error=error as NSError? {
      let certificate=error.domain==NSURLErrorDomain && [-1201,-1202,-1203,-1204].contains(error.code)
      let tls=error.domain==NSURLErrorDomain && error.code==NSURLErrorSecureConnectionFailed
      let timeout=error.domain==NSURLErrorDomain && error.code==NSURLErrorTimedOut
      let transport=error.domain==NSURLErrorDomain && error.code==NSURLErrorAppTransportSecurityRequiresSecureConnection
      var details:[String:Any]=["domain":error.domain,"code":error.code]
      if let underlying=error.userInfo[NSUnderlyingErrorKey] as? NSError {
        details["underlyingDomain"]=underlying.domain
        details["underlyingCode"]=underlying.code
      }
      finish(FlutterError(code:certificate ? "certificate" : tls ? "tls_handshake" : transport ? "transport_security" : timeout ? "api_timeout" : "network",
        message:certificate ? "CERTIFICATE_VERIFY_FAILED" : tls ? "TLS_HANDSHAKE_FAILED：HTTPS安全连接失败" : transport ? "iOS 阻止了此站点的 HTTP 请求，请更新 App 的站点兼容配置" : timeout ? "接口请求超时" : "系统网络请求失败",details:details)); return
    }
    succeed()
  }
  func urlSession(_ session:URLSession,taskIsWaitingForConnectivity task:URLSessionTask) { if !finished { state(true) } }
  func cancel() { finish(FlutterError(code:"cancelled",message:"请求已取消",details:nil)) }
  private func stopWaiting() {
    deadline?.cancel(); deadline=nil
    if let id=pathObserver { SourceNetworkPath.shared.remove(id); pathObserver=nil }
    state(false)
  }
  private func succeed() {
    guard !finished else { return }
    guard let response=response, let address=response.url else { finish(FlutterError(code:"http_response",message:"系统未返回 HTTP 响应",details:nil)); return }
    var headers:[String:String]=[:]
    for (key,value) in response.allHeaderFields { headers[String(describing:key)]=String(describing:value) }
    let cookies=HTTPCookie.cookies(withResponseHeaderFields:headers,for:address)
    let group=DispatchGroup()
    for cookie in cookies {
      group.enter(); WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie) { group.leave() }
    }
    // Cancel the stream at the requested prefix limit; deliver a result only once.
    let data=bytes
    finished=true; stopWaiting(); task?.cancel(); session?.invalidateAndCancel(); session=nil
    group.notify(queue:.main) {
      self.deliver(["status":response.statusCode,"headers":headers,"body":FlutterStandardTypedData(bytes:data)])
    }
  }
  private func finish(_ value:Any) {
    guard !finished else { return }
    finished=true; stopWaiting(); task?.cancel(); session?.invalidateAndCancel(); session=nil
    deliver(value)
  }
  private func deliver(_ value:Any) {
    guard let done=callback else { return }; callback=nil; bytes.removeAll(); done(value)
  }
  func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
    newRequest request:URLRequest,completionHandler:@escaping (URLRequest?)->Void) {
    if options["followRedirects"] as? Bool == false { completionHandler(nil); return }
    guard let next=request.url, ["http","https"].contains(next.scheme ?? ""), next.user==nil, next.password==nil else {
      completionHandler(nil); return
    }
    var outgoing=request
    if response.url?.host != next.host || response.url?.port != next.port || response.url?.scheme != next.scheme {
      outgoing.setValue(nil,forHTTPHeaderField:"Cookie"); outgoing.setValue(nil,forHTTPHeaderField:"Authorization")
    }
    if response.url?.scheme=="https" && next.scheme=="http" { outgoing.setValue(nil,forHTTPHeaderField:"Referer") }
    completionHandler(outgoing)
  }
}

/// One system network observer for all source requests; no probes or proxy tunnel.
private final class SourceNetworkPath {
  static let shared=SourceNetworkPath()
  private let monitor=NWPathMonitor()
  private var available: Bool?
  private var listeners: [UUID:(Bool)->Void]=[:]
  private init() {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self=self else { return }
      if self.available != nil {
        NotificationCenter.default.post(name:Notification.Name("LumeWebSessionsInvalidated"),object:nil)
      }
      self.available=path.status == .satisfied
      for callback in Array(self.listeners.values) { callback(self.available!) }
    }
    monitor.start(queue:.main)
  }
  func observe(_ callback:@escaping (Bool)->Void)->UUID {
    let id=UUID(); listeners[id]=callback
    if let available=available { callback(available) }
    return id
  }
  func remove(_ id:UUID) { listeners.removeValue(forKey:id) }
}

/// Navigation uses the same default WebKit data store as the visible verification page.
/// It does not solve challenges: a remaining challenge is returned as an ordinary 403.
private final class VerifiedPageRead: NSObject, WKNavigationDelegate {
  private let webView: WKWebView
  private let url: URL
  private var completion: ((Any) -> Void)?
  private var timeout: DispatchWorkItem?
  private var poll: DispatchWorkItem?
  private var status = 200
  private var mime = "text/html"
  init(url: URL, userAgent: String?, completion: @escaping (Any) -> Void) {
    self.url = url
    self.completion = completion
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    webView = WKWebView(frame: CGRect(x: -1000, y: -1000, width: 390, height: 600), configuration: configuration)
    super.init()
    webView.customUserAgent = userAgent
    webView.navigationDelegate = self
  }
  private var holdsPermit=false
  deinit { if holdsPermit { SourceWebBudget.release() } }
  func start() {
    guard SourceWebBudget.take() else { finish(FlutterError(code:"browser_busy",message:"网页会话数量已达上限",details:nil)); return }
    holdsPermit=true
    let work = DispatchWorkItem { [weak self] in
      self?.finish(FlutterError(code: "timeout", message: "Verified page timed out", details: nil))
    }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: work)
    webView.load(URLRequest(url: url))
  }
  func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
               decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
    if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse {
      status = response.statusCode
      mime = response.mimeType ?? "text/html"
    }
    decisionHandler(.allow)
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    readDocument(force: true)
  }
  func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
    scheduleRead()
  }
  private func scheduleRead() {
    guard completion != nil else { return }
    let work = DispatchWorkItem { [weak self] in self?.readDocument(force: false) }
    poll = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
  }
  private func readDocument(force: Bool) {
    guard completion != nil else { return }
    let body = mime.contains("html") ? "document.documentElement.outerHTML" : "document.body.innerText"
    let script = "({ready: document.readyState, body: \(body)})"
    webView.evaluateJavaScript(script) { [weak self] value, error in
      guard let self = self else { return }
      if let error = error { self.finish(FlutterError(code: "read_failed", message: error.localizedDescription, details: nil)); return }
      let document = value as? [String: Any] ?? [:]
      let text = document["body"] as? String ?? ""
      // A committed challenge document is not the final navigation result.
      // Give WebKit time to reuse the user's existing verification session.
      let challenge = text.range(of: "cf-chl-|challenge-platform|<title[^>]*>\\s*(Just a moment|Attention Required)",
                                 options: [.regularExpression, .caseInsensitive]) != nil
      if document["ready"] as? String == "loading" || challenge {
        self.scheduleRead(); return
      }
      guard text.utf8.count <= 10 * 1024 * 1024 else {
        self.finish(FlutterError(code: "too_large", message: "Page too large", details: nil)); return
      }
      self.finish(["status": self.status, "body": text, "contentType": self.mime])
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(FlutterError(code: "navigation_failed", message: error.localizedDescription, details: nil))
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(FlutterError(code: "navigation_failed", message: error.localizedDescription, details: nil))
  }
  func cancel() { finish(FlutterError(code:"cancelled",message:"请求已取消",details:nil)) }
  private func finish(_ value: Any) {
    guard let callback = completion else { return }
    if holdsPermit { SourceWebBudget.release(); holdsPermit=false }
    completion = nil
    timeout?.cancel()
    poll?.cancel()
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview(); webView.loadHTMLString("",baseURL:nil)
    callback(value)
  }
}

/// Fetch an image in its own WebKit origin, retaining only the browser's
/// domain-scoped cookies and TLS identity. No source-site credentials are copied.
private final class VerifiedImageRead: NSObject, WKNavigationDelegate {
  private let webView: WKWebView
  private let url: URL
  private let method: String
  private let headers: [String: String]
  private let body: String?
  private var completion: ((Any) -> Void)?
  private var timeout: DispatchWorkItem?
  private var fetching = false
  init(url: URL, userAgent: String?, method: String, headers: [String: String], body: String?, completion: @escaping (Any) -> Void) {
    self.url = url
    self.method = method; self.headers = headers; self.body = body
    self.completion = completion
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    webView = WKWebView(frame: CGRect(x: -1000, y: -1000, width: 390, height: 600), configuration: configuration)
    super.init()
    webView.customUserAgent = userAgent
    webView.navigationDelegate = self
  }
  private var holdsPermit=false
  deinit { if holdsPermit { SourceWebBudget.release() } }
  func start() {
    guard SourceWebBudget.take() else { finish(FlutterError(code:"browser_busy",message:"网页会话数量已达上限",details:nil)); return }
    holdsPermit=true
    let work = DispatchWorkItem { [weak self] in
      self?.finish(FlutterError(code: "timeout", message: "Image verification session timed out", details: nil))
    }
    timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: work)
    var origin = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    origin.path = "/"; origin.query = nil; origin.fragment = nil
    webView.load(URLRequest(url: origin.url!))
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard completion != nil, !fetching else { return }
    fetching = true
    let script = """
      const target = new URL(address);
      if (target.origin !== location.origin) throw new Error('Image origin changed');
      const options = {credentials:'same-origin', method, headers};
      if (method !== 'GET' && method !== 'HEAD' && body !== null) options.body = body;
      const response = await fetch(target.href, options);
      const blob = await response.blob();
      if (blob.size > 20 * 1024 * 1024) throw new Error('Image too large');
      const data = await new Promise((resolve,reject) => {
        const reader = new FileReader(); reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(new Error('Image read failed')); reader.readAsDataURL(blob);
      });
      return {status:response.status, contentType:response.headers.get('content-type') || '',
              body:data.substring(data.indexOf(',') + 1)};
      """
    webView.callAsyncJavaScript(script, arguments: ["address": url.absoluteString, "method": method, "headers": headers, "body": body as Any? ?? NSNull()], in: nil, in: .page) { [weak self] result in
      guard let self = self else { return }
      switch result {
      case .success(let value):
        guard var response = value as? [String: Any], let encoded = response["body"] as? String,
              let bytes = Data(base64Encoded: encoded) else {
          self.finish(FlutterError(code: "image_response", message: "Invalid browser image response", details: nil)); return
        }
        response["body"] = FlutterStandardTypedData(bytes: bytes)
        self.finish(response)
      case .failure(let error):
        self.finish(FlutterError(code: "image_read", message: error.localizedDescription, details: nil))
      }
    }
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    finish(FlutterError(code: "image_navigation", message: error.localizedDescription, details: nil))
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    finish(FlutterError(code: "image_navigation", message: error.localizedDescription, details: nil))
  }
  func cancel() { finish(FlutterError(code:"cancelled",message:"请求已取消",details:nil)) }
  private func finish(_ value: Any) {
    guard let callback = completion else { return }
    if holdsPermit { SourceWebBudget.release(); holdsPermit=false }
    completion = nil; timeout?.cancel()
    webView.stopLoading(); webView.navigationDelegate = nil
    webView.removeFromSuperview(); webView.loadHTMLString("",baseURL:nil)
    callback(value)
  }
}
