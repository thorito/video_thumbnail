package com.rocksti.get_thumbnail_video

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.roundToInt

/**
 * VideoThumbnailPlugin
 */
class VideoThumbnailPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var context: Context
    private var executor: ExecutorService? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        executor = Executors.newCachedThreadPool()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@VideoThumbnailPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments() as? Map<String, Any?> ?: run {
            result.notImplemented()
            return
        }

        val headers = args["headers"] as? Map<String, String>
        val video = args["video"] as String
        val format = args["format"] as Int
        val maxh = args["maxh"] as Int
        val maxw = args["maxw"] as Int
        val timeMs = args["timeMs"] as Int
        val quality = args["quality"] as Int

        executor?.execute {
            var thumbnail: Any? = null
            var handled = false
            var exc: Exception? = null

            try {
                when (call.method) {
                    METHOD_FILE -> {
                        val path = args["path"] as? String
                        thumbnail = buildThumbnailFile(video, headers, path, format, maxh, maxw, timeMs, quality)
                        handled = true
                    }
                    METHOD_DATA -> {
                        thumbnail = buildThumbnailData(video, headers, format, maxh, maxw, timeMs, quality)
                        handled = true
                    }
                }
            } catch (e: Exception) {
                exc = e
            }

            onResult(result, thumbnail, handled, exc)
        }
    }

    private fun buildThumbnailData(
        vidPath: String,
        headers: Map<String, String>?,
        format: Int,
        maxh: Int,
        maxw: Int,
        timeMs: Int,
        quality: Int
    ): ByteArray {
        val bitmap = createVideoThumbnail(vidPath, headers, maxh, maxw, timeMs)
            ?: throw IllegalStateException("Failed to extract video frame. The video may be too large, corrupt, or in an unsupported format.")

        return ByteArrayOutputStream().use { stream ->
            bitmap.compress(intToFormat(format), quality, stream)
            bitmap.recycle()
            stream.toByteArray()
        }
    }

    private fun buildThumbnailFile(
        vidPath: String,
        headers: Map<String, String>?,
        path: String?,
        format: Int,
        maxh: Int,
        maxw: Int,
        timeMs: Int,
        quality: Int
    ): String {
        val bytes = buildThumbnailData(vidPath, headers, format, maxh, maxw, timeMs, quality)
        val ext = formatExt(format)
        val dotIndex = vidPath.lastIndexOf('.')
        val slashIndex = vidPath.lastIndexOf('/')

        val baseName = if (dotIndex > slashIndex) {
            vidPath.substring(0, dotIndex + 1) + ext
        } else {
            "$vidPath.$ext"
        }

        val isLocalFile = vidPath.startsWith("/") || vidPath.startsWith("file://")

        var targetPath = path
        if (targetPath == null && !isLocalFile) {
            targetPath = context.cacheDir.absolutePath
        }

        val fullPath = when {
            targetPath == null -> baseName
            targetPath.endsWith(ext) -> targetPath
            else -> {
                val fileName = baseName.substring(baseName.lastIndexOf('/') + 1)
                if (targetPath.endsWith("/")) "$targetPath$fileName" else "$targetPath/$fileName"
            }
        }

        try {
            val file = File(fullPath)
            file.parentFile?.takeIf { !it.exists() }?.mkdirs()
            FileOutputStream(fullPath).use { it.write(bytes) }
            Log.d(TAG, "buildThumbnailFile( written:${bytes.size} )")
        } catch (e: IOException) {
            e.printStackTrace()
            throw RuntimeException(e)
        }

        return fullPath
    }

    private fun onResult(result: Result, thumbnail: Any?, handled: Boolean, e: Exception?) {
        runOnUiThread {
            when {
                !handled -> result.notImplemented()
                e != null -> {
                    e.printStackTrace()
                    result.error("exception", e.message, null)
                }
                else -> result.success(thumbnail)
            }
        }
    }

    private fun runOnUiThread(runnable: Runnable) {
        Handler(Looper.getMainLooper()).post(runnable)
    }

    /**
     * Create a video thumbnail for a video. May return null if the video is corrupt
     * or the format is not supported.
     *
     * @param video the URI of video
     * @param targetH the max height of the thumbnail
     * @param targetW the max width of the thumbnail
     */
    fun createVideoThumbnail(
        video: String,
        headers: Map<String, String>?,
        targetH: Int,
        targetW: Int,
        timeMs: Int
    ): Bitmap? {
        val retriever = MediaMetadataRetriever()

        try {
            when {
                video.startsWith("/") -> setDataSource(video, retriever)
                video.startsWith("file://") -> setDataSource(video.substring(7), retriever)
                else -> retriever.setDataSource(video, headers ?: emptyMap())
            }

            val durationStr = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            val duration = durationStr?.toLongOrNull() ?: 0L
            val safeTimeMs = if (duration > 0 && timeMs * 1000L > duration) duration else timeMs * 1000L

            Log.d(TAG, "Video duration: ${duration}ms, requesting frame at: ${safeTimeMs}us")

            var bitmap = extractFrameWithOptions(retriever, safeTimeMs, targetW, targetH)

            if (bitmap == null && safeTimeMs != 0L) {
                Log.d(TAG, "Retrying with frame at 0ms")
                bitmap = extractFrameWithOptions(retriever, 0, targetW, targetH)
            }

            return bitmap
        } catch (ex: RuntimeException) {
            Log.e(TAG, "RuntimeException extracting frame", ex)
            return null
        } catch (ex: IOException) {
            Log.e(TAG, "IOException extracting frame", ex)
            return null
        } finally {
            try {
                retriever.release()
            } catch (ex: Exception) {
                Log.e(TAG, "Error releasing MediaMetadataRetriever", ex)
            }
        }
    }

    private fun extractFrameWithOptions(
        retriever: MediaMetadataRetriever,
        timeUs: Long,
        targetW: Int,
        targetH: Int
    ): Bitmap? {
        val options = listOf(
            MediaMetadataRetriever.OPTION_CLOSEST,
            MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
            MediaMetadataRetriever.OPTION_PREVIOUS_SYNC,
            MediaMetadataRetriever.OPTION_NEXT_SYNC
        )

        for (option in options) {
            try {
                val bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && targetH != 0 && targetW != 0) {
                    retriever.getScaledFrameAtTime(timeUs, option, targetW, targetH)
                } else {
                    val frame = retriever.getFrameAtTime(timeUs, option)
                    if (frame != null && (targetW != 0 || targetH != 0)) {
                        val width = frame.width
                        val height = frame.height
                        val finalW = if (targetW == 0) ((targetH.toFloat() / height) * width).roundToInt() else targetW
                        val finalH = if (targetH == 0) ((targetW.toFloat() / width) * height).roundToInt() else targetH
                        Log.d(TAG, "Scaling frame: $width x $height => $finalW x $finalH")
                        Bitmap.createScaledBitmap(frame, finalW, finalH, true).also { frame.recycle() }
                    } else {
                        frame
                    }
                }

                if (bitmap != null) {
                    Log.d(TAG, "Successfully extracted frame with option: $option")
                    return bitmap
                }
            } catch (e: Exception) {
                Log.d(TAG, "Failed with option $option: ${e.message}")
            }
        }

        Log.w(TAG, "All frame extraction options failed")
        return null
    }

    @Throws(IOException::class)
    private fun setDataSource(video: String, retriever: MediaMetadataRetriever) {
        val videoFile = File(video)
        FileInputStream(videoFile.absolutePath).use { inputStream ->
            retriever.setDataSource(inputStream.fd)
        }
    }

    companion object {
        private const val TAG = "ThumbnailPlugin"
        private const val CHANNEL_NAME = "video_thumbnail"
        private const val METHOD_FILE = "file"
        private const val METHOD_DATA = "data"

        private fun intToFormat(format: Int): Bitmap.CompressFormat = when (format) {
            0 -> Bitmap.CompressFormat.JPEG
            1 -> Bitmap.CompressFormat.PNG
            2 -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                Bitmap.CompressFormat.WEBP_LOSSLESS
            } else {
                Bitmap.CompressFormat.WEBP
            }
            else -> Bitmap.CompressFormat.JPEG
        }

        private fun formatExt(format: Int): String = when (format) {
            0 -> "jpg"
            1 -> "png"
            2 -> "webp"
            else -> "jpg"
        }
    }
}
