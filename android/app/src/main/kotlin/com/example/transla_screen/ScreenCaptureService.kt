package com.example.transla_screen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import android.util.Log

class ScreenCaptureService : Service() {

    companion object {
        const val ACTION_START = "com.example.transla_screen.service.ACTION_START"
        const val ACTION_STOP = "com.example.transla_screen.service.ACTION_STOP"
        private const val NOTIFICATION_ID = 123789 // Unique notification ID
        private const val CHANNEL_ID = "ScreenCaptureServiceChannel"
        private const val TAG = "ScreenCaptureService"

        fun startService(context: Context) {
            try {
                val intent = Intent(context, ScreenCaptureService::class.java).apply {
                    action = ACTION_START
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                Log.d(TAG, "ScreenCaptureService start command sent.")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting ScreenCaptureService: \${e.message}", e)
            }
        }

        fun stopService(context: Context) {
            try {
                val intent = Intent(context, ScreenCaptureService::class.java).apply {
                    action = ACTION_STOP
                }
                // Always use startService to send an action to an already running service.
                // The service will then call stopSelf() or stopForeground().
                context.startService(intent)
                Log.d(TAG, "ScreenCaptureService stop command sent.")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending stop command to ScreenCaptureService: \${e.message}", e)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        Log.d(TAG, "ScreenCaptureService onCreate")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand received action: \${intent?.action}")
        if (intent?.action == ACTION_START) {
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle("TranslaScreen Active")
                .setContentText("Screen capture is active for translation.")
                .setSmallIcon(android.R.drawable.ic_media_play) // Placeholder icon, replace with your app's icon
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setOngoing(true)
                .build()

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                Log.d(TAG, "Service started in foreground.")
            } catch (e: Exception) {
                Log.e(TAG, "Error calling startForeground: \${e.message}", e)
                // Fallback or cleanup if startForeground fails
                stopSelf() // Stop the service if it cannot run in foreground as required
            }

        } else if (intent?.action == ACTION_STOP) {
            Log.d(TAG, "Stopping foreground service and self.")
            stopForeground(true) // true = remove notification
            stopSelf()
        }
        return START_NOT_STICKY // If killed, do not restart unless explicitly told.
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null // We don't provide binding, so return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Screen Capture Service", // User visible name
                NotificationManager.IMPORTANCE_LOW // Low importance for background tasks
            ).apply {
                description = "Channel for Screen Capture foreground service."
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
            Log.d(TAG, "Notification channel created.")
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "ScreenCaptureService onDestroy")
        super.onDestroy()
    }
} 