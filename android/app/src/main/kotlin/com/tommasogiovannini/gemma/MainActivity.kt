package com.tommasogiovannini.gemma

import android.content.res.AssetManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.Executors

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.tommasogiovannini.gemma/assets"
    private val executor = Executors.newSingleThreadExecutor()

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