import AVFoundation
import CoreMedia
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  @MainActor func testSourceCancellationReleasesPermitAndRejectsBridge() {
    let baseline=SourceWebBudget.active
    let done=expectation(description:"cancelled once")
    done.assertForOverFulfill=true
    let task=SourceWebTask(url:URL(string:"https://fixture.invalid/")!,options:["scope":"test:cancel","waitForSelector":"#never"]) { reply in
      XCTAssertEqual((reply as? FlutterError)?.code,"cancelled")
      done.fulfill()
    }
    task.start(html:"<html><body><article>业务内容</article></body></html>")
    task.cancel(); task.cancel()
    wait(for:[done],timeout:2)
    XCTAssertEqual(SourceWebBudget.active,baseline)
    task.bridge("bridge.configure",arguments:["origin":"https://fixture.invalid","paths":["/api"]]) { reply in
      XCTAssertEqual((reply as? FlutterError)?.code,"bridge_unverified")
    }
  }

  @MainActor func testPipMediaTimebaseAndPlaybackRate() throws {
    let pump = PipFramePump()
    pump.ensureDisplayLayer()
    let layer = try XCTUnwrap(pump.displayLayer)
    let clock = try XCTUnwrap(layer.controlTimebase)
    pump.setPlaybackState(playing: false)
    XCTAssertEqual(CMTimebaseGetRate(clock), 0)
    XCTAssertTrue(pump.submit(pixels: Data(repeating: 255, count: 32), width: 4, height: 2, timestampMs: 30000))
    XCTAssertEqual(CMTimeGetSeconds(CMTimebaseGetTime(clock)), 30, accuracy: 0.01)
    pump.setPlaybackState(playing: true, rate: 0.5)
    XCTAssertEqual(CMTimebaseGetRate(clock), 0.5)
    pump.setPlaybackState(playing: false)
    XCTAssertTrue(pump.submit(pixels: Data(repeating: 255, count: 32), width: 4, height: 2, timestampMs: 5000))
    XCTAssertEqual(CMTimeGetSeconds(CMTimebaseGetTime(clock)), 5, accuracy: 0.01)
    pump.teardown()
    XCTAssertNil(pump.displayLayer)
  }


  func testSourceLegacyEncoding() {
    let data=Data([0xd6,0xd0,0xce,0xc4])
    XCTAssertEqual(SourceWebController.decodeText(data,charset:"gbk"),"中文")
    XCTAssertEqual(SourceWebController.decodeText(data,charset:"gb2312"),"中文")
    XCTAssertNil(SourceWebController.decodeText(data,charset:"invalid-charset"))
  }

  @MainActor func testSourceWaitHasSeparateTimeout() {
    let done=expectation(description:"element timeout")
    let task=SourceWebTask(url:URL(string:"https://fixture.invalid/")!,options:[
      "timeoutMs":3000,"elementTimeoutMs":100,"waitForSelector":"#absent"
    ]) { response in
      XCTAssertEqual((response as? FlutterError)?.code,"element_not_found"); done.fulfill()
    }
    task.start(html:"<html><body><p>Fixture content</p></body></html>")
    withExtendedLifetime(task) { wait(for:[done],timeout:5) }
  }

  func testSourceHtmlExtraction() throws {
    let rows = try SourceWebController.extract([
      "html": "<article class='card'><a href='../watch/1'>电影 &amp; 剧集</a><b>更新</b><b>高清</b></article>",
      "baseUrl": "https://fixture.invalid/list/", "rowSelector": ".card",
      "fields": [
        "title": ["selector": "a"], "url": ["selector": "a", "attribute": "abs:href"],
        "tags": ["selector": "b", "all": true], "missing": ["selector": "i", "defaultValue": "无"]
      ]
    ])
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(rows[0]["title"] as? String, "电影 & 剧集")
    XCTAssertEqual(rows[0]["url"] as? String, "https://fixture.invalid/watch/1")
    XCTAssertEqual(rows[0]["tags"] as? [String], ["更新", "高清"])
    XCTAssertEqual(rows[0]["missing"] as? String, "无")
    XCTAssertThrowsError(try SourceWebController.extract(["html": "<p>x</p>", "fields": ["bad": ["selector": "["]]]))
  }

  @MainActor func testSourceDynamicPageAndMedia() {
    let done = expectation(description: "dynamic page")
    let task = SourceWebTask(url: URL(string: "https://fixture.invalid/")!, options: [
      "timeoutMs": 6000, "waitForSelector": "#ready",
      "steps": [["type": "fill", "selector": "#q", "value": "手机搜索"],
                ["type": "click", "selector": "#go"], ["type": "wait", "selector": "#result"]],
      "script": "return await Promise.resolve(LumeWeb.xpath('//*[@id=\"result\"]')[0].textContent);"
    ]) { response in
      let value = response as? [String: Any]
      XCTAssertEqual(value?["result"] as? String, "手机搜索")
      XCTAssertTrue((value?["html"] as? String ?? "").contains("id=\"result\""))
      let media = value?["media"] as? [[String: Any]]
      XCTAssertEqual(media?.first?["url"] as? String, "https://cdn.invalid/movie.mp4")
      done.fulfill()
    }
    task.start(html: """
      <html><body><input id='q'><button id='go' onclick="const n=document.createElement('p');n.id='result';n.textContent=document.querySelector('#q').value;document.body.append(n)">搜索</button>
      <video src='https://cdn.invalid/movie.mp4' preload='none'></video>
      <script>setTimeout(()=>{const n=document.createElement('div');n.id='ready';document.body.append(n)},50)</script></body></html>
      """)
    withExtendedLifetime(task) { wait(for: [done], timeout: 10) }
  }

  @MainActor func testSourceVerificationAndCancellation() {
    let done = expectation(description: "verification")
    let task = SourceWebTask(url: URL(string: "https://fixture.invalid/")!, options: ["waitForSelector": "#never"]) { response in
      XCTAssertEqual((response as? FlutterError)?.code, "verification")
      done.fulfill()
    }
    task.start(html: "<html><head><title>Just a moment...</title></head><body><div id='challenge-running'></div></body></html>")
    withExtendedLifetime(task) { wait(for: [done], timeout: 10) }
    task.destroy()
    var completions = 0
    let cancel = SourceWebTask(url: URL(string: "https://fixture.invalid/")!, options: [:]) { response in
      XCTAssertEqual((response as? FlutterError)?.code, "cancelled")
      completions += 1
    }
    cancel.start(html: "<html><body></body></html>")
    cancel.cancel()
    cancel.cancel()
    XCTAssertEqual(completions, 1)
  }

  @MainActor func testUnknownVerificationRetainsDocumentAndOrdinaryLoginDoesNot() {
    let challenge = expectation(description:"unknown verification")
    let task = SourceWebTask(url:URL(string:"https://fixture.invalid/")!,options:["waitForSelector":"#business"]) { response in
      XCTAssertEqual((response as? FlutterError)?.code,"verification")
      challenge.fulfill()
    }
    task.start(html:"<html><body><div id='verify-box'>安全验证，请点击完成验证<button>确认</button></div></body></html>")
    withExtendedLifetime(task) { wait(for:[challenge],timeout:10) }
    task.destroy()
    let normal = expectation(description:"ordinary login")
    let login = SourceWebTask(url:URL(string:"https://fixture.invalid/")!,options:["waitForSelector":"#ready"]) { response in
      XCTAssertNil(response as? FlutterError)
      normal.fulfill()
    }
    login.start(html:"<html><body><form id='ready'>登录，请稍候<input name='username'><button>登录</button></form></body></html>")
    withExtendedLifetime(login) { wait(for:[normal],timeout:10) }
  }
}
