package com.example.transla_screen;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.animation.Animation;
import android.view.animation.AnimationUtils;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;
import androidx.core.content.ContextCompat;

import io.flutter.plugin.common.MethodChannel;

/**
 * 悬浮球服务 - 实现Android原生悬浮窗功能
 */
public class FloatingBubbleService extends Service {
    private static final String TAG = "FloatingBubbleService";
    private static final String CHANNEL_ID = "FloatingBubbleChannel";
    private static final int NOTIFICATION_ID = 1001;
    private static final int BUBBLE_SIZE_DP = 56; // 悬浮球大小，以dp为单位
    
    private WindowManager windowManager;
    private View floatingView;
    private View expandedView;
    private boolean isExpanded = false;
    private static MethodChannel channel;
    
    // 设置Flutter MethodChannel以便通信
    public static void setMethodChannel(MethodChannel methodChannel) {
        channel = methodChannel;
    }
    
    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "悬浮球服务创建");
        // 创建通知通道（Android 8.0及以上需要）
        createNotificationChannel();
        
        // 启动前台服务
        startForeground(NOTIFICATION_ID, createNotification());
    }
    
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 首先检查权限
        if (!checkOverlayPermission()) {
            Log.e(TAG, "没有悬浮窗权限，服务无法启动");
            // 通知Flutter端权限被拒绝
            if (channel != null) {
                final String errorMsg = "悬浮窗权限被拒绝，请在系统设置中授予权限";
                channel.invokeMethod("overlay_permission_denied", errorMsg);
            }
            Toast.makeText(this, "无法创建悬浮窗，请在设置中授予权限", Toast.LENGTH_LONG).show();
            stopSelf();
            return START_NOT_STICKY;
        }
        
        if (floatingView == null) {
            try {
                createFloatingBubble();
            } catch (Exception e) {
                Log.e(TAG, "创建悬浮球时发生错误: " + e.getMessage(), e);
                // 通知Flutter端发生错误
                if (channel != null) {
                    channel.invokeMethod("overlay_error", e.getMessage());
                }
                stopSelf();
                return START_NOT_STICKY;
            }
        }
        return START_STICKY;
    }
    
    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    /**
     * 创建通知通道，适用于Android 8.0及以上
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "悬浮翻译服务",
                NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("用于保持悬浮球服务运行");
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
            .setContentTitle("TranslaScreen翻译服务")
            .setContentText("悬浮球服务正在运行中")
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
     * 打开系统设置请求悬浮窗权限
     * 此方法需要在Activity中调用，这里只是提供参考
     */
    public static Intent getOverlayPermissionIntent(Context context) {
        Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:" + context.getPackageName()));
        return intent;
    }
    
    /**
     * 将dp值转换为像素值
     */
    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private void createFloatingBubble() {
        // 获取WindowManager服务
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        
        // 创建悬浮球视图容器
        floatingView = new FrameLayout(this);
        int bubbleSizePx = dpToPx(BUBBLE_SIZE_DP);
        
        // 创建圆形背景
        GradientDrawable circleDrawable = new GradientDrawable();
        circleDrawable.setShape(GradientDrawable.OVAL);
        circleDrawable.setColor(Color.parseColor("#AA9C27B0")); // 半透明紫色
        
        // 创建圆形容器
        FrameLayout circleContainer = new FrameLayout(this);
        circleContainer.setBackground(circleDrawable);
        FrameLayout.LayoutParams circleParams = new FrameLayout.LayoutParams(
                bubbleSizePx,
                bubbleSizePx
        );
        
        // 添加翻译图标
        ImageView iconView = new ImageView(this);
        iconView.setImageResource(android.R.drawable.ic_menu_edit);
        iconView.setColorFilter(Color.WHITE);
        FrameLayout.LayoutParams iconParams = new FrameLayout.LayoutParams(
                dpToPx(24),
                dpToPx(24),
                Gravity.CENTER
        );
        
        circleContainer.addView(iconView, iconParams);
        ((FrameLayout) floatingView).addView(circleContainer, circleParams);
        
        // 设置悬浮球阴影效果
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            floatingView.setElevation(dpToPx(4));
        }
        
        // 设置WindowManager参数
        final WindowManager.LayoutParams layoutParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                getWindowLayoutType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
        );
        
        // 初始位置 - 右边中间位置
        layoutParams.gravity = Gravity.END | Gravity.CENTER_VERTICAL;
        layoutParams.x = dpToPx(8);
        layoutParams.y = 0;
        
        try {
            // 添加到窗口管理器
            windowManager.addView(floatingView, layoutParams);
            
            // 设置触摸监听
            setupTouchListener(layoutParams);
        } catch (Exception e) {
            Log.e(TAG, "添加悬浮窗失败", e);
            throw e; // 重新抛出异常，让上层处理
        }
    }
    
    private int getWindowLayoutType() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY;
        } else {
            return WindowManager.LayoutParams.TYPE_PHONE;
        }
    }
    
    private void setupTouchListener(final WindowManager.LayoutParams params) {
        floatingView.setOnTouchListener(new View.OnTouchListener() {
            private int initialX;
            private int initialY;
            private float initialTouchX;
            private float initialTouchY;
            private long touchStartTime;
            private static final long CLICK_TIME_THRESHOLD = 200;
            private static final float DRAG_TOLERANCE = 10f; // 拖动阈值，防止轻微触碰被识别为拖动
            
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        // 记录初始位置
                        initialX = params.x;
                        initialY = params.y;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        touchStartTime = System.currentTimeMillis();
                        return true;
                        
                    case MotionEvent.ACTION_MOVE:
                        // 计算移动距离
                        float deltaX = event.getRawX() - initialTouchX;
                        float deltaY = event.getRawY() - initialTouchY;
                        
                        // 确认是否为拖动意图(排除轻微触碰)
                        if (Math.abs(deltaX) > DRAG_TOLERANCE || Math.abs(deltaY) > DRAG_TOLERANCE) {
                            // 修正拖动方向计算
                            // 注意：params.x在END对齐时，方向是相反的
                            if ((params.gravity & Gravity.END) != 0) {
                                // 对于END对齐，x增大时悬浮球应该向左移动（x值减小）
                                params.x = initialX - (int) deltaX;
                            } else {
                                // 对于START或其他对齐，保持正常方向
                                params.x = initialX + (int) deltaX;
                            }
                            // Y方向保持不变
                            params.y = initialY + (int) deltaY;
                            
                            // 更新悬浮球位置
                            windowManager.updateViewLayout(floatingView, params);
                            
                            // 如果菜单展开，需要重新隐藏并显示在新位置
                            if (isExpanded && expandedView != null) {
                                // 当拖动时隐藏菜单
                                if (expandedView.getVisibility() == View.VISIBLE) {
                                    expandedView.setVisibility(View.GONE);
                                }
                            }
                        }
                        return true;
                        
                    case MotionEvent.ACTION_UP:
                        // 如果是点击(不是拖动)
                        long touchDuration = System.currentTimeMillis() - touchStartTime;
                        float totalDragDistance = Math.abs(event.getRawX() - initialTouchX) + 
                                                Math.abs(event.getRawY() - initialTouchY);
                        
                        Log.d(TAG, "触摸结束: 时长=" + touchDuration + "ms, 距离=" + totalDragDistance + ", isExpanded=" + isExpanded);
                                                
                        if (touchDuration < CLICK_TIME_THRESHOLD && totalDragDistance < DRAG_TOLERANCE) {
                            Log.d(TAG, "检测到点击行为");
                            if (!isExpanded || (expandedView != null && expandedView.getVisibility() != View.VISIBLE)) {
                                Log.d(TAG, "展开菜单");
                                showBubbleMenu();
                            } else {
                                Log.d(TAG, "隐藏菜单");
                                hideBubbleMenu();
                            }
                        } else if (isExpanded && expandedView != null && expandedView.getVisibility() != View.VISIBLE) {
                            // 如果是拖动结束且菜单是展开状态但不可见，重新显示菜单在新位置
                            windowManager.removeView(expandedView);
                            expandedView = null;
                            isExpanded = false;
                            showBubbleMenu();
                        }
                        return true;
                }
                return false;
            }
        });
        
        // 长按监听 - 直接全屏翻译
        floatingView.setOnLongClickListener(new View.OnLongClickListener() {
            @Override
            public boolean onLongClick(View v) {
                // 添加震动反馈
                v.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS);
                
                // 执行全屏翻译
                if (channel != null) {
                    channel.invokeMethod("translate_fullscreen", null);
                }
                return true;
            }
        });
    }
    
    private void showBubbleMenu() {
        isExpanded = true;
        Log.d(TAG, "显示菜单，当前状态: " + isExpanded);
        
        // 创建环形菜单
        if (expandedView == null) {
            Log.d(TAG, "创建新菜单...");
            
            // 创建菜单容器 - 使用固定大小确保可见
            expandedView = new FrameLayout(this);
            
            // 创建菜单项
            addMenuItems();
            
            // 设置WindowManager参数 - 使用固定大小确保全部显示
            WindowManager.LayoutParams menuParams = new WindowManager.LayoutParams(
                    dpToPx(200),  // 固定宽度
                    dpToPx(200),  // 固定高度
                    getWindowLayoutType(),
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT
            );
            
            // 菜单位置 - 使用与悬浮球相同的对齐方式
            WindowManager.LayoutParams bubbleParams = (WindowManager.LayoutParams) floatingView.getLayoutParams();
            menuParams.gravity = Gravity.TOP | Gravity.START; // 使用绝对定位
            
            // 获取悬浮球在屏幕上的位置
            int[] location = new int[2];
            floatingView.getLocationOnScreen(location);
            
            // 菜单位置居中于悬浮球
            menuParams.x = location[0] - (dpToPx(200) / 2) + (dpToPx(BUBBLE_SIZE_DP) / 2);
            menuParams.y = location[1] - (dpToPx(200) / 2) + (dpToPx(BUBBLE_SIZE_DP) / 2);
            
            Log.d(TAG, "菜单位置: x=" + menuParams.x + ", y=" + menuParams.y);
            
            try {
                // 添加到窗口管理器
                windowManager.addView(expandedView, menuParams);
                
                // 执行显示动画
                for (int i = 0; i < ((FrameLayout) expandedView).getChildCount(); i++) {
                    View item = ((FrameLayout) expandedView).getChildAt(i);
                    item.setAlpha(0f);
                    item.setScaleX(0.5f);
                    item.setScaleY(0.5f);
                    item.animate()
                        .alpha(1f)
                        .scaleX(1f)
                        .scaleY(1f)
                        .setDuration(200)
                        .setStartDelay(i * 50)
                        .start();
                }
                
                Log.d(TAG, "菜单创建完成，子项数量: " + ((FrameLayout) expandedView).getChildCount());
            } catch (Exception e) {
                Log.e(TAG, "添加菜单窗口失败", e);
                isExpanded = false;
                expandedView = null;
                // 通知Flutter端发生错误
                if (channel != null) {
                    channel.invokeMethod("overlay_menu_error", e.getMessage());
                }
            }
        } else {
            Log.d(TAG, "菜单已存在，设置为可见");
            expandedView.setVisibility(View.VISIBLE);
            // 执行显示动画
            for (int i = 0; i < ((FrameLayout) expandedView).getChildCount(); i++) {
                View item = ((FrameLayout) expandedView).getChildAt(i);
                item.setAlpha(0f);
                item.setScaleX(0.5f);
                item.setScaleY(0.5f);
                item.animate()
                    .alpha(1f)
                    .scaleX(1f)
                    .scaleY(1f)
                    .setDuration(200)
                    .setStartDelay(i * 50)
                    .start();
            }
        }
    }
    
    private void addMenuItems() {
        // 增加日志
        Log.d(TAG, "添加菜单项...");
        
        // 添加全屏翻译菜单项 - 固定在悬浮球的下方
        addMenuItem(
            android.R.drawable.ic_menu_camera,
            "全屏翻译",
            "translate_fullscreen",
            0,       // 水平居中
            dpToPx(60), // 下方
            Color.parseColor("#4CAF50") // 绿色
        );
        
        // 添加选区翻译菜单项 - 固定在左侧
        addMenuItem(
            android.R.drawable.ic_menu_crop,
            "选区翻译",
            "start_area_selection",
            -dpToPx(60), // 左侧
            0,          // 同一水平线
            Color.parseColor("#2196F3") // 蓝色
        );
    }
    
    private void addMenuItem(int iconRes, String text, final String action, int xOffset, int yOffset, int color) {
        // 创建圆形菜单项
        FrameLayout menuItem = new FrameLayout(this);
        
        // 设置圆形背景
        GradientDrawable itemBg = new GradientDrawable();
        itemBg.setShape(GradientDrawable.OVAL);
        itemBg.setColor(color);
        menuItem.setBackground(itemBg);
        
        // 添加图标
        ImageView icon = new ImageView(this);
        icon.setImageResource(iconRes);
        icon.setColorFilter(Color.WHITE);
        
        // 图标居中
        FrameLayout.LayoutParams iconParams = new FrameLayout.LayoutParams(
                dpToPx(24), dpToPx(24), Gravity.CENTER);
        menuItem.addView(icon, iconParams);
        
        // 设置菜单项大小和位置
        FrameLayout.LayoutParams itemParams = new FrameLayout.LayoutParams(
                dpToPx(48), dpToPx(48));
        
        // 相对于菜单中心的位置（布局中心即悬浮球位置）
        itemParams.gravity = Gravity.CENTER;
        itemParams.leftMargin = xOffset;
        itemParams.topMargin = yOffset;
        
        // 添加文本标签
        TextView label = new TextView(this);
        label.setText(text);
        label.setTextColor(Color.WHITE);
        label.setPadding(dpToPx(8), dpToPx(4), dpToPx(8), dpToPx(4));
        label.setBackgroundColor(Color.parseColor("#80000000"));
        
        // 文本标签位置
        FrameLayout.LayoutParams labelParams = new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT);
        labelParams.gravity = Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM;
        labelParams.bottomMargin = -dpToPx(24);
        
        menuItem.addView(label, labelParams);
        
        // 点击监听
        menuItem.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                // 添加点击效果
                v.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
                
                // 调用对应功能
                if (channel != null) {
                    channel.invokeMethod(action, null);
                }
                
                // 隐藏菜单
                hideBubbleMenu();
            }
        });
        
        // 添加到菜单容器
        ((FrameLayout) expandedView).addView(menuItem, itemParams);
    }
    
    private void hideBubbleMenu() {
        Log.d(TAG, "隐藏菜单，当前状态: " + isExpanded);
        if (expandedView != null) {
            isExpanded = false; // 先设置状态为非展开
            
            // 执行隐藏动画
            final int childCount = ((FrameLayout) expandedView).getChildCount();
            Log.d(TAG, "准备隐藏 " + childCount + " 个菜单项");
            
            if (childCount == 0) {
                // 如果没有子视图，直接隐藏
                expandedView.setVisibility(View.GONE);
                Log.d(TAG, "菜单无子项，直接隐藏");
                return;
            }
            
            for (int i = 0; i < childCount; i++) {
                final View item = ((FrameLayout) expandedView).getChildAt(i);
                final int index = i;
                
                item.animate()
                    .alpha(0f)
                    .scaleX(0.5f)
                    .scaleY(0.5f)
                    .setDuration(150)
                    .setStartDelay(index * 30)
                    .withEndAction(new Runnable() {
                        @Override
                        public void run() {
                            Log.d(TAG, "菜单项 " + index + " 动画完成");
                            if (index == childCount - 1) {
                                // 最后一个动画完成后隐藏整个菜单
                                expandedView.setVisibility(View.GONE);
                                Log.d(TAG, "所有菜单项动画完成，菜单已隐藏");
                            }
                        }
                    })
                    .start();
            }
        } else {
            Log.d(TAG, "菜单不存在，无需隐藏");
        }
    }
    
    @Override
    public void onDestroy() {
        super.onDestroy();
        if (floatingView != null && windowManager != null) {
            try {
                windowManager.removeView(floatingView);
            } catch (Exception e) {
                Log.e(TAG, "移除悬浮窗时出错", e);
            }
            floatingView = null;
        }
        
        if (expandedView != null && windowManager != null) {
            try {
                windowManager.removeView(expandedView);
            } catch (Exception e) {
                Log.e(TAG, "移除菜单窗口时出错", e);
            }
            expandedView = null;
        }

        // 停止前台服务
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }
    }
} 