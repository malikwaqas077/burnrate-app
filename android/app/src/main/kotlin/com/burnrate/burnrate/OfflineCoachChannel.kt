package com.burnrate.burnrate

import android.app.ActivityManager
import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class OfflineCoachChannel(
    private val context: Context,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.burnrate.burnrate/offline_coach"

        private const val PREFS = "offline_coach"
        private const val KEY_DOWNLOAD_ID = "download_id"
        private const val KEY_MODEL_VERSION = "model_version"
        private const val MODEL_VERSION = "gemma4-e2b-it-2026-04"
        private const val MODEL_VARIANT = "Gemma 4 E2B"
        private const val MODEL_FILE_NAME = "gemma-4-E2B-it.litertlm"
        private const val MODEL_SIZE_BYTES = 2583L * 1024L * 1024L
        private const val MIN_ANDROID_SDK = 29
        private const val MIN_RAM_MB = 6144
        private const val RECOMMENDED_RAM_MB = 8192
        private const val MIN_STORAGE_MB = 4096
    }

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val downloadManager =
        context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var activeBackend = "cpu"

    @Volatile
    private var initializedModelPath: String? = null

    @Volatile
    private var isInitializing = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformCapabilities" -> result.success(getPlatformCapabilities())
            "getModelStatus" -> result.success(getModelStatus())
            "getDownloadStatus" -> result.success(getDownloadStatus())
            "downloadModel" -> {
                val url = call.argument<String>("url")
                val version = call.argument<String>("version") ?: MODEL_VERSION
                val wifiOnly = call.argument<Boolean>("wifiOnly") ?: true
                if (url.isNullOrBlank()) {
                    result.error("invalid_url", "Model download URL is required.", null)
                } else {
                    result.success(startDownload(url, version, wifiOnly))
                }
            }

            "cancelDownload" -> result.success(cancelDownload())
            "deleteModel" -> result.success(deleteModel())
            "initializeModel" -> {
                val preferGpu = call.argument<Boolean>("preferGpu") ?: false
                initializeModel(preferGpu, result)
            }

            "disposeModel" -> {
                executor.execute {
                    disposeEngineInternal()
                    postSuccess(result, null)
                }
            }

            "generateResponse" -> {
                val systemPrompt = call.argument<String>("systemPrompt") ?: ""
                val userPrompt = call.argument<String>("userPrompt") ?: ""
                if (userPrompt.isBlank()) {
                    result.error("invalid_prompt", "A user prompt is required.", null)
                } else {
                    generateResponse(systemPrompt, userPrompt, result)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun getPlatformCapabilities(): Map<String, Any> {
        val totalRamMb = getTotalRamMb()
        val availableStorageMb = getAvailableStorageMb()
        val reasons = mutableListOf<String>()

        if (Build.VERSION.SDK_INT < MIN_ANDROID_SDK) {
            reasons += "Android ${Build.VERSION.SDK_INT} is below the supported minimum of $MIN_ANDROID_SDK."
        }
        if (totalRamMb < MIN_RAM_MB) {
            reasons += "Device RAM (${totalRamMb}MB) is below the offline advisor minimum of ${MIN_RAM_MB}MB."
        }
        if (availableStorageMb < MIN_STORAGE_MB) {
            reasons += "Available storage (${availableStorageMb}MB) is below the recommended ${MIN_STORAGE_MB}MB."
        }

        return mapOf(
            "isAndroid" to true,
            "runtime" to "LiteRT-LM",
            "modelFormat" to "litertlm",
            "sdkInt" to Build.VERSION.SDK_INT,
            "totalRamMb" to totalRamMb,
            "availableStorageMb" to availableStorageMb,
            "isSupported" to reasons.isEmpty(),
            "meetsRecommendedSpec" to (Build.VERSION.SDK_INT >= MIN_ANDROID_SDK &&
                totalRamMb >= RECOMMENDED_RAM_MB &&
                availableStorageMb >= MIN_STORAGE_MB),
            "reasons" to reasons,
        )
    }

    private fun getModelStatus(): Map<String, Any?> {
        val modelFile = getModelFile()
        val downloadStatus = getDownloadStatus()
        val isDownloaded = modelFile.exists() && modelFile.length() > 0L

        return mapOf(
            "runtime" to "LiteRT-LM",
            "modelVariant" to MODEL_VARIANT,
            "modelVersion" to (prefs.getString(KEY_MODEL_VERSION, MODEL_VERSION) ?: MODEL_VERSION),
            "modelPath" to if (isDownloaded) modelFile.absolutePath else null,
            "isDownloaded" to isDownloaded,
            "isReady" to (engine != null && initializedModelPath == modelFile.absolutePath),
            "isInitializing" to isInitializing,
            "downloadedBytes" to if (isDownloaded) modelFile.length() else 0L,
            "requiredBytes" to MODEL_SIZE_BYTES,
            "backend" to activeBackend,
            "message" to when {
                engine != null && initializedModelPath == modelFile.absolutePath ->
                    "Offline advisor is ready on-device."

                downloadStatus["state"] == "running" || downloadStatus["state"] == "pending" ->
                    "Model download is in progress."

                isDownloaded ->
                    "Model is downloaded and ready to initialize."

                else ->
                    "Download the offline model to enable Gemma 4 financial advice on this device."
            },
        )
    }

    private fun getDownloadStatus(): Map<String, Any> {
        val modelFile = getModelFile()
        val downloadId = prefs.getLong(KEY_DOWNLOAD_ID, -1L)
        if (downloadId == -1L) {
            return if (modelFile.exists() && modelFile.length() > 0L) {
                mapOf(
                    "state" to "completed",
                    "downloadedBytes" to modelFile.length(),
                    "totalBytes" to modelFile.length(),
                    "message" to "Model download complete.",
                )
            } else {
                mapOf(
                    "state" to "idle",
                    "downloadedBytes" to 0L,
                    "totalBytes" to MODEL_SIZE_BYTES,
                    "message" to "Model download has not started yet.",
                )
            }
        }

        val query = DownloadManager.Query().setFilterById(downloadId)
        downloadManager.query(query).use { cursor ->
            if (!cursor.moveToFirst()) {
                prefs.edit().remove(KEY_DOWNLOAD_ID).apply()
                return if (modelFile.exists() && modelFile.length() > 0L) {
                    mapOf(
                        "state" to "completed",
                        "downloadedBytes" to modelFile.length(),
                        "totalBytes" to modelFile.length(),
                        "message" to "Model download complete.",
                    )
                } else {
                    mapOf(
                        "state" to "idle",
                        "downloadedBytes" to 0L,
                        "totalBytes" to MODEL_SIZE_BYTES,
                        "message" to "No active model download.",
                    )
                }
            }

            val status =
                cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val downloadedBytes =
                cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val totalBytes =
                cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))

            return when (status) {
                DownloadManager.STATUS_PENDING -> mapOf(
                    "state" to "pending",
                    "downloadedBytes" to downloadedBytes,
                    "totalBytes" to if (totalBytes > 0L) totalBytes else MODEL_SIZE_BYTES,
                    "message" to "Waiting to start the model download.",
                )

                DownloadManager.STATUS_RUNNING -> mapOf(
                    "state" to "running",
                    "downloadedBytes" to downloadedBytes,
                    "totalBytes" to if (totalBytes > 0L) totalBytes else MODEL_SIZE_BYTES,
                    "message" to "Downloading the offline Gemma model.",
                )

                DownloadManager.STATUS_PAUSED -> mapOf(
                    "state" to "paused",
                    "downloadedBytes" to downloadedBytes,
                    "totalBytes" to if (totalBytes > 0L) totalBytes else MODEL_SIZE_BYTES,
                    "message" to "Model download paused (reason code $reason).",
                )

                DownloadManager.STATUS_SUCCESSFUL -> {
                    prefs.edit().remove(KEY_DOWNLOAD_ID).apply()
                    mapOf(
                        "state" to "completed",
                        "downloadedBytes" to modelFile.length(),
                        "totalBytes" to modelFile.length(),
                        "message" to "Model download complete.",
                    )
                }

                DownloadManager.STATUS_FAILED -> {
                    prefs.edit().remove(KEY_DOWNLOAD_ID).apply()
                    mapOf(
                        "state" to "failed",
                        "downloadedBytes" to downloadedBytes,
                        "totalBytes" to if (totalBytes > 0L) totalBytes else MODEL_SIZE_BYTES,
                        "message" to "Model download failed (reason code $reason).",
                    )
                }

                else -> mapOf(
                    "state" to "idle",
                    "downloadedBytes" to downloadedBytes,
                    "totalBytes" to if (totalBytes > 0L) totalBytes else MODEL_SIZE_BYTES,
                    "message" to "No active model download.",
                )
            }
        }
    }

    private fun startDownload(
        url: String,
        version: String,
        wifiOnly: Boolean,
    ): Map<String, Any> {
        val existingStatus = getDownloadStatus()
        val state = existingStatus["state"] as? String
        if (state == "pending" || state == "running") {
            return existingStatus
        }

        val modelFile = getModelFile()
        modelFile.parentFile?.mkdirs()
        if (modelFile.exists()) {
            modelFile.delete()
        }

        val request = DownloadManager.Request(Uri.parse(url))
            .setTitle("BurnRate offline advisor")
            .setDescription("Downloading $MODEL_VARIANT")
            .setAllowedOverRoaming(false)
            .setAllowedOverMetered(!wifiOnly)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            .setDestinationUri(Uri.fromFile(modelFile))

        val downloadId = downloadManager.enqueue(request)
        prefs.edit()
            .putLong(KEY_DOWNLOAD_ID, downloadId)
            .putString(KEY_MODEL_VERSION, version)
            .apply()
        return getDownloadStatus()
    }

    private fun cancelDownload(): Map<String, Any> {
        val downloadId = prefs.getLong(KEY_DOWNLOAD_ID, -1L)
        if (downloadId != -1L) {
            downloadManager.remove(downloadId)
            prefs.edit().remove(KEY_DOWNLOAD_ID).apply()
        }
        return mapOf(
            "state" to "idle",
            "downloadedBytes" to 0L,
            "totalBytes" to MODEL_SIZE_BYTES,
            "message" to "Model download cancelled.",
        )
    }

    private fun deleteModel(): Map<String, Any?> {
        cancelDownload()
        disposeEngineInternal()
        val modelFile = getModelFile()
        if (modelFile.exists()) {
            modelFile.delete()
        }
        prefs.edit().putString(KEY_MODEL_VERSION, MODEL_VERSION).apply()
        return getModelStatus()
    }

    private fun initializeModel(preferGpu: Boolean, result: MethodChannel.Result) {
        executor.execute {
            try {
                val modelFile = getModelFile()
                if (!modelFile.exists()) {
                    throw IllegalStateException("Offline model file is missing.")
                }
                if (engine != null && initializedModelPath == modelFile.absolutePath) {
                    postSuccess(result, getModelStatus())
                    return@execute
                }

                isInitializing = true
                disposeEngineInternal()
                val backend = if (preferGpu) Backend.GPU() else Backend.CPU()
                val engineConfig = EngineConfig(
                    modelPath = modelFile.absolutePath,
                    backend = backend,
                    cacheDir = context.cacheDir.absolutePath,
                )
                val newEngine = Engine(engineConfig)
                newEngine.initialize()
                engine = newEngine
                initializedModelPath = modelFile.absolutePath
                activeBackend = if (preferGpu) "gpu" else "cpu"
                postSuccess(result, getModelStatus())
            } catch (error: Throwable) {
                postError(
                    result,
                    "init_failed",
                    error.message ?: "Failed to initialize the offline model.",
                )
            } finally {
                isInitializing = false
            }
        }
    }

    private fun generateResponse(
        systemPrompt: String,
        userPrompt: String,
        result: MethodChannel.Result,
    ) {
        executor.execute {
            try {
                val localEngine = ensureEngine()
                localEngine.createConversation(
                    ConversationConfig(
                        systemInstruction = Contents.of(systemPrompt),
                    ),
                ).use { conversation ->
                    val response = conversation.sendMessage(userPrompt)
                    val text = response.toString()
                    postSuccess(
                        result,
                        mapOf(
                            "text" to text,
                            "backend" to activeBackend,
                        ),
                    )
                }
            } catch (error: Throwable) {
                postError(
                    result,
                    "generation_failed",
                    error.message ?: "Failed to generate an offline advisor reply.",
                )
            }
        }
    }

    private fun ensureEngine(): Engine {
        val existing = engine
        if (existing != null) {
            return existing
        }

        val modelFile = getModelFile()
        if (!modelFile.exists()) {
            throw IllegalStateException("Offline model file is missing.")
        }

        val newEngine = Engine(
            EngineConfig(
                modelPath = modelFile.absolutePath,
                backend = Backend.CPU(),
                cacheDir = context.cacheDir.absolutePath,
            ),
        )
        newEngine.initialize()
        engine = newEngine
        initializedModelPath = modelFile.absolutePath
        activeBackend = "cpu"
        return newEngine
    }

    private fun disposeEngineInternal() {
        try {
            engine?.close()
        } catch (_: Throwable) {
        } finally {
            engine = null
            initializedModelPath = null
        }
    }

    private fun getModelFile(): File {
        val baseDir = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: context.filesDir
        val modelDir = File(baseDir, "burnrate-ai/$MODEL_VERSION")
        if (!modelDir.exists()) {
            modelDir.mkdirs()
        }
        return File(modelDir, MODEL_FILE_NAME)
    }

    private fun getTotalRamMb(): Int {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)
        return (memoryInfo.totalMem / (1024L * 1024L)).toInt()
    }

    private fun getAvailableStorageMb(): Int {
        val usableSpace = getModelFile().parentFile?.usableSpace ?: 0L
        return (usableSpace / (1024L * 1024L)).toInt()
    }

    private fun postSuccess(result: MethodChannel.Result, payload: Any?) {
        mainHandler.post { result.success(payload) }
    }

    private fun postError(
        result: MethodChannel.Result,
        code: String,
        message: String,
    ) {
        mainHandler.post { result.error(code, message, null) }
    }
}
