import AVFoundation
import Flutter

/// Metadata only: no AVPlayer, rendering layer or video decoder is created.
final class MediaTrackProbe {
  func register(with messenger: FlutterBinaryMessenger) {
    UserDefaults.standard.removeObject(forKey:"lumebox.mediaOwner")
    FlutterMethodChannel(name:"lumebox/mediaTracks",binaryMessenger:messenger)
      .setMethodCallHandler { call,result in
        if call.method == "owner",let owner = call.arguments as? String,
           ["audioBook","tts","video"].contains(owner) {
          UserDefaults.standard.set(owner,forKey:"lumebox.mediaOwner");result(nil);return
        }
        guard call.method == "inspect",let args = call.arguments as? [String:Any],
          let raw = args["url"] as? String,let url = URL(string:raw),
          ["file","https","http"].contains(url.scheme ?? "") else {
          result(["known":false]);return
        }
        let headers = args["headers"] as? [String:String] ?? [:]
        let asset = AVURLAsset(url:url,options:["AVURLAssetHTTPHeaderFieldsKey":headers])
        var completed = false
        func finish(_ data:[String:Bool]) {
          guard !completed else { return };completed = true;result(data)
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+9) {
          if !completed { asset.cancelLoading();finish(["known":false]) }
        }
        asset.loadValuesAsynchronously(forKeys:["tracks"]) {
          DispatchQueue.main.async {
            var error:NSError?
            guard asset.statusOfValue(forKey:"tracks",error:&error) == .loaded else {
              finish(["known":false]);return
            }
            finish(["known":true,"audio":!asset.tracks(withMediaType:.audio).isEmpty,
              "video":!asset.tracks(withMediaType:.video).isEmpty])
          }
        }
      }
  }
}
