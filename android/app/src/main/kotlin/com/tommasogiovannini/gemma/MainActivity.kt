package com.tommasogiovannini.gemma

import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.tommasogiovannini.gemma/assets"
    private val MLC_CHANNEL = "com.tommasogiovannini.gemma/mlc"
    private val MLC_STREAM_CHANNEL = "com.tommasogiovannini.gemma/mlc_stream"
    private val executor = Executors.newSingleThreadExecutor()
    private var mlcEventSink: EventChannel.EventSink? = null
    private var mlcRuntimeReady: Boolean = false
    private var gemmaEngine: Engine? = null
    private var gemmaConversation: Conversation? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "copyAsset") {
                val assetName = call.argument<String>("assetName")
                val targetPath = call.argument<String>("targetPath")

                if (assetName != null && targetPath != null) {
                    // 백그라운드 스레드에서 복사 실행
                    executor.execute {
                        try {
                            val success = copyAssetFile(assetName, targetPath)
                            // UI 스레드에서 결과 반환
                            runOnUiThread {
                                if (success) {
                                    result.success(true)
                                } else {
                                    result.error("COPY_FAILED", "Failed to copy asset", null)
                                }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("ERROR", e.message, null)
                            }
                        }
                    }
                } else {
                    result.error("INVALID_ARGS", "Arguments missing", null)
                }
            } else {
                result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MLC_STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    mlcEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    mlcEventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MLC_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        val modelPath = call.argument<String>("modelPath")
                        val runtime = call.argument<String>("runtime") ?: "mlc"
                        val backendName = call.argument<String>("backend") ?: "cpu"
                        if (modelPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "modelPath is required", null)
                            return@setMethodCallHandler
                        }

                        if (runtime != "litert_lm") {
                            result.error(
                                "UNSUPPORTED_RUNTIME",
                                "Gemma 4 requires the LiteRT-LM Android runtime.",
                                runtime
                            )
                            return@setMethodCallHandler
                        }

                        val modelFile = File(modelPath)
                        if (!modelFile.isFile) {
                            result.error(
                                "MODEL_NOT_FOUND",
                                "Gemma 4 LiteRT-LM model file missing: $modelPath",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        executor.execute {
                            try {
                                closeGemmaRuntime()
                                val runtimeBackend = backendFromName(backendName)
                                val cacheDir = File(filesDir, "litertlm-cache").apply { mkdirs() }
                                val engine = Engine(
                                    EngineConfig(
                                        modelPath = modelPath,
                                        backend = runtimeBackend,
                                        visionBackend = runtimeBackend,
                                        cacheDir = cacheDir.absolutePath
                                    )
                                )
                                engine.initialize()
                                val conversation = engine.createConversation()
                                gemmaEngine = engine
                                gemmaConversation = conversation
                                mlcRuntimeReady = true
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                mlcRuntimeReady = false
                                runOnUiThread {
                                    result.error(
                                        "GEMMA_RUNTIME_INIT_FAILED",
                                        e.message ?: "Failed to initialize Gemma 4 LiteRT-LM runtime.",
                                        null
                                    )
                                }
                            }
                        }
                    }

                    "generate" -> {
                        val requestId = call.argument<String>("requestId")
                        val prompt = call.argument<String>("prompt")
                        val imagePath = call.argument<String>("imagePath")
                        if (requestId.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "requestId is required", null)
                            return@setMethodCallHandler
                        }
                        if (prompt.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "prompt is required", null)
                            return@setMethodCallHandler
                        }
                        if (!mlcRuntimeReady) {
                            result.error(
                                "GEMMA_RUNTIME_MISSING",
                                "Gemma 4 Android native runtime is not initialized.",
                                null
                            )
                            return@setMethodCallHandler
                        }

                        result.success(true)
                        executor.execute {
                            generateWithGemma(requestId, prompt, imagePath)
                        }
                    }

                    "reset" -> {
                        executor.execute {
                            try {
                                gemmaConversation = gemmaEngine?.createConversation()
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error(
                                        "GEMMA_RESET_FAILED",
                                        e.message ?: "Failed to reset Gemma conversation.",
                                        null
                                    )
                                }
                            }
                        }
                    }
                    "dispose" -> {
                        executor.execute {
                            closeGemmaRuntime()
                            runOnUiThread { result.success(true) }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun generateWithGemma(requestId: String, prompt: String, imagePath: String?) {
        val conversation = gemmaConversation
        if (conversation == null) {
            emitMlcError(requestId, "Gemma 4 conversation is not initialized.")
            return
        }

        try {
            val response = if (imagePath.isNullOrBlank()) {
                conversation.sendMessage(prompt)
            } else {
                val imageFile = File(imagePath)
                if (!imageFile.isFile) {
                    emitMlcError(requestId, "Image file missing: $imagePath")
                    return
                }
                val content = Contents.of(
                    Content.ImageFile(imageFile.canonicalPath),
                    Content.Text(prompt)
                )
                conversation.sendMessage(content)
            }

            emitMlcTokenDelta(requestId, messageToText(response))
            emitMlcDone(requestId)
        } catch (t: Throwable) {
            emitMlcError(requestId, t.message ?: "Gemma 4 generation failed.")
        }
    }

    private fun messageToText(message: Message): String {
        return message.contents.contents
            .filterIsInstance<Content.Text>()
            .joinToString(separator = "") { it.text }
    }

    private fun emitMlcTokenDelta(requestId: String, text: String?) {
        if (text.isNullOrEmpty()) {
            return
        }
        runOnUiThread {
            mlcEventSink?.success(
                mapOf(
                    "requestId" to requestId,
                    "token" to text
                )
            )
        }
    }

    private fun emitMlcDone(requestId: String) {
        runOnUiThread {
            mlcEventSink?.success(
                mapOf(
                    "requestId" to requestId,
                    "done" to true
                )
            )
        }
    }

    private fun emitMlcError(requestId: String, message: String) {
        runOnUiThread {
            mlcEventSink?.success(
                mapOf(
                    "requestId" to requestId,
                    "error" to message,
                    "done" to true
                )
            )
        }
    }

    private fun backendFromName(name: String): Backend {
        return when (name.lowercase()) {
            "gpu" -> Backend.GPU()
            else -> Backend.CPU()
        }
    }

    private fun closeGemmaRuntime() {
        try {
            gemmaConversation?.close()
        } catch (_: Exception) {
        }
        try {
            gemmaEngine?.close()
        } catch (_: Exception) {
        }
        gemmaConversation = null
        gemmaEngine = null
        mlcRuntimeReady = false
    }

    private fun copyAssetFile(assetName: String, targetPath: String): Boolean {
        var inputStream: InputStream? = null
        var outputStream: OutputStream? = null

        return try {
            // Flutter asset은 'flutter_assets/' 하위에 위치함
            // rootBundle로 등록된 asset은 'flutter_assets/assets/models/...' 경로를 가짐
            val fullAssetName = "flutter_assets/$assetName"

            inputStream = assets.open(fullAssetName)
            val outFile = File(targetPath)

            // 상위 디렉토리 생성
            outFile.parentFile?.mkdirs()

            outputStream = FileOutputStream(outFile)

            val buffer = ByteArray(1024 * 1024) // 1MB 버퍼
            var length: Int
            while (inputStream.read(buffer).also { length = it } > 0) {
                outputStream.write(buffer, 0, length)
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            // 경로 문제일 수 있으므로 접두사 없이 시도 (예비책)
            try {
                if (inputStream == null) {
                    inputStream = assets.open(assetName)
                    val outFile = File(targetPath)
                    outputStream = FileOutputStream(outFile)
                    val buffer = ByteArray(1024 * 1024)
                    var length: Int
                    while (inputStream.read(buffer).also { length = it } > 0) {
                        outputStream!!.write(buffer, 0, length)
                    }
                    return true
                }
                false
            } catch (e2: Exception) {
                e2.printStackTrace()
                false
            }
        } finally {
            inputStream?.close()
            outputStream?.flush()
            outputStream?.close()
        }
    }
}
