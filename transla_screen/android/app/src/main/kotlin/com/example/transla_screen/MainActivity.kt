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
import android.util.Log
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.transla_screen/screen_capture"
    private val REQUEST_CODE_SCREEN_CAPTURE = 1002
    private val TAG = "MainActivityCapture"

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var flutterResultForScreenCapture: MethodChannel.Result? = null 

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private val handler: Handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        Log.d(TAG, "configureFlutterEngine called and MediaProjectionManager initialized.")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "startScreenCapture" -> {
                    Log.d(TAG, "startScreenCapture method call received.")
                    if (mediaProjectionManager != null) {
                        this.flutterResultForScreenCapture = result 
                        ScreenCaptureService.startService(this)
                        startActivityForResult(mediaProjectionManager!!.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
                    } else {
                        Log.e(TAG, "MediaProjectionManager is null when trying to start capture intent.")
                        result.error("UNAVAILABLE", "MediaProjectionManager not available.", null)
                        ScreenCaptureService.stopService(this)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        Log.d(TAG, "MethodChannel for screen_capture configured.")
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        Log.d(TAG, "onActivityResult: requestCode=$requestCode, resultCode=$resultCode")
        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Screen capture permission granted.")
                try {
                    mediaProjection = mediaProjectionManager?.getMediaProjection(resultCode, data)
                    if (mediaProjection == null) {
                        Log.e(TAG, "getMediaProjection returned null.")
                        flutterResultForScreenCapture?.error("PROJECTION_ERROR", "Failed to get MediaProjection.", null)
                        cleanUpScreenCapture(false)
                        return
                    }
                    Log.d(TAG, "MediaProjection obtained successfully.")
                    mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                        override fun onStop() {
                            super.onStop()
                            Log.w(TAG, "MediaProjection.Callback onStop() called - projection stopped unexpectedly.")
                            if (flutterResultForScreenCapture != null) {
                                flutterResultForScreenCapture?.error("PROJECTION_STOPPED", "MediaProjection stopped unexpectedly.", null)
                            }
                            cleanUpScreenCapture(true)
                        }
                    }, handler)
                    captureScreenshotAndReply()
                } catch (e: SecurityException) {
                    Log.e(TAG, "SecurityException in onActivityResult: ${e.message}", e)
                    flutterResultForScreenCapture?.error("SECURITY_EXCEPTION", "SecurityException: ${e.message}. Ensure foreground service is running correctly.", null)
                    cleanUpScreenCapture(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Generic Exception in onActivityResult: ${e.message}", e)
                    flutterResultForScreenCapture?.error("EXCEPTION_ON_RESULT", "Exception in onActivityResult: ${e.message}", null)
                    cleanUpScreenCapture(true)
                }
            } else {
                Log.w(TAG, "Screen capture permission denied by user or cancelled. Result code: $resultCode")
                flutterResultForScreenCapture?.error("USER_DENIED", "Screen capture permission denied by user.", null)
                cleanUpScreenCapture(true)
            }
        }
    }

    private fun captureScreenshotAndReply() {
        val currentResult = flutterResultForScreenCapture 
        if (mediaProjection == null || currentResult == null) {
            Log.e(TAG, "captureScreenshotAndReply: MediaProjection or Result callback is null.")
            currentResult?.error("INTERNAL_ERROR", "MediaProjection or Result callback is null before capture.", null)
            cleanUpScreenCapture(false)
            return
        }
        Log.d(TAG, "Starting actual screenshot capture logic.")

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(displayMetrics)
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels
        val screenDensity = displayMetrics.densityDpi

        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        Log.d(TAG, "ImageReader created with size: $screenWidth x $screenHeight")

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, handler
        )
        if (virtualDisplay == null) {
             Log.e(TAG, "Failed to create VirtualDisplay.")
             currentResult.error("VIRTUAL_DISPLAY_FAIL", "Failed to create VirtualDisplay.", null)
             cleanUpScreenCapture(false)
             return
        }
        Log.d(TAG, "VirtualDisplay created.")

        imageReader?.setOnImageAvailableListener({ reader ->
            Log.d(TAG, "ImageAvailableListener: New image is available.")
            var image: Image? = null
            var bitmap: Bitmap? = null
            try {
                image = reader.acquireLatestImage()
                if (image != null) {
                    Log.d(TAG, "Image acquired successfully.")
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
                    Log.d(TAG, "Bitmap created and cropped.")

                    val byteArrayOutputStream = ByteArrayOutputStream()
                    croppedBitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
                    val byteArray = byteArrayOutputStream.toByteArray()
                    Log.d(TAG, "Bitmap compressed to PNG byte array, size: ${byteArray.size}")
                    
                    currentResult.success(byteArray)
                    cleanUpScreenCapture(false)

                } else {
                    Log.w(TAG, "Acquired image is null.")
                    currentResult.error("IMAGE_NULL", "Acquired image is null.", null)
                    cleanUpScreenCapture(true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception during screen capture processing: ${e.message}", e)
                currentResult.error("CAPTURE_EXCEPTION", "Exception during screen capture: ${e.message}", null)
                cleanUpScreenCapture(true)
            } finally {
                image?.close()
                bitmap?.recycle() 
                Log.d(TAG, "ImageAvailableListener: Cleanup done.")
            }
        }, handler)
    }

    private fun cleanUpScreenCapture(stopService: Boolean) {
        Log.d(TAG, "cleanUpScreenCapture called. Stop service: $stopService")
        try {
            virtualDisplay?.release()
            virtualDisplay = null
            imageReader?.close()
            imageReader = null
            if (mediaProjection != null) {
                mediaProjection?.stop() 
                mediaProjection = null
                Log.d(TAG, "MediaProjection explicitly stopped.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception during media projection resource cleanup: ${e.message}", e)
        }
        flutterResultForScreenCapture = null
        if (stopService) {
            ScreenCaptureService.stopService(this)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy called.")
        cleanUpScreenCapture(true) 
    }
}
