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
    @Volatile private var latestFrameBytes: ByteArray? = null
    private var isCaptureSessionActive = false // To track if continuous capture is running

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        Log.d(TAG, "configureFlutterEngine called and MediaProjectionManager initialized.")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "startScreenCapture" -> {
                    Log.d(TAG, "startScreenCapture method call received.")
                    if (isCaptureSessionActive && latestFrameBytes != null) {
                        Log.d(TAG, "Capture session active and frame available. Returning latest frame.")
                        result.success(latestFrameBytes)
                        // latestFrameBytes = null // Optionally clear after sending, or let it be overwritten
                    } else if (isCaptureSessionActive && latestFrameBytes == null) {
                        Log.d(TAG, "Capture session active but no frame yet. Waiting for next frame.")
                        // This case might happen if called immediately after setup before first frame arrives.
                        // Store result to be fulfilled by OnImageAvailableListener or timeout.
                        // For simplicity, we can ask Flutter to retry or implement a more robust queue.
                        this.flutterResultForScreenCapture = result // Listener will pick this up
                    } else {
                        Log.d(TAG, "Capture session not active. Initiating permission request.")
                        if (this.flutterResultForScreenCapture != null) {
                            Log.w(TAG, "startScreenCapture called while another permission request is already pending. Aborting new request.")
                            result.error("ALREADY_PENDING_PERMISSION", "A screen capture permission request is already in progress.", null)
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
                        if (this@MainActivity.flutterResultForScreenCapture == null || this@MainActivity.flutterResultForScreenCapture != currentPendingResult) {
                            Log.w(TAG, "flutterResultForScreenCapture changed or nulled before getMediaProjection. Aborting.")
                            ScreenCaptureService.stopService(this@MainActivity)
                            return@postDelayed
                        }
                        mediaProjection = this@MainActivity.mediaProjectionManager?.getMediaProjection(finalResultCode, finalData)
                        if (mediaProjection == null) {
                            Log.e(TAG, "getMediaProjection returned null even after service start.")
                            val result = this@MainActivity.flutterResultForScreenCapture
                            this@MainActivity.flutterResultForScreenCapture = null
                            result?.error("PROJECTION_ERROR", "Failed to get MediaProjection post-service-start.", null)
                            cleanUpScreenCaptureResources(true)
                            return@postDelayed
                        }
                        Log.d(TAG, "MediaProjection obtained successfully after service start.")
                        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                            override fun onStop() {
                                super.onStop()
                                Log.w(TAG, "MediaProjection.Callback onStop() called.")
                                this@MainActivity.isCaptureSessionActive = false
                                val resultToNotify = this@MainActivity.flutterResultForScreenCapture
                                this@MainActivity.flutterResultForScreenCapture = null
                                resultToNotify?.error("PROJECTION_STOPPED", "MediaProjection stopped unexpectedly.", null)
                                cleanUpScreenCaptureResources(true)
                            }
                        }, this@MainActivity.handler)
                        setupContinuousCapture() // Setup continuous capture instead of one-off
                    } catch (e: SecurityException) {
                        Log.e(TAG, "SecurityException when getting MediaProjection: ${e.message}", e)
                        val result = this@MainActivity.flutterResultForScreenCapture
                        this@MainActivity.flutterResultForScreenCapture = null
                        result?.error("SECURITY_EXCEPTION_POST_SERVICE", "SecurityException: ${e.message}", null)
                        cleanUpScreenCaptureResources(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Generic Exception when getting MediaProjection: ${e.message}", e)
                        val result = this@MainActivity.flutterResultForScreenCapture
                        this@MainActivity.flutterResultForScreenCapture = null
                        result?.error("EXCEPTION_POST_SERVICE", "Exception: ${e.message}", null)
                        cleanUpScreenCaptureResources(true)
                    }
                }, 300)
            } else {
                Log.w(TAG, "Screen capture permission denied by user or cancelled. Result code: $resultCode")
                val result = this.flutterResultForScreenCapture
                this.flutterResultForScreenCapture = null
                result?.error("USER_DENIED", "Screen capture permission denied by user.", null)
                // No need to call cleanUpScreenCaptureResources here as nothing was set up yet
            }
        } else {
             Log.d(TAG, "onActivityResult received for requestCode $requestCode, not SCREEN_CAPTURE_REQUEST_CODE. Ignoring.")
        }
    }

    private fun setupContinuousCapture() {
        if (mediaProjection == null) {
            Log.e(TAG, "setupContinuousCapture: MediaProjection is null.")
            val result = this.flutterResultForScreenCapture
            this.flutterResultForScreenCapture = null
            result?.error("INTERNAL_ERROR_SETUP", "MediaProjection became null before setup.", null)
            cleanUpScreenCaptureResources(true)
            return
        }
        Log.d(TAG, "Setting up continuous screen capture.")

        val windowManager = this@MainActivity.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()
        windowManager.defaultDisplay.getRealMetrics(displayMetrics)
        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels
        val screenDensity = displayMetrics.densityDpi

        imageReader?.close() // Close existing reader if any
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        Log.d(TAG, "ImageReader created/recreated for continuous capture with size: $screenWidth x $screenHeight")

        virtualDisplay?.release() // Release existing display if any
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ContinuousScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, handler
        )

        if (virtualDisplay == null) {
            Log.e(TAG, "Failed to create VirtualDisplay for continuous capture.")
            val result = this.flutterResultForScreenCapture
            this.flutterResultForScreenCapture = null
            result?.error("VIRTUAL_DISPLAY_FAIL_CONTINUOUS", "Failed to create VirtualDisplay for continuous capture.", null)
            cleanUpScreenCaptureResources(true)
            return
        }
        isCaptureSessionActive = true
        Log.d(TAG, "VirtualDisplay for continuous capture created.")

        imageReader?.setOnImageAvailableListener({ reader ->
            var image: Image? = null
            try {
                image = reader.acquireLatestImage() // Use acquireLatestImage to prevent processing stale frames
                if (image != null) {
                    val planes = image.planes
                    val buffer = planes[0].buffer
                    val pixelStride = planes[0].pixelStride
                    val rowStride = planes[0].rowStride
                    val rowPadding = rowStride - pixelStride * screenWidth

                    val bitmap = Bitmap.createBitmap(
                        screenWidth + rowPadding / pixelStride,
                        screenHeight,
                        Bitmap.Config.ARGB_8888
                    )
                    bitmap.copyPixelsFromBuffer(buffer)
                    val croppedBitmap = Bitmap.createBitmap(bitmap, 0, 0, screenWidth, screenHeight)
                    
                    val byteArrayOutputStream = ByteArrayOutputStream()
                    croppedBitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
                    this@MainActivity.latestFrameBytes = byteArrayOutputStream.toByteArray()
                    bitmap.recycle()
                    croppedBitmap.recycle()
                    Log.d(TAG, "ContinuousCaptureListener: New frame processed, size: ${this@MainActivity.latestFrameBytes?.size}")

                    // If there's a pending Flutter result (likely the one that initiated capture), fulfill it.
                    val pendingResult = this@MainActivity.flutterResultForScreenCapture
                    if (pendingResult != null) {
                        Log.d(TAG, "ContinuousCaptureListener: Fulfilling pending Flutter request.")
                        this@MainActivity.flutterResultForScreenCapture = null // Clear it after use
                        pendingResult.success(this@MainActivity.latestFrameBytes)
                    }
                } else {
                    // This can happen, just means no new image was available at this exact moment
                    // Log.v(TAG, "ContinuousCaptureListener: acquireLatestImage returned null.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception in continuous screen capture listener: ${e.message}", e)
                // Potentially signal an error or try to recover, but avoid stopping continuous capture unless fatal
            } finally {
                image?.close()
            }
        }, this@MainActivity.handler)
    }

    private fun cleanUpScreenCaptureResources(stopService: Boolean) {
        Log.d(TAG, "cleanUpScreenCaptureResources called. Stop service: $stopService")
        isCaptureSessionActive = false
        latestFrameBytes = null
        try {
            virtualDisplay?.release()
            virtualDisplay = null
            Log.d(TAG, "VirtualDisplay released.")
        } catch (e: Exception) {
            Log.e(TAG, "Exception releasing VirtualDisplay: ${e.message}", e)
        }
        try {
            imageReader?.close()
            imageReader = null
            Log.d(TAG, "ImageReader closed.")
        } catch (e: Exception) {
            Log.e(TAG, "Exception closing ImageReader: ${e.message}", e)
        }
        try {
            if (mediaProjection != null) {
                mediaProjection?.stop() 
                mediaProjection = null
                Log.d(TAG, "MediaProjection explicitly stopped.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception stopping MediaProjection: ${e.message}", e)
        }
        
        val pendingResult = this.flutterResultForScreenCapture
        if (pendingResult != null) {
            Log.w(TAG, "flutterResultForScreenCapture was not null during final cleanup. Notifying error.")
            pendingResult.error("CAPTURE_CLEANED_UP", "Screen capture resources were cleaned up before result could be sent.", null)
            this.flutterResultForScreenCapture = null
        }

        if (stopService) {
            Log.d(TAG, "Stopping ScreenCaptureService.")
            ScreenCaptureService.stopService(this@MainActivity)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy called.")
        cleanUpScreenCaptureResources(true)
        super.onDestroy() // Call super.onDestroy() last
    }
}
