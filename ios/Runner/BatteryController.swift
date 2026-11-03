import Flutter
import UIKit

final class BatteryController {
  private let channelName = "lumebox/battery"

  func register(with messenger: FlutterBinaryMessenger) {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "level" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let level = UIDevice.current.batteryLevel
      result(level < 0 ? nil : Int((level * 100).rounded()))
    }
  }
}
