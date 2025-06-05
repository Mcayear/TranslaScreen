package com.example.transla_screen;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.List;

import io.flutter.plugin.common.MethodChannel;

/**
 * 译文蒙版服务 - 在屏幕上显示翻译结果
 */
public class TranslationOverlayService extends Service {
    private static final String TAG = "TranslationOverlay";
    private static final String CHANNEL_ID = "TranslationOverlayChannel";
    private static final int NOTIFICATION_ID = 1002;
    
    private WindowManager windowManager;
    private View overlayView;
    private FrameLayout maskContainer;
    private static MethodChannel channel;
    private List<TranslationMaskItem> maskItems = new ArrayList<>();
    
    /**
     * 翻译项数据模型
     */
    public static class TranslationMaskItem {
        public Rect bbox;
        public String translatedText;
        public String originalText;
        
        public TranslationMaskItem(Rect bbox, String translatedText, String originalText) {
            this.bbox = bbox;
            this.translatedText = translatedText;
            this.originalText = originalText;
        }
    }
    
    // 设置Flutter MethodChannel以便通信
    public static void setMethodChannel(MethodChannel methodChannel) {
        channel = methodChannel;
    }
    
    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "译文蒙版服务创建");
        
        // 创建通知通道
        createNotificationChannel();
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification());
    }
    
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 检查悬浮窗权限
        if (!checkOverlayPermission()) {
            Log.e(TAG, "没有悬浮窗权限，译文蒙版无法显示");
            if (channel != null) {
                channel.invokeMethod("overlay_permission_denied", "无法显示译文蒙版：未获得悬浮窗权限");
            }
            Toast.makeText(this, "无法显示译文蒙版，请允许悬浮窗权限", Toast.LENGTH_LONG).show();
            stopSelf();
            return START_NOT_STICKY;
        }
        
        if (intent != null && intent.hasExtra("translation_data")) {
            String translationData = intent.getStringExtra("translation_data");
            try {
                parseTranslationData(translationData);
            } catch (JSONException e) {
                Log.e(TAG, "解析翻译数据失败", e);
                if (channel != null) {
                    channel.invokeMethod("overlay_error", "解析翻译数据失败: " + e.getMessage());
                }
            }
        }
        
        if (overlayView == null) {
            try {
                createOverlayView();
            } catch (Exception e) {
                Log.e(TAG, "创建译文蒙版失败: " + e.getMessage(), e);
                if (channel != null) {
                    channel.invokeMethod("overlay_error", e.getMessage());
                }
                stopSelf();
                return START_NOT_STICKY;
            }
        } else {
            updateOverlayView();
        }
        
        return START_NOT_STICKY;
    }
    
    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
    
    /**
     * 创建通知通道（Android 8.0及以上需要）
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "译文蒙版服务",
                NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("用于保持译文蒙版显示");
            channel.enableLights(false);
            channel.enableVibration(false);
            
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }
    
    /**
     * 创建前台服务所需的通知
     */
    private Notification createNotification() {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        );
        
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("TranslaScreen译文显示")
            .setContentText("译文蒙版服务运行中")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pendingIntent);
            
        return builder.build();
    }
    
    /**
     * 检查是否有悬浮窗权限
     */
    private boolean checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(this);
        }
        return true; // 旧版本Android默认允许
    }
    
    /**
     * 解析翻译数据
     */
    private void parseTranslationData(String data) throws JSONException {
        maskItems.clear();
        
        JSONObject jsonObject = new JSONObject(data);
        if (jsonObject.has("items") && jsonObject.get("items") instanceof JSONArray) {
            JSONArray itemsArray = jsonObject.getJSONArray("items");
            for (int i = 0; i < itemsArray.length(); i++) {
                JSONObject item = itemsArray.getJSONObject(i);
                if (item.has("bbox") && item.has("translatedText")) {
                    JSONObject bbox = item.getJSONObject("bbox");
                    
                    int left = bbox.getInt("l");
                    int top = bbox.getInt("t");
                    int width = bbox.getInt("w");
                    int height = bbox.getInt("h");
                    
                    String translatedText = item.getString("translatedText");
                    String originalText = item.optString("originalText", "");
                    
                    Rect rect = new Rect(left, top, left + width, top + height);
                    TranslationMaskItem maskItem = new TranslationMaskItem(rect, translatedText, originalText);
                    maskItems.add(maskItem);
                }
            }
        }
        
        Log.d(TAG, "解析完成，共" + maskItems.size() + "个翻译项");
    }
    
    /**
     * 创建译文蒙版视图
     */
    private void createOverlayView() {
        // 获取WindowManager服务
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        
        // 创建主视图容器
        overlayView = new FrameLayout(this);
        
        // 设置半透明背景 - 改为完全透明
        overlayView.setBackgroundColor(0x00000000); // 完全透明背景
        
        // 创建译文容器
        maskContainer = new FrameLayout(this);
        ((FrameLayout) overlayView).addView(maskContainer, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
        ));
        
        // 创建关闭按钮
        Button closeButton = new Button(this);
        closeButton.setText("关闭遮罩(" + maskItems.size() + "项)");
        closeButton.setBackgroundColor(0xFFFF0000); // 红色
        closeButton.setTextColor(0xFFFFFFFF); // 白色文字
        closeButton.setPadding(30, 20, 30, 20);
        
        // 设置关闭按钮布局参数
        FrameLayout.LayoutParams buttonParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
        );
        buttonParams.gravity = Gravity.BOTTOM | Gravity.END;
        buttonParams.bottomMargin = 100; // 增加底部边距，避免被导航栏遮挡
        buttonParams.rightMargin = 50;
        
        // 添加关闭按钮
        ((FrameLayout) overlayView).addView(closeButton, buttonParams);
        
        // 设置关闭按钮点击事件
        closeButton.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                closeOverlay();
            }
        });
        
        // 设置WindowManager参数
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                getWindowLayoutType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE |
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN |
                        WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS |
                        WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.TRANSLUCENT
        );
        
        // 确保覆盖状态栏和导航栏
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            params.layoutInDisplayCutoutMode = 
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        }
        
        try {
            // 添加到窗口管理器
            windowManager.addView(overlayView, params);
            
            // 更新译文显示
            updateMaskItems();
        } catch (Exception e) {
            Log.e(TAG, "添加译文蒙版失败", e);
            throw e; // 重新抛出异常，让上层处理
        }
    }
    
    /**
     * 更新译文视图
     */
    private void updateOverlayView() {
        // 清除旧的译文视图
        maskContainer.removeAllViews();
        
        // 更新译文显示
        updateMaskItems();
    }
    
    /**
     * 更新译文项显示
     */
    private void updateMaskItems() {
        for (TranslationMaskItem item : maskItems) {
            try {
                // 创建译文显示视图
                FrameLayout maskItemView = new FrameLayout(this);
                // 降低背景透明度，从70%改为40%透明度
                maskItemView.setBackgroundColor(0x66000000); // 40%透明度黑色
                
                // 移除边框，避免文本被边框遮挡
                // maskItemView.setForeground(ContextCompat.getDrawable(this, android.R.drawable.dialog_holo_dark_frame));
                
                // 创建译文文本
                TextView textView = new TextView(this);
                textView.setText(item.translatedText);
                textView.setTextColor(0xFFFFFFFF); // 白色
                // 调整文本大小，使其更易读
                textView.setTextSize(Math.max(14, item.bbox.height() * 0.2f));
                textView.setGravity(Gravity.CENTER);
                // 添加文本阴影，提高可读性
                textView.setShadowLayer(3.0f, 1.0f, 1.0f, 0xFF000000);
                
                // 添加小边距，确保文本不贴边。边距会导致文本偏移
                // textView.setPadding(8, 4, 8, 4);
                
                // 添加文本到视图
                maskItemView.addView(textView, new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        ViewGroup.LayoutParams.WRAP_CONTENT,
                        Gravity.CENTER
                ));
                
                // 设置位置和大小
                FrameLayout.LayoutParams itemParams = new FrameLayout.LayoutParams(
                        item.bbox.width(),
                        item.bbox.height()
                );
                itemParams.leftMargin = item.bbox.left;
                itemParams.topMargin = item.bbox.top;
                
                // 添加到容器
                maskContainer.addView(maskItemView, itemParams);
            } catch (Exception e) {
                Log.e(TAG, "添加译文项失败: " + e.getMessage(), e);
            }
        }
    }
    
    /**
     * 关闭译文蒙版
     */
    private void closeOverlay() {
        // 通知Flutter端蒙版已关闭
        if (channel != null) {
            channel.invokeMethod("mask_closed", null);
        }
        
        // 停止服务
        stopSelf();
    }
    
    /**
     * 获取窗口类型
     */
    private int getWindowLayoutType() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY;
        } else {
            return WindowManager.LayoutParams.TYPE_PHONE;
        }
    }
    
    @Override
    public void onDestroy() {
        super.onDestroy();
        if (overlayView != null && windowManager != null) {
            try {
                windowManager.removeView(overlayView);
            } catch (Exception e) {
                Log.e(TAG, "移除译文蒙版失败", e);
            }
            overlayView = null;
        }
        
        // 停止前台服务
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }
    }
} 