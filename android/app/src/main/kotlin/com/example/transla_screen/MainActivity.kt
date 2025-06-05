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
import android.os.HandlerThread
import android.os.Looper
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.transla_screen/screen_capture"
    private val REQUEST_CODE_SCREEN_CAPTURE = 1002
    private val TAG = "MainActivityCapture"

    private var mediaProjectionManager: MediaProjectionManager? = null
    private var flutterResultForScreenCapture: MethodChannel.Result? = null

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    @Volatile private var latestFrameBytes: ByteArray? = null
    private var isCaptureSessionActive = false

    // --- Threading and Handler Setup ---
    private val mainHandler: Handler = Handler(Looper.getMainLooper())
    private var imageProcessThread: HandlerThread? = null
    private var imageProcessHandler: Handler? = null // For ImageReader callbacks and VirtualDisplay callbacks

    // --- Frame Throttling ---
    @Volatile private var lastFrameProcessTimeMs: Long = 0
    // Process one frame every 150ms (15 FPS). Adjust as needed.
    // Set to 0 if you want to process every frame (might be CPU intensive).
    private val FRAME_PROCESS_INTERVAL_MS: Long = 150

    // --- Reusable Objects ---
    private val reusableOutputStream = ByteArrayOutputStream()

    // --- 原生悬浮窗插件 ---
    private val nativeOverlayPlugin = NativeOverlayPlugin()

    // --- MediaProjection Callback ---
    private val mediaProjectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            super.onStop()
            Log.w(TAG, "MediaProjection.Callback onStop() called.")
            // Ensure UI/Flutter interaction happens on main thread
            mainHandler.post {
                val resultToNotify = this@MainActivity.flutterResultForScreenCapture
                this@MainActivity.flutterResultForScreenCapture = null
                resultToNotify?.error("PROJECTION_STOPPED", "MediaProjection stopped unexpectedly.", null)
                // Call cleanup, but avoid recursive calls if onStop is part of cleanup
                if (isCaptureSessionActive) { // only if it was active
                    cleanUpScreenCaptureResources(true)
                }
            }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 注册原生悬浮窗插件
        flutterEngine.plugins.add(nativeOverlayPlugin)
        
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        Log.d(TAG, "configureFlutterEngine called and MediaProjectionManager initialized.")

        // Initialize background thread for image processing
        imageProcessThread = HandlerThread("ScreenCaptureProcessingThread").apply {
            start()
            imageProcessHandler = Handler(looper)
        }
        Log.d(TAG, "ImageProcessingThread started.")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenCapture" -> {
                    Log.d(TAG, "startScreenCapture method call received.")
                    val currentFrame = latestFrameBytes // Read volatile once
                    if (isCaptureSessionActive && currentFrame != null) {
                        Log.d(TAG, "Capture session active and frame available. Returning latest frame.")
                        result.success(currentFrame.clone()) // Send a clone
                    } else if (isCaptureSessionActive && currentFrame == null) {
                        Log.d(TAG, "Capture session active but no frame yet. Waiting for next frame.")
                        if (this.flutterResultForScreenCapture != null && this.flutterResultForScreenCapture != result) {
                            Log.w(TAG, "startScreenCapture: Another FlutterResult is already pending for a frame. Overwriting previous.")
                            // Optionally, error out the previous or current request.
                            // this.flutterResultForScreenCapture?.error("SUPERSEDED", "Request superseded by new one.", null)
                        }
                        this.flutterResultForScreenCapture = result
                    } else { // Session not active or first call
                        Log.d(TAG, "Capture session not active. Initiating permission request.")
                        if (this.flutterResultForScreenCapture != null) {
                            Log.w(TAG, "startScreenCapture: Another permission request is already pending. Aborting new request.")
                            result.error("ALREADY_PENDING_PERMISSION", "A screen capture permission request is already in progress.", null)
                            return@setMethodCallHandler
                        }
                        this.flutterResultForScreenCapture = result
                        if (mediaProjectionManager != null) {
                            startActivityForResult(mediaProjectionManager!!.createScreenCaptureIntent(), REQUEST_CODE_SCREEN_CAPTURE)
                        } else {
                            Log.e(TAG, "MediaProjectionManager is null.")
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

        val currentPendingResult = this.flutterResultForScreenCapture // Capture before any async operation
        if (currentPendingResult == null) {
            Log.w(TAG, "onActivityResult: flutterResultForScreenCapture is null. This might happen if request timed out or activity was recreated. No action taken.")
            // If we successfully got permission but the result handler is gone, we might have started a service
            // that needs stopping if it's not intended to run indefinitely.
            if (resultCode == Activity.RESULT_OK) {
                 // ScreenCaptureService.stopService(this) // Consider this if service is only for active capture
            }
            return
        }

        if (requestCode == REQUEST_CODE_SCREEN_CAPTURE) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                Log.d(TAG, "Screen capture permission granted.")
                ScreenCaptureService.startService(this) // Start foreground service
                val finalResultCode = resultCode
                val finalData = data

                // The 300ms delay was in your original code. It might be a workaround for some race condition
                // with service startup or MediaProjection availability. Test reducing or removing it.
                mainHandler.postDelayed({
                    if (this@MainActivity.flutterResultForScreenCapture != currentPendingResult) {
                        Log.w(TAG, "onActivityResult: flutterResultForScreenCapture changed or nulled during delay. Aborting projection setup.")
                        // ScreenCaptureService.stopService(this@MainActivity) // Stop if started for this request
                        return@postDelayed
                    }
                    try {
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
                        mediaProjection?.registerCallback(mediaProjectionCallback, mainHandler) // Use mainHandler for its callbacks
                        setupContinuousCapture()
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
            }
        } else {
            Log.d(TAG, "onActivityResult received for requestCode $requestCode, not SCREEN_CAPTURE. Ignoring.")
        }
    }

    private fun setupContinuousCapture() {
        if (mediaProjection == null || imageProcessHandler == null) {
            Log.e(TAG, "setupContinuousCapture: MediaProjection is null or imageProcessHandler not ready.")
            val result = this.flutterResultForScreenCapture
            this.flutterResultForScreenCapture = null // Clear it
            mainHandler.post { result?.error("INTERNAL_ERROR_SETUP", "MediaProjection became null or handler not ready.", null) }
            cleanUpScreenCaptureResources(true)
            return
        }
        Log.d(TAG, "Setting up continuous screen capture.")

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // For Android R and above, currentWindowMetrics is preferred for active display area
            // However, for screen capture, full display real metrics are usually what's intended.
            windowManager.defaultDisplay.getRealMetrics(displayMetrics)
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealMetrics(displayMetrics)
        }

        val screenWidth = displayMetrics.widthPixels
        val screenHeight = displayMetrics.heightPixels
        val screenDensity = displayMetrics.densityDpi

        imageReader?.close() // Close existing reader if any
        imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2 /*maxImages*/)
        Log.d(TAG, "ImageReader created/recreated with size: $screenWidth x $screenHeight")

        virtualDisplay?.release() // Release existing display if any
        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ContinuousScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface,
            null, // VirtualDisplay.Callback (optional)
            imageProcessHandler // Handler for VirtualDisplay.Callback (if provided)
        )

        if (virtualDisplay == null) {
            Log.e(TAG, "Failed to create VirtualDisplay.")
            val result = this.flutterResultForScreenCapture
            this.flutterResultForScreenCapture = null // Clear it
            mainHandler.post { result?.error("VIRTUAL_DISPLAY_FAIL_CONTINUOUS", "Failed to create VirtualDisplay.", null) }
            cleanUpScreenCaptureResources(true)
            return
        }
        isCaptureSessionActive = true
        lastFrameProcessTimeMs = 0 // Reset throttling timer for new session
        Log.d(TAG, "VirtualDisplay for continuous capture created.")

        imageReader?.setOnImageAvailableListener({ reader ->
            // This listener now runs on imageProcessHandler (background thread)
            var image: Image? = null
            try {
                image = reader.acquireLatestImage()
                if (image == null) {
                    // Log.v(TAG, "OnImageAvailable: acquireLatestImage returned null.")
                    return@setOnImageAvailableListener
                }

                // Frame Throttling
                if (FRAME_PROCESS_INTERVAL_MS > 0) {
                    val currentTimeMs = System.currentTimeMillis()
                    if (currentTimeMs - lastFrameProcessTimeMs < FRAME_PROCESS_INTERVAL_MS) {
                        image.close() // MUST close the image even if not processing
                        // Log.v(TAG, "OnImageAvailable: Frame skipped due to throttling.")
                        return@setOnImageAvailableListener
                    }
                    lastFrameProcessTimeMs = currentTimeMs
                }

                val planes = image.planes
                val buffer = planes[0].buffer
                val pixelStride = planes[0].pixelStride
                val rowStride = planes[0].rowStride
                val rowPadding = rowStride - pixelStride * screenWidth // In bytes

                val paddedBitmap: Bitmap
                val finalBitmap: Bitmap

                val bitmapWidthWithPadding = screenWidth + rowPadding / pixelStride
                paddedBitmap = Bitmap.createBitmap(bitmapWidthWithPadding, screenHeight, Bitmap.Config.ARGB_8888)
                paddedBitmap.copyPixelsFromBuffer(buffer)

                if (rowPadding > 0 || bitmapWidthWithPadding > screenWidth) { // Check if actual width from buffer was larger
                    finalBitmap = Bitmap.createBitmap(paddedBitmap, 0, 0, screenWidth, screenHeight)
                    paddedBitmap.recycle()
                } else {
                    finalBitmap = paddedBitmap
                }

                reusableOutputStream.reset()
                finalBitmap.compress(Bitmap.CompressFormat.PNG, 90, reusableOutputStream) // Quality 90
                val newFrameBytes = reusableOutputStream.toByteArray()
                finalBitmap.recycle()

                this@MainActivity.latestFrameBytes = newFrameBytes // Update volatile variable
                // Log.d(TAG, "OnImageAvailable: New frame processed, size: ${newFrameBytes.size}")

                // If there's a pending Flutter result (e.g., first frame after setup, or waiting for next), fulfill it.
                val pendingResult = this@MainActivity.flutterResultForScreenCapture
                if (pendingResult != null) {
                    Log.d(TAG, "OnImageAvailable: Fulfilling pending Flutter request on main thread.")
                    this@MainActivity.flutterResultForScreenCapture = null // Clear before posting
                    mainHandler.post {
                        pendingResult.success(newFrameBytes.clone()) // Send a clone
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Exception in OnImageAvailableListener: ${e.message}", e)
                // Consider more robust error handling, e.g., stopping capture on repeated errors.
            } finally {
                image?.close() // CRUCIAL: Always close the image in a finally block
            }
        }, imageProcessHandler) // Use background handler
    }

    private fun cleanUpScreenCaptureResources(stopServiceAlso: Boolean) {
        Log.d(TAG, "cleanUpScreenCaptureResources called. Stop service: $stopServiceAlso, Active: $isCaptureSessionActive")
        if (!isCaptureSessionActive && mediaProjection == null && virtualDisplay == null && imageReader == null) {
            Log.d(TAG, "cleanUpScreenCaptureResources: Nothing to clean or already cleaned.")
            // Still ensure thread is stopped if it exists
             if (imageProcessThread != null) {
                imageProcessHandler?.removeCallbacksAndMessages(null)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
                    imageProcessThread?.quitSafely()
                } else {
                    imageProcessThread?.quit()
                }
                imageProcessHandler = null
                imageProcessThread = null
                Log.d(TAG, "ImageProcessingThread explicitly stopped during cleanup of inactive session.")
            }
            if (stopServiceAlso) {
                 Log.d(TAG, "Requesting ScreenCaptureService to stop (from inactive cleanup).")
                 ScreenCaptureService.stopService(this@MainActivity)
            }
            return
        }

        isCaptureSessionActive = false // Mark as inactive first
        latestFrameBytes = null

        try {
            virtualDisplay?.release()
            Log.d(TAG, "VirtualDisplay released.")
        } catch (e: Exception) {
            Log.e(TAG, "Exception releasing VirtualDisplay: ${e.message}", e)
        } finally {
            virtualDisplay = null
        }

        try {
            imageReader?.setOnImageAvailableListener(null, null) // Remove listener first
            imageReader?.close()
            Log.d(TAG, "ImageReader closed.")
        } catch (e: Exception) {
            Log.e(TAG, "Exception closing ImageReader: ${e.message}", e)
        } finally {
            imageReader = null
        }

        try {
            if (mediaProjection != null) {
                mediaProjection?.unregisterCallback(mediaProjectionCallback)
                mediaProjection?.stop()
                Log.d(TAG, "MediaProjection explicitly stopped.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Exception stopping MediaProjection: ${e.message}", e)
        } finally {
            mediaProjection = null
        }

        // Clean up background thread
        imageProcessHandler?.removeCallbacksAndMessages(null) // Clear pending processing tasks
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2) {
            imageProcessThread?.quitSafely()
        } else {
            imageProcessThread?.quit()
        }
        imageProcessHandler = null
        imageProcessThread = null
        Log.d(TAG, "ImageProcessingThread stopped.")

        val pendingResult = this.flutterResultForScreenCapture
        if (pendingResult != null) {
            Log.w(TAG, "flutterResultForScreenCapture was not null during final cleanup. Notifying error on main thread.")
            this.flutterResultForScreenCapture = null // Clear before posting
            mainHandler.post {
                pendingResult.error("CAPTURE_CLEANED_UP", "Screen capture resources were cleaned up.", null)
            }
        }

        if (stopServiceAlso) {
            Log.d(TAG, "Requesting ScreenCaptureService to stop.")
            ScreenCaptureService.stopService(this@MainActivity)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "onDestroy called.")
        cleanUpScreenCaptureResources(true) // Ensure everything is stopped and service is requested to stop
        super.onDestroy()
    }
}
