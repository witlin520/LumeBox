package com.lumebox.app

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Bitmap
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.min

class IntroRecognition(private val activity: Activity, messenger: BinaryMessenger) {
    private val worker = Executors.newSingleThreadExecutor { runnable -> Thread(runnable, "LumeBox-intro-idle").apply { priority = Thread.MIN_PRIORITY } }
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private val retrievers = mutableMapOf<String, MediaMetadataRetriever>()
    private val ocr by lazy { TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build()) }

    init {
        MethodChannel(messenger, "lumebox/reference_intro").setMethodCallHandler { call, result ->
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val session = args["session"] as? String ?: ""
            if (call.method == "resources") { result.success(resources()); return@setMethodCallHandler }
            if (call.method == "cancel") { cancelled.add(session); result.success(null); return@setMethodCallHandler }
            worker.execute {
                try {
                    val data: Any? = when (call.method) {
                        "release" -> { retrievers.remove(session)?.release(); cancelled.remove(session); null }
                        "metadata" -> emptyMap<String, Any>() // MKV EBML and MPV chapter reads run in Dart.
                        "sample" -> sample(args, session)
                        "classify" -> throw UnsupportedOperationException("MobileCLIP Core ML requires iOS; audio YAMNet runs on both platforms")
                        else -> { main.post { result.notImplemented() }; return@execute }
                    }
                    main.post { result.success(data) }
                } catch (error: Exception) {
                    // Deliberately omit decoder error messages containing signed URLs.
                    main.post { result.error("intro_scan", "Native scan unavailable or cancelled (${error.javaClass.simpleName})", null) }
                }
            }
        }
    }
    private fun resources(): Map<String, Any> {
        val power = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        val connection = activity.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connection.getNetworkCapabilities(connection.activeNetwork)
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val charging = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) in listOf(BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL)
        val thermal = if (Build.VERSION.SDK_INT >= 29) power.currentThermalStatus else PowerManager.THERMAL_STATUS_NONE
        val memory = ActivityManager.MemoryInfo().also { (activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(it) }
        val allowed = !power.isPowerSaveMode && thermal < PowerManager.THERMAL_STATUS_SEVERE && !memory.lowMemory && memory.availMem > 256L * 1024 * 1024
        return mapOf("allowed" to allowed, "reason" to if (allowed) "" else "Power, thermal or memory limit", "wifi" to (network?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true), "charging" to charging)
    }
    private fun check(session: String) { check(!cancelled.contains(session)) { "Cancelled" } }
    @Suppress("UNCHECKED_CAST")
    private fun source(args: Map<*, *>, session: String): MediaMetadataRetriever {
        check(session)
        return retrievers.getOrPut(session) {
            MediaMetadataRetriever().apply {
                val url = args["url"] as String
                if (url.startsWith("file:")) setDataSource(java.net.URI(url).path)
                else setDataSource(url, args["headers"] as? Map<String, String> ?: emptyMap())
            }
        }
    }
    private fun sample(args: Map<*, *>, session: String): Map<String, Any> {
        val retriever = source(args, session)
        val at = (args["atMs"] as Number).toLong()
        val frame = if (Build.VERSION.SDK_INT >= 27) retriever.getScaledFrameAtTime(at * 1000, MediaMetadataRetriever.OPTION_CLOSEST, 384, 384)
          else retriever.getFrameAtTime(at * 1000, MediaMetadataRetriever.OPTION_CLOSEST)?.let { original -> Bitmap.createScaledBitmap(original, 384, 384, true).also { if (it !== original) original.recycle() } }
        requireNotNull(frame) { "No decoded frame" }
        try {
            check(session)
            val small = Bitmap.createScaledBitmap(frame, 32, 32, true)
            val pixels = IntArray(1024)
            small.getPixels(pixels, 0, 32, 0, 0, 32, 32)
            if (small !== frame) small.recycle()
            val gray = ByteArray(1024) { i -> val c = pixels[i]; (((c shr 16 and 255) * 77 + (c shr 8 and 255) * 150 + (c and 255) * 29) shr 8).toByte() }
            val result = mutableMapOf<String, Any>("atMs" to at, "gray" to gray)
            if (args["jpeg"] == true) result["jpeg"] = ByteArrayOutputStream().also { frame.compress(Bitmap.CompressFormat.JPEG, 65, it) }.toByteArray()
            if (args["ocr"] == true) {
                try {
                val text = Tasks.await(ocr.process(InputImage.fromBitmap(frame, 0)), 4, TimeUnit.SECONDS)
                result["text"] = text.text.take(2000)
                text.textBlocks.firstOrNull()?.boundingBox?.let { result["textY"] = it.top.toDouble() / frame.height }
                result["lines"] = text.textBlocks.flatMap { it.lines }.take(40).mapNotNull { line -> line.boundingBox?.let { mapOf("text" to line.text, "y" to it.top.toDouble() / frame.height) } }
                } catch (_: Exception) { result["ocrError"] = true }
            }
            if (args["audio"] == true) {
                try { result["pcm"] = audio(args, at, session) }
                catch (_: Exception) { result["audioError"] = true }
            }
            check(session)
            return result
        } finally { frame.recycle() }
    }
    @Suppress("UNCHECKED_CAST")
    private fun audio(args: Map<*, *>, at: Long, session: String): ByteArray {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            val url = args["url"] as String
            if (url.startsWith("file:")) extractor.setDataSource(java.net.URI(url).path)
            else extractor.setDataSource(url, args["headers"] as? Map<String, String> ?: emptyMap())
            val index = (0 until extractor.trackCount).firstOrNull { extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true } ?: return ByteArray(0)
            extractor.selectTrack(index)
            val format = extractor.getTrackFormat(index)
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder; decoder.configure(format, null, null, 0); decoder.start()
            extractor.seekTo(at * 1000, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val info = MediaCodec.BufferInfo()
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var eof = false
            val samples = ArrayList<Float>(15600)
            val started = SystemClock.elapsedRealtime()
            while (samples.size < 15600 && SystemClock.elapsedRealtime() - started < 4000) {
                check(session)
                if (!eof) {
                    val inputIndex = decoder.dequeueInputBuffer(1000)
                    if (inputIndex >= 0) {
                        val input = decoder.getInputBuffer(inputIndex)!!
                        val size = extractor.readSampleData(input, 0)
                        if (size < 0 || extractor.sampleTime > (at + 1200) * 1000) {
                            decoder.queueInputBuffer(inputIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); eof = true
                        } else {
                            decoder.queueInputBuffer(inputIndex, 0, size, extractor.sampleTime, 0); extractor.advance()
                        }
                    }
                }
                val outputIndex = decoder.dequeueOutputBuffer(info, 1000)
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val output = decoder.outputFormat
                    rate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE); channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    if (output.containsKey(MediaFormat.KEY_PCM_ENCODING)) encoding = output.getInteger(MediaFormat.KEY_PCM_ENCODING)
                } else if (outputIndex >= 0) {
                    val output = decoder.getOutputBuffer(outputIndex)!!.order(ByteOrder.LITTLE_ENDIAN)
                    output.position(info.offset); output.limit(info.offset + info.size)
                    val width = if (encoding == AudioFormat.ENCODING_PCM_FLOAT) 4 else 2
                    val frames = info.size / (width * channels)
                    for (frameIndex in 0 until frames) {
                        val timestamp = info.presentationTimeUs + frameIndex.toLong() * 1000000 / rate
                        val desired = ((timestamp - at * 1000) * 16000 / 1000000).toInt()
                        var value = 0f
                        for (channel in 0 until channels) value += if (width == 4) output.float else output.short / 32768f
                        if (timestamp >= at * 1000 && desired >= samples.size && desired < 15600) {
                            // Bounded linear-rate conversion to the 16 kHz mono contract.
                            while (samples.size <= desired && samples.size < 15600) samples.add(value / channels)
                        }
                    }
                    val finished = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    decoder.releaseOutputBuffer(outputIndex, false)
                    if (finished) break
                }
            }
            return ByteBuffer.allocate(samples.size * 4).order(ByteOrder.LITTLE_ENDIAN).also { out -> samples.forEach { out.putFloat(it) } }.array()
        } finally {
            try { codec?.stop() } catch (_: Exception) { }
            codec?.release(); extractor.release()
        }
    }
}
