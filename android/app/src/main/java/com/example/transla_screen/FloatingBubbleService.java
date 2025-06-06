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
import android.os.Handler;
import android.os.IBinder;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

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
    private WindowManager.LayoutParams bubbleParams; // 保存悬浮球的布局参数
    private WindowManager.LayoutParams menuParams;   // 保存菜单的布局参数
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
        // 获取WindowManager服务
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
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

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_edit)
                .setContentTitle("TranslaScreen翻译服务")
                .setContentText("悬浮球服务正在运行中")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setContentIntent(pendingIntent)
                .build();
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
     * 将dp值转换为像素值
     */
    private int dpToPx(int dp) {
        float density = getResources().getDisplayMetrics().density;
        return Math.round(dp * density);
    }

    private int getWindowLayoutType() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
    }

    private void createFloatingBubble() {
        floatingView = new FrameLayout(this);
        int bubbleSizePx = dpToPx(BUBBLE_SIZE_DP);

        GradientDrawable circleDrawable = new GradientDrawable();
        circleDrawable.setShape(GradientDrawable.OVAL);
        circleDrawable.setColor(Color.parseColor("#AA9C27B0")); // 半透明紫色

        FrameLayout circleContainer = new FrameLayout(this);
        circleContainer.setBackground(circleDrawable);
        FrameLayout.LayoutParams circleParams = new FrameLayout.LayoutParams(bubbleSizePx, bubbleSizePx);

        ImageView iconView = new ImageView(this);
        iconView.setImageResource(android.R.drawable.ic_menu_edit);
        iconView.setColorFilter(Color.WHITE);
        FrameLayout.LayoutParams iconParams = new FrameLayout.LayoutParams(dpToPx(24), dpToPx(24), Gravity.CENTER);

        circleContainer.addView(iconView, iconParams);
        ((FrameLayout) floatingView).addView(circleContainer, circleParams);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            floatingView.setElevation(dpToPx(4));
        }

        bubbleParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                getWindowLayoutType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
        );

        bubbleParams.gravity = Gravity.END | Gravity.CENTER_VERTICAL;
        bubbleParams.x = dpToPx(8);
        bubbleParams.y = 0;

        windowManager.addView(floatingView, bubbleParams);

        // 定义长按操作，并将其与单击操作一同传递给触摸监听器
        Runnable onLongClickAction = () -> {
            floatingView.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS);
            if (channel != null) {
                channel.invokeMethod("translate_fullscreen", null);
            }
        };
        floatingView.setOnTouchListener(new DraggableTouchListener(bubbleParams, this::showBubbleMenu, onLongClickAction));
    }


    private void showBubbleMenu() {
        if (isExpanded || expandedView != null) {
            return;
        }
        isExpanded = true;
        Log.d(TAG, "展开菜单");
        floatingView.setVisibility(View.GONE);

        LinearLayout menuLayout = new LinearLayout(this);
        menuLayout.setOrientation(LinearLayout.VERTICAL);
        int padding = dpToPx(8);
        menuLayout.setPadding(padding, padding, padding, padding);
        menuLayout.setGravity(Gravity.CENTER_HORIZONTAL);

        GradientDrawable background = new GradientDrawable();
        background.setShape(GradientDrawable.RECTANGLE);
        background.setColor(Color.parseColor("#E6D3E8FD"));
        background.setCornerRadius(dpToPx(28));
        menuLayout.setBackground(background);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            menuLayout.setElevation(dpToPx(4));
        }

        expandedView = menuLayout;

        if (menuParams == null) {
            menuParams = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    getWindowLayoutType(),
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT
            );
            menuParams.gravity = bubbleParams.gravity;
            menuParams.x = bubbleParams.x;
            menuParams.y = bubbleParams.y;
        }

        // ** 关键改动：先创建拖动监听器，再把它传递给按钮创建函数 **
        DraggableTouchListener menuDragger = new DraggableTouchListener(menuParams, null, null);
        expandedView.setOnTouchListener(menuDragger);

        addMenuItemsToLayout(menuLayout, menuDragger);

        windowManager.addView(expandedView, menuParams);

        expandedView.setAlpha(0f);
        expandedView.animate().alpha(1f).setDuration(200).start();
    }

    private void hideBubbleMenu() {
        if (!isExpanded || expandedView == null) {
            return;
        }
        Log.d(TAG, "隐藏菜单");

        isExpanded = false;
        final View viewToRemove = expandedView;
        expandedView = null;

        viewToRemove.animate()
                .alpha(0f)
                .setDuration(200)
                .withEndAction(() -> {
                    if (viewToRemove.isAttachedToWindow()) {
                        windowManager.removeView(viewToRemove);
                    }
                })
                .start();

        if (floatingView != null) {
            floatingView.setVisibility(View.VISIBLE);
            floatingView.setAlpha(0f);
            floatingView.animate().alpha(1f).setDuration(200).start();
        }
    }

    /**
     * 创建并添加所有菜单项到布局中
     * @param menuLayout 菜单的父布局
     * @param menuDragger 父布局的拖动监听器，用于传递给可拖动的子按钮
     */
    private void addMenuItemsToLayout(LinearLayout menuLayout, View.OnTouchListener menuDragger) {
        // 1. 折叠/翻译按钮 (A文) - 将父容器的拖动监听器传给它
        menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_sort_by_size, "collapse", true, menuDragger, menuLayout));

        // 其他按钮不需要拖动功能，所以传 null
        menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_camera, "translate_fullscreen", false, null, null));
        menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_crop, "start_area_selection", false, null, null));
        // menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_search, "ocr_text", false, null, null));
        // menuLayout.addView(createMenuButton(android.R.drawable.ic_lock_lock, "lock_position", false, null, null));
        // menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_edit, "input_text", false, null, null));
        // menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_more, "more_options", false, null, null));
    }

    /**
     * 创建单个菜单按钮 (ImageView)
     * @param dragListener 如果此按钮需要能拖动整个菜单，则传入父容器的拖动监听器
     * @param parentView   父容器的视图实例，仅当 dragListener 不为 null 时需要
     */
    private ImageView createMenuButton(int iconResId, final String action, boolean isCollapseButton, @Nullable View.OnTouchListener dragListener, @Nullable View parentView) {
        ImageView button = new ImageView(this);
        button.setImageResource(iconResId);
        int padding = dpToPx(12);
        button.setPadding(padding, padding, padding, padding);

        if (isCollapseButton) {
            // 折叠按钮样式
            GradientDrawable circleBg = new GradientDrawable();
            circleBg.setShape(GradientDrawable.OVAL);
            circleBg.setColor(Color.parseColor("#2196F3"));
            button.setBackground(circleBg);
            button.setColorFilter(Color.WHITE);

            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dpToPx(48), dpToPx(48));
            params.setMargins(0, 0, 0, dpToPx(12));
            button.setLayoutParams(params);
        } else {
            // 普通按钮样式
            button.setBackgroundColor(Color.TRANSPARENT);
            button.setColorFilter(Color.parseColor("#555555"));

            LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dpToPx(48), dpToPx(48));
            params.setMargins(0, dpToPx(4), 0, dpToPx(4));
            button.setLayoutParams(params);
        }

        // ** 关键改动：根据按钮类型设置不同的监听器 **
        if (isCollapseButton && dragListener != null && parentView != null) {
            // 这个按钮既要能点击，也要能拖动整个菜单
            button.setOnTouchListener(new DraggableButtonTouchListener(v -> hideBubbleMenu(), dragListener, parentView));
        } else {
            // 其他按钮只有点击功能
            button.setOnClickListener(v -> {
                v.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
                handleButtonClick(action);
            });
        }
        return button;
    }

    private void handleButtonClick(String action) {
        switch (action) {
            case "collapse":
                // 此处不再处理，由DraggableButtonTouchListener处理
                break;
            case "start_area_selection":
            case "translate_fullscreen":
                if (channel != null) {
                    channel.invokeMethod(action, null);
                }
                hideBubbleMenu();
                break;
            default:
                Toast.makeText(FloatingBubbleService.this, "功能待实现: " + action, Toast.LENGTH_SHORT).show();
                hideBubbleMenu();
                break;
        }
    }


    @Override
    public void onDestroy() {
        super.onDestroy();
        if (floatingView != null && floatingView.isAttachedToWindow()) {
            try {
                windowManager.removeView(floatingView);
            } catch (Exception e) {
                Log.e(TAG, "移除悬浮窗时出错", e);
            }
        }
        floatingView = null;

        if (expandedView != null && expandedView.isAttachedToWindow()) {
            try {
                windowManager.removeView(expandedView);
            } catch (Exception e) {
                Log.e(TAG, "移除菜单窗口时出错", e);
            }
        }
        expandedView = null;
        stopForeground(true);
    }

    // =====================================================================================
    // 可重用的拖动监听器 (集成单击和长按逻辑)
    // =====================================================================================
    private class DraggableTouchListener implements View.OnTouchListener {
        private final WindowManager.LayoutParams params;
        private final Runnable onClickAction;
        private final Runnable onLongClickAction; // 新增：长按操作
        private int initialX;
        private int initialY;
        private float initialTouchX;
        private float initialTouchY;
        private long touchStartTime;

        private static final long CLICK_TIME_THRESHOLD = 200; // 单击时间阈值 (ms)
        private static final float DRAG_TOLERANCE = 10f;       // 判定为拖动的最小移动距离
        private static final int LONG_PRESS_TIMEOUT = 500;     // 判定为长按的超时时间 (ms)

        private final Handler longPressHandler = new Handler();
        private boolean longPressFired = false;
        private final Runnable longPressRunnable;

        public DraggableTouchListener(WindowManager.LayoutParams params, @Nullable Runnable onClickAction, @Nullable Runnable onLongClickAction) {
            this.params = params;
            this.onClickAction = onClickAction;
            this.onLongClickAction = onLongClickAction;
            this.longPressRunnable = () -> {
                longPressFired = true;
                if (this.onLongClickAction != null) {
                    this.onLongClickAction.run();
                }
            };
        }

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    initialX = params.x;
                    initialY = params.y;
                    initialTouchX = event.getRawX();
                    initialTouchY = event.getRawY();
                    touchStartTime = System.currentTimeMillis();
                    longPressFired = false;
                    // 启动长按计时器
                    longPressHandler.postDelayed(longPressRunnable, LONG_PRESS_TIMEOUT);
                    return true;

                case MotionEvent.ACTION_MOVE:
                    float deltaX = event.getRawX() - initialTouchX;
                    float deltaY = event.getRawY() - initialTouchY;

                    // 如果移动距离超过阈值，则视为拖动
                    if (Math.abs(deltaX) > DRAG_TOLERANCE || Math.abs(deltaY) > DRAG_TOLERANCE) {
                        // 是拖动，取消长按计时
                        longPressHandler.removeCallbacks(longPressRunnable);
                        // 更新视图位置
                        if ((params.gravity & Gravity.END) == Gravity.END) {
                            params.x = initialX - (int) deltaX;
                        } else {
                            params.x = initialX + (int) deltaX;
                        }
                        params.y = initialY + (int) deltaY;
                        windowManager.updateViewLayout(v, params);
                    }
                    return true;

                case MotionEvent.ACTION_UP:
                    // 手指抬起，取消长按计时
                    longPressHandler.removeCallbacks(longPressRunnable);

                    long touchDuration = System.currentTimeMillis() - touchStartTime;
                    float totalDragDistance = Math.abs(event.getRawX() - initialTouchX) + Math.abs(event.getRawY() - initialTouchY);

                    // 如果长按未触发，且满足单击条件（时间短，位移小），则执行单击
                    if (!longPressFired && onClickAction != null && touchDuration < CLICK_TIME_THRESHOLD && totalDragDistance < DRAG_TOLERANCE) {
                        onClickAction.run();
                    }
                    return true;
            }
            return false;
        }
    }

    // =====================================================================================
    // ** 新增：一个特殊的TouchListener，用于既能点击又能拖动父视图的按钮 **
    // =====================================================================================
    private static class DraggableButtonTouchListener implements View.OnTouchListener {
        private final View.OnClickListener clickListener;
        private final View.OnTouchListener dragListener;
        private final View parentView;

        private float initialTouchX;
        private float initialTouchY;
        private long touchStartTime;
        private static final long CLICK_TIME_THRESHOLD = 200;
        private static final float DRAG_TOLERANCE = 10f;


        public DraggableButtonTouchListener(@NonNull View.OnClickListener clickListener,
                                            @NonNull View.OnTouchListener dragListener,
                                            @NonNull View parentView) {
            this.clickListener = clickListener;
            this.dragListener = dragListener;
            this.parentView = parentView;
        }

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    initialTouchX = event.getRawX();
                    initialTouchY = event.getRawY();
                    touchStartTime = System.currentTimeMillis();
                    // 将事件传递给父视图的拖动监听器以初始化拖动
                    dragListener.onTouch(parentView, event);
                    return true;

                case MotionEvent.ACTION_MOVE:
                    // 持续将事件传递给父视图的拖动监听器以处理拖动
                    dragListener.onTouch(parentView, event);
                    return true;

                case MotionEvent.ACTION_UP:
                    long touchDuration = System.currentTimeMillis() - touchStartTime;
                    float totalDragDistance = Math.abs(event.getRawX() - initialTouchX) + Math.abs(event.getRawY() - initialTouchY);

                    // 判断是点击还是拖动结束
                    if (touchDuration < CLICK_TIME_THRESHOLD && totalDragDistance < DRAG_TOLERANCE) {
                        // 这是个点击事件
                        v.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
                        clickListener.onClick(v);
                    }
                    // 无论如何，都将UP事件传递给父视图的拖动监听器以完成拖动操作
                    dragListener.onTouch(parentView, event);
                    return true;
            }
            return false;
        }
    }
}