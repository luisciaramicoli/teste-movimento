package com.testemovimento.mobilidade

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Pose via MediaPipe Pose Landmarker (BlazePose) com delegate de GPU (ou CPU em
 * emuladores / dispositivos sem suporte).
 *
 * Recebe quadros do Dart e devolve 33 landmarks normalizados (x, y, z, visibilidade)
 * já na orientação "em pé" da imagem (a rotação é aplicada aqui).
 *
 * Os modelos `pose_landmarker_{lite,full}.task` vêm nos assets desta biblioteca.
 */
class MovimentoMobilidadePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private val report = ReportExport()
    private var reportChannel: MethodChannel? = null

    override fun onAttachedToActivity(binding: ActivityPluginBinding) = report.attach(binding)
    override fun onDetachedFromActivity() = report.detach(true)
    override fun onDetachedFromActivityForConfigChanges() = report.detach(false)
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = report.attach(binding)

    private companion object {
        const val CHANNEL_NAME = "movimento/pose"
        const val TAG = "PoseNative"
        const val DEFAULT_MODEL = "full"
        const val MIN_CONFIDENCE = 0.5f
        const val VALUES_PER_LANDMARK = 4
        const val MAX_YUV_CLAMP = 262143
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var landmarker: PoseLandmarker? = null
    private var loadedModel: String? = null
    private var loadedDelegate: String = ""

    private var bitmap: Bitmap? = null
    private var pixels: IntArray? = null
    private var rotated: IntArray? = null
    private var sw = 0
    private var sh = 0
    private var lastTs = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        reportChannel = MethodChannel(binding.binaryMessenger, "movimento/relatorio").also {
            it.setMethodCallHandler(report)
        }
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        reportChannel?.setMethodCallHandler(null)
        reportChannel = null
        channel?.setMethodCallHandler(null)
        channel = null
        executor.execute {
            closeLandmarker()
        }
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> handleInit(call, result)
            "detect" -> handleDetect(call, result)
            "detectYuv" -> handleDetectYuv(call, result)
            "dispose" -> handleDispose(result)
            else -> result.notImplemented()
        }
    }

    private fun handleInit(call: MethodCall, result: MethodChannel.Result) {
        val model = call.argument<String>("model") ?: DEFAULT_MODEL
        executor.execute {
            try {
                val delegate = initLandmarker(model)
                main.post { result.success(delegate) }
            } catch (e: Throwable) {
                Log.e(TAG, "init falhou", e)
                main.post { result.error("INIT", e.toString(), null) }
            }
        }
    }

    private fun handleDetect(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val w = call.argument<Int>("width") ?: 0
        val h = call.argument<Int>("height") ?: 0
        val rot = call.argument<Int>("rotation") ?: 0
        if (bytes == null || landmarker == null || w <= 0 || h <= 0) {
            result.success(DoubleArray(0))
            return
        }
        executor.execute {
            try {
                val out = detect(bytes, w, h, rot)
                main.post { result.success(out) }
            } catch (e: Throwable) {
                Log.e(TAG, "detect falhou", e)
                main.post { result.error("DETECT", e.toString(), null) }
            }
        }
    }

    private fun handleDetectYuv(call: MethodCall, result: MethodChannel.Result) {
        val y = call.argument<ByteArray>("y")
        val u = call.argument<ByteArray>("u")
        val v = call.argument<ByteArray>("v")
        val w = call.argument<Int>("width") ?: 0
        val h = call.argument<Int>("height") ?: 0
        val rot = call.argument<Int>("rotation") ?: 0
        val yStride = call.argument<Int>("yStride") ?: w
        val uvStride = call.argument<Int>("uvStride") ?: w
        val uvPixel = call.argument<Int>("uvPixelStride") ?: 1
        if (y == null || u == null || v == null || landmarker == null || w <= 0 || h <= 0) {
            result.success(DoubleArray(0))
            return
        }
        executor.execute {
            try {
                val out = detectYuv(y, u, v, w, h, yStride, uvStride, uvPixel, rot)
                main.post { result.success(out) }
            } catch (e: Throwable) {
                Log.e(TAG, "detectYuv falhou", e)
                main.post { result.error("DETECT", e.toString(), null) }
            }
        }
    }

    private fun handleDispose(result: MethodChannel.Result) {
        executor.execute {
            closeLandmarker()
            main.post { result.success(null) }
        }
    }

    private fun closeLandmarker() {
        landmarker?.close()
        landmarker = null
        loadedModel = null
        loadedDelegate = ""
    }

    private fun isEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT.lowercase()
        val model = Build.MODEL.lowercase()
        val manufacturer = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        val device = Build.DEVICE.lowercase()
        val product = Build.PRODUCT.lowercase()
        val hardware = Build.HARDWARE.lowercase()

        return fingerprint.startsWith("generic") ||
            fingerprint.startsWith("unknown") ||
            fingerprint.contains("emulator") ||
            fingerprint.contains("sdk_gphone") ||
            model.contains("google_sdk") ||
            model.contains("emulator") ||
            model.contains("android sdk built for x86") ||
            model.contains("sdk_gphone") ||
            manufacturer.contains("genymotion") ||
            (brand.startsWith("generic") && device.startsWith("generic")) ||
            product.contains("sdk") ||
            product.contains("emulator") ||
            product.contains("simulator") ||
            product.contains("vbox86p") ||
            hardware.contains("goldfish") ||
            hardware.contains("ranchu")
    }

    private fun buildLandmarker(model: String, delegate: Delegate): PoseLandmarker {
        val ctx = context ?: throw IllegalStateException("Plugin não anexado ao engine")
        val base = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_$model.task")
            .setDelegate(delegate)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(MIN_CONFIDENCE)
            .setMinPosePresenceConfidence(MIN_CONFIDENCE)
            .setMinTrackingConfidence(MIN_CONFIDENCE)
            .build()
        return PoseLandmarker.createFromOptions(ctx, options)
    }

    private fun initLandmarker(model: String): String {
        if (landmarker != null && loadedModel == model) {
            return loadedDelegate
        }
        closeLandmarker()

        val delegateName = if (isEmulator()) {
            Log.i(TAG, "Emulador detectado, usando CPU diretamente")
            landmarker = buildLandmarker(model, Delegate.CPU)
            "CPU"
        } else {
            try {
                landmarker = buildLandmarker(model, Delegate.GPU)
                "GPU"
            } catch (e: Throwable) {
                Log.w(TAG, "GPU indisponível, usando CPU", e)
                landmarker = buildLandmarker(model, Delegate.CPU)
                "CPU"
            }
        }
        loadedModel = model
        loadedDelegate = delegateName
        return delegateName
    }

    private fun detect(nv21: ByteArray, w: Int, h: Int, rotation: Int): DoubleArray {
        val px = prepareBuffers(w, h)
        nv21ToArgb(nv21, w, h, px)
        return runInference(rotation)
    }

    private fun detectYuv(
        y: ByteArray, u: ByteArray, v: ByteArray, w: Int, h: Int,
        yStride: Int, uvStride: Int, uvPixel: Int, rotation: Int
    ): DoubleArray {
        val px = prepareBuffers(w, h)
        yuv420ToArgb(y, u, v, w, h, yStride, uvStride, uvPixel, px)
        return runInference(rotation)
    }

    /** Rotaciona [src] (sw x sh) no sentido horário por [rot] graus para [dst]. */
    private fun rotate(src: IntArray, sw: Int, sh: Int, rot: Int, dst: IntArray) {
        when (rot) {
            90 -> for (j in 0 until sh) for (i in 0 until sw) dst[i * sh + (sh - 1 - j)] = src[j * sw + i]
            180 -> for (k in 0 until sw * sh) dst[sw * sh - 1 - k] = src[k]
            270 -> for (j in 0 until sh) for (i in 0 until sw) dst[(sw - 1 - i) * sh + j] = src[j * sw + i]
            else -> System.arraycopy(src, 0, dst, 0, sw * sh)
        }
    }

    /** Buffer de saída em meia resolução (o modelo usa entrada de ~256 px). */
    private fun prepareBuffers(w: Int, h: Int): IntArray {
        val nw = w / 2
        val nh = h / 2
        if (pixels == null || sw != nw || sh != nh) {
            sw = nw
            sh = nh
            pixels = IntArray(nw * nh)
            rotated = IntArray(nw * nh)
            bitmap = null
        }
        return pixels!!
    }

    private fun runInference(rotation: Int): DoubleArray {
        val lm = landmarker ?: return DoubleArray(0)
        val rot = ((rotation % 360) + 360) % 360
        val dw = if (rot == 90 || rot == 270) sh else sw
        val dh = if (rot == 90 || rot == 270) sw else sh
        rotate(pixels!!, sw, sh, rot, rotated!!)

        var bmp = bitmap
        if (bmp == null || bmp.width != dw || bmp.height != dh) {
            bmp = Bitmap.createBitmap(dw, dh, Bitmap.Config.ARGB_8888)
            bitmap = bmp
        }
        bmp.setPixels(rotated!!, 0, dw, 0, 0, dw, dh)

        var ts = SystemClock.uptimeMillis()
        if (ts <= lastTs) ts = lastTs + 1
        lastTs = ts

        val res = lm.detectForVideo(BitmapImageBuilder(bmp).build(), ts)
        val poses = res.landmarks()
        if (poses.isEmpty()) return DoubleArray(0)

        val pts = poses[0]
        val out = DoubleArray(pts.size * VALUES_PER_LANDMARK)
        for (i in pts.indices) {
            val p = pts[i]
            val base = i * VALUES_PER_LANDMARK
            out[base] = p.x().toDouble()
            out[base + 1] = p.y().toDouble()
            out[base + 2] = p.z().toDouble()
            out[base + 3] = p.visibility().orElse(0.5f).toDouble()
        }
        return out
    }

    private fun clamp(v: Int) = if (v < 0) 0 else if (v > MAX_YUV_CLAMP) MAX_YUV_CLAMP else v

    private fun pack(yy: Int, u: Int, v: Int): Int {
        val y1192 = 1192 * (if (yy < 0) 0 else yy)
        val r = clamp(y1192 + 1634 * v)
        val g = clamp(y1192 - 833 * v - 400 * u)
        val b = clamp(y1192 + 2066 * u)
        return -0x1000000 or ((r shl 6) and 0xff0000) or ((g shr 2) and 0xff00) or ((b shr 10) and 0xff)
    }

    /** YUV_420_888 (3 planos) -> ARGB em meia resolução (amostra 1 de cada 2 pixels). */
    private fun yuv420ToArgb(
        yp: ByteArray, up: ByteArray, vp: ByteArray, w: Int, h: Int,
        yStride: Int, uvStride: Int, uvPixel: Int, out: IntArray
    ) {
        val nw = w / 2
        val nh = h / 2
        var o = 0
        for (j in 0 until nh) {
            val yRow = (j * 2) * yStride
            val uvRow = j * uvStride
            for (i in 0 until nw) {
                val yy = (yp[yRow + i * 2].toInt() and 0xff) - 16
                val uvi = uvRow + i * uvPixel
                val u = (up[if (uvi < up.size) uvi else up.size - 1].toInt() and 0xff) - 128
                val v = (vp[if (uvi < vp.size) uvi else vp.size - 1].toInt() and 0xff) - 128
                out[o++] = pack(yy, u, v)
            }
        }
    }

    /** NV21 (1 plano) -> ARGB em meia resolução. */
    private fun nv21ToArgb(nv21: ByteArray, w: Int, h: Int, out: IntArray) {
        val frame = w * h
        val nw = w / 2
        val nh = h / 2
        var o = 0
        for (j in 0 until nh) {
            val yRow = (j * 2) * w
            val uvRow = frame + j * w
            for (i in 0 until nw) {
                val yy = (nv21[yRow + i * 2].toInt() and 0xff) - 16
                val uvi = uvRow + i * 2
                val v = (nv21[uvi].toInt() and 0xff) - 128
                val u = (nv21[uvi + 1].toInt() and 0xff) - 128
                out[o++] = pack(yy, u, v)
            }
        }
    }
}
