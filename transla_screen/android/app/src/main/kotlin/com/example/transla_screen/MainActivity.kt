package com.example.transla_screen

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.translascreen/native_bridge"
    private val REQUEST_CODE_SCREEN_CAPTURE = 1002

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var flutterResultForScreenCapture: MethodChannel.Result? = null 

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler: Handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "startScreenCapture" -> {
                    if (mediaProjectionManager != null) {
                        this.flutterResultForScreenCapture = result 
                        startActivityForResult(mediaProjectionManager!!.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
                    } else {
                        result.error("UNAVAILABLE", "MediaProjectionManager not available.", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)
                if (mediaProjection == null) {
                    flutterResultForScreenCapture?.error("PROJECTION_ERROR", "Failed to get MediaProjection.", null)
                    flutterResultForScreenCapture = null
                    return
                }
                mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        super.onStop()
                        stopMediaProjection()
                    }
                }, handler)
                captureScreenshotAndReply()
            } else {
                flutterResultForScreenCapture?.error("USER_DENIED", "Screen capture permission denied by user.", null)
                flutterResultForScreenCapture = null
            }
        }
    }

    private fun captureScreenshotAndReply() {
        val currentResult = flutterResultForScreenCapture 
        if (mediaProjection == null || currentResult == null) {
            currentResult?.error("INTERNAL_ERROR", "MediaProjection or Result callback is null.", null)
            flutterResultForScreenCapture = null
            return
        }

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(displayMetrics)
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels
        val screenDensity = displayMetrics.densityDpi

        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, handler
        )

        imageReader?.setOnImageAvailableListener({ reader ->
            var image: Image? = null
            var bitmap: Bitmap? = null
            val fos: ByteArrayOutputStream? = null
            try {
                image = reader.acquireLatestImage()
                if (image != null) {
                    val planes = image.planes
                    val buffer = planes[0].buffer
                    val pixelStride = planes[0].pixelStride
                    val rowStride = planes[0].rowStride
                    val rowPadding = rowStride - pixelStride * screenWidth

                    bitmap = Bitmap.createBitmap(
                        screenWidth + rowPadding / pixelStride,
                        screenHeight,
                        Bitmap.Config.ARGB_8888
                    )
                    bitmap.copyPixelsFromBuffer(buffer)

                    val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)

                    val byteArrayOutputStream = ByteArrayOutputStream()
                    croppedBitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
                    val byteArray = byteArrayOutputStream.toByteArray()
                    
                    currentResult.success(byteArray)
                    flutterResultForScreenCapture = null

                    stopMediaProjection()

                } else {
                    currentResult.error("IMAGE_NULL", "Acquired image is null.", null)
                    flutterResultForScreenCapture = null
                    stopMediaProjection()
                }
            } catch (e: Exception) {
                currentResult.error("CAPTURE_EXCEPTION", "Exception during screen capture: ${e.message}", null)
                flutterResultForScreenCapture = null
                 stopMediaProjection()
            } finally {
                image?.close()
                bitmap?.recycle() 
                fos?.close()
            }
        }, handler)
    }

    private fun stopMediaProjection() {
        try {
            virtualDisplay?.release()
            virtualDisplay = null
            imageReader?.close()
            imageReader = null
            mediaProjection?.stop()
            mediaProjection = null
        } catch (e: Exception) {
            // Log error or handle
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopMediaProjection()
    }
}
