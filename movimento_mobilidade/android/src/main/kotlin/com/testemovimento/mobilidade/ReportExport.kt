package com.testemovimento.mobilidade

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

internal class ReportExport : MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener {
    private companion object {
        const val CREATE_PDF = 42731
    }

    private var binding: ActivityPluginBinding? = null
    private data class Pending(val bytes: ByteArray, val result: MethodChannel.Result)
    private var pending: Pending? = null

    fun attach(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    fun detach(cancel: Boolean) {
        binding?.removeActivityResultListener(this)
        binding = null
        if (cancel) {
            pending?.result?.success(false)
            pending = null
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "salvarPdf") {
            result.notImplemented()
            return
        }
        val activity = binding?.activity
        val bytes = call.argument<ByteArray>("bytes")
        if (activity == null || pending != null || bytes == null) {
            result.error("UNAVAILABLE", "Exportação indisponível.", null)
            return
        }
        pending = Pending(bytes, result)
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/pdf"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("nome"))
        }
        try {
            activity.startActivityForResult(intent, CREATE_PDF)
        } catch (e: Exception) {
            pending = null
            result.error("CREATE_PDF", e.localizedMessage, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE_PDF) return false
        val export = pending ?: return false
        pending = null
        val uri = data?.data
        val resolver = binding?.activity?.contentResolver
        if (resultCode != Activity.RESULT_OK) {
            export.result.success(false)
        } else if (uri == null || resolver == null) {
            export.result.error("WRITE_PDF", "Destino indisponível.", null)
        } else {
            val main = Handler(Looper.getMainLooper())
            Thread {
                try {
                    requireNotNull(resolver.openOutputStream(uri, "wt")).use { it.write(export.bytes) }
                    main.post { export.result.success(true) }
                } catch (e: Exception) {
                    main.post { export.result.error("WRITE_PDF", e.localizedMessage, null) }
                }
            }.start()
        }
        return true
    }
}
