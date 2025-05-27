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
import android.os.Build
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
                    if (this.flutterResultForScreenCapture != null) {
                        Log.w(TAG, "startScreenCapture called while another capture request is already pending. Aborting new request.")
                        result.error("ALREADY_ACTIVE", "A screen capture request is already in progress.", null)
                        return@setMethodCallHandler
                    }
                    this.flutterResultForScreenCapture = result
                    if (mediaProjectionManager != null) {
                        startActivityForResult(mediaProjectionManager!!.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
                    } else {
                        Log.e(TAG, "MediaProjectionManager is null when trying to start capture intent.")
                        val res = this.flutterResultForScreenCapture
                        this.flutterResultForScreenCapture = null
                        res?.error("UNAVAILABLE", "MediaProjectionManager not available.", null)
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

        val currentPendingResult = this.flutterResultForScreenCapture
        if (currentPendingResult == null) {
            Log.w(TAG, "onActivityResult: flutterResultForScreenCapture is null. This might happen if request timed out or activity was recreated. No action taken.")
            return
        }

        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Screen capture permission granted by user.")
                ScreenCaptureService.startService(this)
                val finalResultCode = resultCode
                val finalData = data
                
                handler.postDelayed({
                    Log.d(TAG, "Attempting to get MediaProjection after service start and delay.")
                    try {
                        if (this.flutterResultForScreenCapture == null || this.flutterResultForScreenCapture != currentPendingResult) {
                            Log.w(TAG, "flutterResultForScreenCapture changed or nulled before getMediaProjection. Aborting.")
                            ScreenCaptureService.stopService(this@MainActivity)
                            return@postDelayed
                        }
                        mediaProjection = mediaProjectionManager?.getMediaProjection(finalResultCode, finalData)
                        if (mediaProjection == null) {
                            Log.e(TAG, "getMediaProjection returned null even after service start.")
                            val result = this.flutterResultForScreenCapture
                            this.flutterResultForScreenCapture = null
                            result?.error("PROJECTION_ERROR", "Failed to get MediaProjection post-service-start.", null)
                            cleanUpScreenCaptureResources(true)
                            return@postDelayed
                        }
                        Log.d(TAG, "MediaProjection obtained successfully after service start.")
                        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                            override fun onStop() {
                                super.onStop()
                                Log.w(TAG, "MediaProjection.Callback onStop() called.")
                                val result = flutterResultForScreenCapture
                                flutterResultForScreenCapture = null
                                result?.error("PROJECTION_STOPPED", "MediaProjection stopped unexpectedly.", null)
                                cleanUpScreenCaptureResources(true) 
                            }
                        }, handler)
                        captureScreenshotAndReply()
                    } catch (e: SecurityException) {
                        Log.e(TAG, "SecurityException when getting MediaProjection: ${e.message}", e)
                        val result = this.flutterResultForScreenCapture
                        this.flutterResultForScreenCapture = null
                        result?.error("SECURITY_EXCEPTION_POST_SERVICE", "SecurityException: ${e.message}", null)
                        cleanUpScreenCaptureResources(true) 
                    } catch (e: Exception) {
                        Log.e(TAG, "Generic Exception when getting MediaProjection: ${e.message}", e)
                        val result = this.flutterResultForScreenCapture
                        this.flutterResultForScreenCapture = null
                        result?.error("EXCEPTION_POST_SERVICE", "Exception: ${e.message}", null)
                        cleanUpScreenCaptureResources(true) 
                    }
                }, 300)

            } else {
                Log.w(TAG, "Screen capture permission denied by user or cancelled. Result code: $resultCode")
                val result = this.flutterResultForScreenCapture
                this.flutterResultForScreenCapture = null
                result?.error("USER_DENIED", "Screen capture permission denied by user.", null)
            }
        }
    }

    private fun captureScreenshotAndReply() {
        val activeResultForThisAttempt = this.flutterResultForScreenCapture
        if (mediaProjection == null || activeResultForThisAttempt == null) {
            Log.e(TAG, "captureScreenshotAndReply: MediaProjection or an active Result callback is null at start.")
            if (activeResultForThisAttempt != null) {
                 this.flutterResultForScreenCapture = null
                 activeResultForThisAttempt.error("INTERNAL_ERROR_PRE_CAPTURE", "MediaProjection is null or result already handled.", null)
            }
            cleanUpScreenCaptureResources(true) 
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

        val localImageReader = imageReader 

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            localImageReader?.surface, null, handler
        )

        if (virtualDisplay == null) {
             Log.e(TAG, "Failed to create VirtualDisplay.")
             this.flutterResultForScreenCapture = null 
             activeResultForThisAttempt.error("VIRTUAL_DISPLAY_FAIL", "Failed to create VirtualDisplay.", null)
             cleanUpScreenCaptureResources(true)
             return
        }
        Log.d(TAG, "VirtualDisplay created.")

        localImageReader?.setOnImageAvailableListener({ reader ->
            val resultForThisCallback = this.flutterResultForScreenCapture
            if (resultForThisCallback == null) {
                Log.w(TAG, "ImageAvailableListener: flutterResultForScreenCapture is null, reply already sent or error occurred. Ignoring.")
                return@setOnImageAvailableListener
            }
            this.flutterResultForScreenCapture = null

            Log.d(TAG, "ImageAvailableListener: New image is available. Processing...")
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
                    
                    resultForThisCallback.success(byteArray)
                    cleanUpScreenCaptureResources(false)

                } else {
                    Log.w(TAG, "Acquired image is null in listener.")
                    resultForThisCallback.error("IMAGE_NULL_LISTENER", "Acquired image is null in listener.", null)
                    cleanUpScreenCaptureResources(true)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception during screen capture processing in listener: ${e.message}", e)
                resultForThisCallback.error("CAPTURE_EXCEPTION_LISTENER", "Exception in listener: ${e.message}", null)
                cleanUpScreenCaptureResources(true)
            } finally {
                image?.close()
                bitmap?.recycle() 
                Log.d(TAG, "ImageAvailableListener: Processing and cleanup for this image done.")
            }
        }, handler)
    }

    private fun cleanUpScreenCaptureResources(stopService: Boolean) {
        Log.d(TAG, "cleanUpScreenCaptureResources called. Stop service: $stopService")
        try {
            if (imageReader != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                 // imageReader?.setOnImageAvailableListener(null, null) // This can be problematic
            }
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
        if (this.flutterResultForScreenCapture != null) {
            Log.w(TAG, "flutterResultForScreenCapture was not null during final cleanup. This might indicate an unhandled path.")
            this.flutterResultForScreenCapture = null
        }

        if (stopService) {
            ScreenCaptureService.stopService(this)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "onDestroy called.")
        cleanUpScreenCaptureResources(true) 
    }
}
