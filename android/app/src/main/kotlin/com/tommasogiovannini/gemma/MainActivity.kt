package com.tommasogiovannini.gemma

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.tommasogiovannini.gemma/assets"
    private val MLC_CHANNEL = "com.tommasogiovannini.gemma/mlc"
    private val MLC_STREAM_CHANNEL = "com.tommasogiovannini.gemma/mlc_stream"
    private val LOCATION_CHANNEL = "com.tommasogiovannini.gemma/location"
    private val executor = Executors.newSingleThreadExecutor()
    private var mlcEventSink: EventChannel.EventSink? = null
    private var mlcRuntimeReady: Boolean = false
    private var gemmaEngine: Engine? = null
    private var gemmaConversation: Conversation? = null
    private var pendingLocationResult: MethodChannel.Result? = null

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LOCATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentLocation" -> getCurrentLocation(result)
                    else -> result.notImplemented()
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

                    "generateTemporary" -> {
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
                            generateWithTemporaryConversation(requestId, prompt, imagePath)
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
            if (imagePath.isNullOrBlank()) {
                streamGemmaResponse(requestId, start = { callback ->
                    conversation.sendMessageAsync(prompt, callback)
                })
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
                streamGemmaResponse(requestId, start = { callback ->
                    conversation.sendMessageAsync(content, callback)
                })
            }
        } catch (t: Throwable) {
            emitMlcError(requestId, t.message ?: "Gemma 4 generation failed.")
        }
    }

    private fun generateWithTemporaryConversation(requestId: String, prompt: String, imagePath: String?) {
        val engine = gemmaEngine
        if (engine == null) {
            emitMlcError(requestId, "Gemma 4 engine is not initialized.")
            return
        }

        var conversation: Conversation? = null
        try {
            val activeConversation = engine.createConversation()
            conversation = activeConversation
            if (imagePath.isNullOrBlank()) {
                streamGemmaResponse(
                    requestId,
                    start = { callback -> activeConversation.sendMessageAsync(prompt, callback) },
                    onFinished = { closeConversation(activeConversation) }
                )
            } else {
                val imageFile = File(imagePath)
                if (!imageFile.isFile) {
                    emitMlcError(requestId, "Image file missing: $imagePath")
                    closeConversation(activeConversation)
                    return
                }
                val content = Contents.of(
                    Content.ImageFile(imageFile.canonicalPath),
                    Content.Text(prompt)
                )
                streamGemmaResponse(
                    requestId,
                    start = { callback -> activeConversation.sendMessageAsync(content, callback) },
                    onFinished = { closeConversation(activeConversation) }
                )
            }
        } catch (t: Throwable) {
            conversation?.let { closeConversation(it) }
            emitMlcError(requestId, t.message ?: "Gemma 4 temporary generation failed.")
        }
    }

    private fun streamGemmaResponse(
        requestId: String,
        start: (MessageCallback) -> Unit,
        onFinished: (() -> Unit)? = null
    ) {
        val completed = AtomicBoolean(false)
        val textLock = Any()
        var accumulatedText = ""

        fun finish(emitTerminalEvent: () -> Unit) {
            if (completed.compareAndSet(false, true)) {
                try {
                    emitTerminalEvent()
                } finally {
                    onFinished?.invoke()
                }
            }
        }

        val callback = object : MessageCallback {
            override fun onMessage(message: Message) {
                val text = messageToText(message)
                if (text.isEmpty()) {
                    return
                }

                val delta = synchronized(textLock) {
                    val nextDelta = if (text.startsWith(accumulatedText)) {
                        text.substring(accumulatedText.length)
                    } else {
                        text
                    }

                    accumulatedText = if (text.startsWith(accumulatedText)) {
                        text
                    } else {
                        accumulatedText + text
                    }
                    nextDelta
                }

                if (delta.isNotEmpty()) {
                    emitMlcTokenDelta(requestId, delta)
                }
            }

            override fun onDone() {
                finish { emitMlcDone(requestId) }
            }

            override fun onError(t: Throwable) {
                finish {
                    emitMlcError(requestId, t.message ?: "Gemma 4 generation failed.")
                }
            }
        }

        start(callback)
    }

    private fun getCurrentLocation(result: MethodChannel.Result) {
        if (!hasLocationPermission()) {
            result.error("LOCATION_PERMISSION_MISSING", "Location permission is not granted.", null)
            return
        }

        val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER
        ).filter { provider ->
            try {
                locationManager.isProviderEnabled(provider)
            } catch (_: Exception) {
                false
            }
        }

        if (providers.isEmpty()) {
            result.error("LOCATION_PROVIDER_DISABLED", "No location provider is enabled.", null)
            return
        }

        val lastKnown = providers
            .mapNotNull { provider ->
                try {
                    locationManager.getLastKnownLocation(provider)
                } catch (_: SecurityException) {
                    null
                }
            }
            .maxByOrNull { it.time }

        if (lastKnown != null && System.currentTimeMillis() - lastKnown.time < 10 * 60 * 1000) {
            result.success(locationToMap(lastKnown))
            return
        }

        if (pendingLocationResult != null) {
            result.error("LOCATION_REQUEST_ACTIVE", "A location request is already active.", null)
            return
        }

        pendingLocationResult = result
        val provider = providers.first()
        val handler = Handler(Looper.getMainLooper())
        var listener: LocationListener? = null

        listener = object : LocationListener {
            override fun onLocationChanged(location: Location) {
                completeLocation(locationManager, listener, locationToMap(location), null)
            }

            override fun onProviderDisabled(provider: String) {
                completeLocation(
                    locationManager,
                    listener,
                    null,
                    "Location provider was disabled before a location was received."
                )
            }

            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {
            }
        }

        handler.postDelayed({
            val fallback = providers
                .mapNotNull { activeProvider ->
                    try {
                        locationManager.getLastKnownLocation(activeProvider)
                    } catch (_: SecurityException) {
                        null
                    }
                }
                .maxByOrNull { it.time }

            completeLocation(
                locationManager,
                listener,
                fallback?.let { locationToMap(it) },
                if (fallback == null) "Timed out while waiting for current location." else null
            )
        }, 15_000)

        try {
            locationManager.requestSingleUpdate(provider, listener, Looper.getMainLooper())
        } catch (e: SecurityException) {
            completeLocation(locationManager, listener, null, e.message ?: "Location permission denied.")
        }
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun completeLocation(
        locationManager: LocationManager,
        listener: LocationListener?,
        value: Map<String, Any?>?,
        error: String?
    ) {
        if (listener != null) {
            try {
                locationManager.removeUpdates(listener)
            } catch (_: Exception) {
            }
        }

        val result = pendingLocationResult ?: return
        pendingLocationResult = null
        runOnUiThread {
            if (value != null) {
                result.success(value)
            } else {
                result.error("LOCATION_UNAVAILABLE", error ?: "Location unavailable.", null)
            }
        }
    }

    private fun locationToMap(location: Location): Map<String, Any?> {
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
            "provider" to location.provider
        )
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

    private fun closeConversation(conversation: Conversation) {
        try {
            conversation.close()
        } catch (_: Exception) {
        }
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
