package com.itsash.tidy

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

/**
 * Native side of Tidy (Dart side: lib/media/media_platform.dart).
 *
 * MethodChannel "com.itsash.tidy/media":
 *   - deviceInfo() -> {sdk, access: full|partial|none, freeBytes, totalBytes}
 *   - startScan({force}) -> [media map]; progress goes to the EventChannel; force ignores the cache
 *   - cancelScan()
 *   - thumbnail({id, video, size}) -> JPEG bytes (null when it cannot be decoded)
 *   - delete({items: [{id, video}], trash}) -> {deleted: [keys], cancelled}
 *   - open({id, video}): view in the gallery app
 * EventChannel "com.itsash.tidy/progress": {phase, done, total}
 */
class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())
    private val scanExecutor = Executors.newSingleThreadExecutor()
    private val thumbExecutor = Executors.newFixedThreadPool(3)
    private val cache by lazy { AnalysisCache(applicationContext) }
    private val deleter by lazy { DeleteCoordinator(this) }
    private var scanner: Scanner? = null
    private var events: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.itsash.tidy/media").setMethodCallHandler(::onCall)
        EventChannel(messenger, "com.itsash.tidy/progress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceInfo" -> result.success(deviceInfo())
            "startScan" -> startScan(call.argument<Boolean>("force") == true, result)
            "cancelScan" -> { scanner?.cancel(); result.success(null) }
            "thumbnail" -> thumbnail(call, result)
            "delete" -> {
                val items = call.argument<List<Map<String, Any>>>("items").orEmpty().map {
                    MediaRef((it["id"] as Number).toLong(), it["video"] == true)
                }
                deleter.delete(items, call.argument<Boolean>("trash") == true, result)
            }
            "open" -> openMedia(call, result)
            else -> result.notImplemented()
        }
    }

    private fun deviceInfo(): Map<String, Any> {
        val stat = StatFs(Environment.getExternalStorageDirectory().path)
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT,
            "access" to accessLevel(),
            "freeBytes" to stat.availableBytes,
            "totalBytes" to stat.totalBytes,
        )
    }

    private fun granted(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    /** `full` = all photos and videos; `partial` = Android 14 "selected photos" or only one kind. */
    private fun accessLevel(): String = when {
        Build.VERSION.SDK_INT >= 33 -> when {
            granted(Manifest.permission.READ_MEDIA_IMAGES) && granted(Manifest.permission.READ_MEDIA_VIDEO) -> "full"
            granted(Manifest.permission.READ_MEDIA_IMAGES) || granted(Manifest.permission.READ_MEDIA_VIDEO) -> "partial"
            Build.VERSION.SDK_INT >= 34 && granted("android.permission.READ_MEDIA_VISUAL_USER_SELECTED") -> "partial"
            else -> "none"
        }
        granted(Manifest.permission.READ_EXTERNAL_STORAGE) -> "full"
        else -> "none"
    }

    private fun startScan(force: Boolean, result: MethodChannel.Result) {
        if (scanner != null) return result.error("busy", "A scan is already running.", null)
        val s = Scanner(applicationContext, cache) { p ->
            main.post { events?.success(mapOf("phase" to p.phase, "done" to p.done, "total" to p.total)) }
        }
        scanner = s
        scanExecutor.execute {
            try {
                val rows = s.run(force)
                main.post { scanner = null; result.success(rows) }
            } catch (_: CancellationException) {
                main.post { scanner = null; result.error("cancelled", "Scan cancelled.", null) }
            } catch (e: Exception) {
                main.post { scanner = null; result.error("scan_failed", e.message, null) }
            }
        }
    }

    private fun thumbnail(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toLong() ?: return result.error("args", "id", null)
        val video = call.argument<Boolean>("video") == true
        val size = call.argument<Int>("size") ?: 256
        thumbExecutor.execute {
            val bytes = try {
                Thumbnails.load(applicationContext, id, video, size)?.let { bmp ->
                    ByteArrayOutputStream().also { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }.toByteArray()
                }
            } catch (_: Throwable) {
                null
            }
            main.post { result.success(bytes) }
        }
    }

    private fun openMedia(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toLong() ?: return result.error("args", "id", null)
        val video = call.argument<Boolean>("video") == true
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(MediaRow.uriFor(id, video), if (video) "video/*" else "image/*")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: Exception) {
            result.success(false)
        }
    }

    @Deprecated("Needed for the MediaStore delete confirmation dialogs.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (!deleter.onActivityResult(requestCode, resultCode)) super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        scanner?.cancel()
        super.onDestroy()
    }
}
