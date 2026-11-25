package com.testemovimento.mobilidade

import android.content.Context
import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Pose via MediaPipe Pose Landmarker (BlazePose) com delegate de GPU.
 * Recebe quadros do Dart, devolve 33 landmarks normalizados (x, y, z, visibilidade)
 * já na orientação "em pé" da imagem (a rotação é aplicada aqui).
 *
 * Os modelos pose_landmarker_{lite,full}.task vêm nos assets desta biblioteca.
 */
class MovimentoMobilidadePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var landmarker: PoseLandmarker? = null
    private var bitmap: Bitmap? = null
    private var pixels: IntArray? = null
    private var lastTs = 0L

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "movimento/pose").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor.execute {
            landmarker?.close()
            landmarker = null
        }
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val model = call.argument<String>("model") ?: "full"
                executor.execute {
                    try {
                        val delegate = initLandmarker(model)
                        main.post { result.success(delegate) }
                    } catch (e: Throwable) {
                        Log.e("PoseNative", "init falhou", e)
                        main.post { result.error("INIT", e.toString(), null) }
                    }
                }
            }
            "detect" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val w = call.argument<Int>("width") ?: 0
                val h = call.argument<Int>("height") ?: 0
                val rot = call.argument<Int>("rotation") ?: 0
                if (bytes == null || landmarker == null) {
                    result.success(DoubleArray(0))
                    return
                }
                executor.execute {
                    try {
                        val out = detect(bytes, w, h, rot)
                        main.post { result.success(out) }
                    } catch (e: Throwable) {
                        Log.e("PoseNative", "detect falhou", e)
                        main.post { result.error("DETECT", e.toString(), null) }
                    }
                }
            }
            "detectYuv" -> {
                val y = call.argument<ByteArray>("y")
                val u = call.argument<ByteArray>("u")
                val v = call.argument<ByteArray>("v")
                val w = call.argument<Int>("width") ?: 0
                val h = call.argument<Int>("height") ?: 0
                val rot = call.argument<Int>("rotation") ?: 0
                val yStride = call.argument<Int>("yStride") ?: w
                val uvStride = call.argument<Int>("uvStride") ?: w
                val uvPixel = call.argument<Int>("uvPixelStride") ?: 1
                if (y == null || u == null || v == null || landmarker == null) {
                    result.success(DoubleArray(0))
                    return
                }
                executor.execute {
                    try {
                        val out = detectYuv(y, u, v, w, h, yStride, uvStride, uvPixel, rot)
                        main.post { result.success(out) }
                    } catch (e: Throwable) {
                        Log.e("PoseNative", "detectYuv falhou", e)
                        main.post { result.error("DETECT", e.toString(), null) }
                    }
                }
            }
            "dispose" -> {
                executor.execute {
                    landmarker?.close()
                    landmarker = null
                    main.post { result.success(null) }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun build(model: String, delegate: Delegate): PoseLandmarker {
        val ctx = context ?: throw IllegalStateException("Plugin não anexado ao engine")
        val base = BaseOptions.builder()
            .setModelAssetPath("pose_landmarker_$model.task")
            .setDelegate(delegate)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(RunningMode.VIDEO)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.5f)
            .setMinPosePresenceConfidence(0.5f)
            .setMinTrackingConfidence(0.5f)
            .build()
        return PoseLandmarker.createFromOptions(ctx, options)
    }

    private fun initLandmarker(model: String): String {
        landmarker?.close()
        landmarker = null
        return try {
            landmarker = build(model, Delegate.GPU)
            "GPU"
        } catch (e: Throwable) {
            Log.w("PoseNative", "GPU indisponível, usando CPU", e)
            landmarker = build(model, Delegate.CPU)
            "CPU"
        }
    }

    private fun detect(nv21: ByteArray, w: Int, h: Int, rotation: Int): DoubleArray {
        val px = prepare(w, h)
        nv21ToArgb(nv21, w, h, px)
        return run(w, h, rotation)
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

    private fun detectYuv(
        y: ByteArray, u: ByteArray, v: ByteArray, w: Int, h: Int,
        yStride: Int, uvStride: Int, uvPixel: Int, rotation: Int
    ): DoubleArray {
        val px = prepare(w, h)
        yuv420ToArgb(y, u, v, w, h, yStride, uvStride, uvPixel, px)
        return run(w, h, rotation)
    }

    private var sw = 0
    private var sh = 0
    private var rotated: IntArray? = null

    /** Buffer de saída em meia resolução (o modelo usa entrada de ~256 px). */
    private fun prepare(w: Int, h: Int): IntArray {
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

    private fun run(w: Int, h: Int, rotation: Int): DoubleArray {
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
        bmp!!.setPixels(rotated!!, 0, dw, 0, 0, dw, dh)

        var ts = SystemClock.uptimeMillis()
        if (ts <= lastTs) ts = lastTs + 1
        lastTs = ts

        val res = lm.detectForVideo(BitmapImageBuilder(bmp).build(), ts)
        val poses = res.landmarks()
        if (poses.isEmpty()) return DoubleArray(0)
        val pts = poses[0]
        val out = DoubleArray(pts.size * 4)
        for (i in pts.indices) {
            val p = pts[i]
            out[i * 4] = p.x().toDouble()
            out[i * 4 + 1] = p.y().toDouble()
            out[i * 4 + 2] = p.z().toDouble()
            out[i * 4 + 3] = p.visibility().orElse(0.5f).toDouble()
        }
        return out
    }

    private fun clamp(v: Int) = if (v < 0) 0 else if (v > 262143) 262143 else v

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
