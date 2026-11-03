package com.lumebox.app

import android.app.Activity
import android.os.BatteryManager
import android.view.KeyEvent
import android.content.Intent
import android.content.ComponentName
import android.content.pm.PackageManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var readerKeysEnabled = false
    private var readerKeys: MethodChannel? = null
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (readerKeysEnabled && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) {
            readerKeys?.invokeMethod("turn", if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) 1 else -1)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean {
        if (readerKeysEnabled && (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)) return true
        return super.onKeyUp(keyCode, event)
    }
    private var exportResult: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    override fun configureFlutterEngine(engine: FlutterEngine) {
        readerKeys = MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/reader_keys").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "configure") {
                    readerKeysEnabled = call.argument<Boolean>("enabled") == true
                    result.success(null)
                } else result.notImplemented()
            }
        }
        DanmakuCredentials.register(this, engine.dartExecutor.binaryMessenger)
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/battery")
            .setMethodCallHandler { call, result ->
                if (call.method != "level") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val manager = getSystemService(BATTERY_SERVICE) as? BatteryManager
                val level = manager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                result.success(level?.takeIf { it in 0..100 })
            }
        IntroRecognition(this, engine.dartExecutor.binaryMessenger)
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/app_icon")
            .setMethodCallHandler { call, result ->
                val names = listOf("default", "Aurora", "Obsidian", "Solar", "Orbit", "Prism", "Spark")
                fun component(name: String) = ComponentName(packageName, "$packageName.icons.${if (name == "default") "Default" else name}")
                if (call.method == "current") {
                    val current = names.firstOrNull { name ->
                        val state = packageManager.getComponentEnabledSetting(component(name))
                        state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                            (name == "default" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
                    }
                    result.success(current ?: "default")
                } else if (call.method == "set") {
                    val selected = call.arguments as? String
                    if (selected !in names) { result.error("icon", "Unknown icon", null); return@setMethodCallHandler }
                    try {
                        // Enable the destination first, so a failed switch never removes every launcher.
                        packageManager.setComponentEnabledSetting(component(selected!!), PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                        names.filter { it != selected }.forEach { name ->
                            packageManager.setComponentEnabledSetting(component(name), PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                        }
                        result.success(true)
                    } catch (error: Exception) { result.error("icon", error.message, null) }
                } else { result.notImplemented() }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "lumebox/configuration")
            .setMethodCallHandler { call, result ->
                if (call.method != "export") { result.notImplemented(); return@setMethodCallHandler }
                if (exportResult != null) { result.error("busy", "Export already open", null); return@setMethodCallHandler }
                val bytes = call.argument<ByteArray>("bytes") ?: call.argument<String>("text")?.toByteArray(Charsets.UTF_8)
                val name = call.argument<String>("name")
                if (bytes == null || bytes.size > 32 * 1024 * 1024 || name == null || name.contains("/") || name.contains("\\")) { result.error("arguments", "Missing backup", null); return@setMethodCallHandler }
                exportBytes = bytes
                exportResult = result
                try {
                    startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = if (name.endsWith(".zip")) "application/zip" else "application/json"
                        putExtra(Intent.EXTRA_TITLE, name)
                    }, 4271)
                } catch (error: Exception) {
                    exportBytes = null; exportResult = null
                    result.error("export", error.message, null)
                }
            }
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4271) return
        val result = exportResult ?: return
        val bytes = exportBytes
        exportResult = null; exportBytes = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) { result.success(false); return }
        try {
            val stream = contentResolver.openOutputStream(uri) ?: throw IllegalStateException("Cannot open destination")
            stream.use { it.write(bytes) }
            result.success(true)
        } catch (error: Exception) { result.error("export", error.message, null) }
    }
}
