package com.example.transla_screen;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
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
 * 悬浮球服务 (FloatingBubbleService)
 *
 * 负责创建和管理一个可在其他应用上层显示的悬浮窗。该悬浮窗包含一个可拖动的悬浮球，
 * 点击后会展开一个功能菜单。此服务通过前台服务(Foreground Service)来保证其在后台的持续运行。
 *
 * 主要功能:
 * 1.  创建和显示一个可拖动的悬浮球。
 * 2.  响应用户的触摸操作：
 *     - 单击：展开功能菜单。
 *     - 长按：触发全屏翻译。
 *     - 拖动：移动悬浮球位置。
 * 3.  显示一个可展开、可拖动的功能菜单，菜单中的按钮用于触发不同功能。
 * 4.  通过 MethodChannel 与 Flutter 端进行双向通信，以调用 Flutter 功能或将原生事件通知给 Flutter。
 * 5.  处理悬浮窗权限检查。
 * 6.  通过启动前台服务和创建通知渠道来兼容新版 Android系统。
 */
public class FloatingBubbleService extends Service {
    // =====================================================================================
    // 常量
    // =====================================================================================
    private static final String TAG = "FloatingBubbleService";
    private static final String CHANNEL_ID = "FloatingBubbleChannel";
    private static final int NOTIFICATION_ID = 1001;
    private static final int BUBBLE_SIZE_DP = 56; // 悬浮球的直径 (dp)

    // =====================================================================================
    // 成员变量
    // =====================================================================================

    private WindowManager windowManager;
    private View floatingView; // 悬浮球视图
    private View expandedView; // 展开后的菜单视图
    private FrameLayout circleContainer; // 悬浮球的圆形背景容器，方便后续修改颜色
    private ImageView iconView; // 悬浮球的图标，方便后续修改图标

    // 布局参数，用于控制视图在屏幕上的位置、大小等属性
    private WindowManager.LayoutParams bubbleParams;
    private WindowManager.LayoutParams menuParams;

    private boolean isExpanded = false; // 标记菜单是否处于展开状态
    private boolean isOverlayActive = false; // 标记译文遮罩是否处于激活状态

    // 用于与 Flutter 端通信的 MethodChannel
    private static MethodChannel channel;

    // 用于接收遮罩状态变化广播
    private BroadcastReceiver overlayStateReceiver;
    // 用于保存原始的长按操作
    private Runnable onLongClickAction;

    // =====================================================================================
    // 静态方法 - Flutter 通信接口
    // =====================================================================================

    /**
     * 设置与 Flutter 通信的 MethodChannel。
     * 此方法应在 Flutter 引擎初始化后尽快调用。
     *
     * @param methodChannel 来自 Flutter 的 MethodChannel 实例
     */
    public static void setMethodChannel(MethodChannel methodChannel) {
        channel = methodChannel;
    }

    // =====================================================================================
    // Service 生命周期方法
    // =====================================================================================

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, createNotification());
        setupOverlayStateReceiver();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 每次服务启动时，都优先检查悬浮窗权限
        if (!checkOverlayPermission()) {
            handlePermissionDenied();
            return START_NOT_STICKY; // 权限不足，不重新创建服务
        }

        // 如果悬浮球视图尚未创建，则进行创建
        if (floatingView == null) {
            try {
                createFloatingBubble();
            } catch (Exception e) {
                Log.e(TAG, "创建悬浮球时发生未知错误", e);
                if (channel != null) {
                    channel.invokeMethod("overlay_error", "创建悬浮窗失败: " + e.getMessage());
                }
                stopSelf(); // 创建失败，停止服务
                return START_NOT_STICKY;
            }
        }
        return START_STICKY; // 系统杀死服务后，会尝试重建服务
    }

    @Override
    public void onDestroy() {
        super.onDestroy();
        // 注销广播接收器，防止内存泄漏
        if (overlayStateReceiver != null) {
            unregisterReceiver(overlayStateReceiver);
        }
        // 确保移除所有窗口视图，防止窗口泄漏
        removeView(floatingView);
        floatingView = null;
        removeView(expandedView);
        expandedView = null;
        // 停止前台服务
        stopForeground(true);
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        // 该服务不提供绑定功能
        return null;
    }

    // =====================================================================================
    // 核心 UI 逻辑 - 悬浮球和菜单的创建、显示、隐藏
    // =====================================================================================

    /**
     * 创建并显示初始的悬浮球。
     */
    private void createFloatingBubble() {
        floatingView = new FrameLayout(this);
        int bubbleSizePx = dpToPx(BUBBLE_SIZE_DP);

        // 1. 创建圆形背景
        GradientDrawable circleDrawable = new GradientDrawable();
        circleDrawable.setShape(GradientDrawable.OVAL);
        circleDrawable.setColor(Color.parseColor("#AA9C27B0")); // 半透明紫色

        circleContainer = new FrameLayout(this); // 赋值给成员变量
        circleContainer.setBackground(circleDrawable);
        FrameLayout.LayoutParams circleParams = new FrameLayout.LayoutParams(bubbleSizePx, bubbleSizePx);

        // 2. 创建图标
        iconView = new ImageView(this); // 赋值给成员变量
        iconView.setImageResource(android.R.drawable.ic_menu_edit);
        iconView.setColorFilter(Color.WHITE);
        FrameLayout.LayoutParams iconParams = new FrameLayout.LayoutParams(dpToPx(24), dpToPx(24), Gravity.CENTER);

        // 3. 组装视图
        circleContainer.addView(iconView, iconParams);
        ((FrameLayout) floatingView).addView(circleContainer, circleParams);

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            floatingView.setElevation(dpToPx(4));
        }

        // 强制使用软件渲染，以避免在某些模拟器上因图形驱动问题导致的日志刷屏
        floatingView.setLayerType(View.LAYER_TYPE_SOFTWARE, null);

        // 4. 设置窗口布局参数
        bubbleParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                getWindowLayoutType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE, // 不获取焦点，以免影响其他应用
                PixelFormat.TRANSLUCENT
        );
        bubbleParams.gravity = Gravity.END | Gravity.CENTER_VERTICAL;
        bubbleParams.x = dpToPx(8); // 距离屏幕右侧的边距
        bubbleParams.y = 0;

        // 5. 定义长按操作，并将其与单击展开菜单的操作一同传递给触摸监听器
        onLongClickAction = () -> {
            floatingView.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS);
            if (channel != null) {
                channel.invokeMethod("translate_fullscreen", null);
            }
        };
        floatingView.setOnTouchListener(new DraggableTouchListener(bubbleParams, this::showBubbleMenu, onLongClickAction));

        // 6. 将视图添加到 WindowManager
        windowManager.addView(floatingView, bubbleParams);
    }

    /**
     * 根据悬浮球的当前位置，展开功能菜单。
     */
    private void showBubbleMenu() {
        if (isExpanded || expandedView != null) {
            return; // 防止重复展开
        }
        isExpanded = true;
        floatingView.setVisibility(View.GONE);

        // 1. 创建菜单的根布局
        LinearLayout menuLayout = new LinearLayout(this);
        menuLayout.setOrientation(LinearLayout.VERTICAL);
        int padding = dpToPx(8);
        menuLayout.setPadding(padding, padding, padding, padding);
        menuLayout.setGravity(Gravity.CENTER_HORIZONTAL);

        // 2. 创建菜单的背景（圆角矩形）
        GradientDrawable background = new GradientDrawable();
        background.setShape(GradientDrawable.RECTANGLE);
        background.setColor(Color.parseColor("#E6D3E8FD")); // 半透明浅蓝色
        background.setCornerRadius(dpToPx(28));
        menuLayout.setBackground(background);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            menuLayout.setElevation(dpToPx(4));
        }
        expandedView = menuLayout;

        // 强制使用软件渲染，以规避模拟器上的图形问题
        expandedView.setLayerType(View.LAYER_TYPE_SOFTWARE, null);

        // 3. 初始化或复用菜单的布局参数
        if (menuParams == null) {
            menuParams = new WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    getWindowLayoutType(),
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.TRANSLUCENT
            );
        }

        // 4. 创建可拖动的触摸监听器，并将其应用到菜单视图上
        DraggableTouchListener menuDragger = new DraggableTouchListener(menuParams, null, null);
        expandedView.setOnTouchListener(menuDragger);

        // 5. 将所有功能按钮添加到菜单布局中
        addMenuItemsToLayout(menuLayout, menuDragger);

        // 6. **核心对齐逻辑**: 计算菜单的位置，使其左上角与悬浮球的左上角对齐
        //    a. 必须先测量视图，才能获得其准确的宽度和高度
        expandedView.measure(
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
                View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        );
        final int menuWidth = expandedView.getMeasuredWidth();
        final int menuHeight = expandedView.getMeasuredHeight();
        final int bubbleSizePx = dpToPx(BUBBLE_SIZE_DP);

        //    b. 同步 gravity，并根据两个视图的尺寸差异，调整 x, y 坐标以实现左上角对齐
        menuParams.gravity = bubbleParams.gravity;
        //    x 坐标是相对于屏幕右边缘的偏移。要对齐左边缘，公式为: menu.x = bubble.x + bubble.width - menu.width
        menuParams.x = bubbleParams.x + bubbleSizePx - menuWidth;
        //    y 坐标是相对于垂直中心的偏移。要对齐上边缘，公式为: menu.y = bubble.y - (bubble.height/2) + (menu.height/2)
        //    注意：这里假设 bubble.y 是中心点的偏移，所以要先把它转换成顶部的偏移再计算。
        menuParams.y = bubbleParams.y - (bubbleSizePx / 2) + (menuHeight / 2);

        // 7. 将菜单视图添加到 WindowManager 并播放动画
        windowManager.addView(expandedView, menuParams);
        expandedView.setAlpha(0f);
        expandedView.animate().alpha(1f).setDuration(200).start();
    }

    /**
     * 隐藏功能菜单，并恢复显示悬浮球。
     */
    private void hideBubbleMenu() {
        if (!isExpanded || expandedView == null) {
            return;
        }

        // **核心对齐逻辑**: 在隐藏菜单前，将悬浮球的位置更新为当前菜单的位置，以保证下次展开时位置正确。
        if (menuParams != null) {
            final int menuWidth = expandedView.getWidth();
            final int menuHeight = expandedView.getHeight();
            final int bubbleSizePx = dpToPx(BUBBLE_SIZE_DP);

            bubbleParams.gravity = menuParams.gravity;
            // 反向计算，将悬浮球的左上角与菜单的左上角对齐
            // 公式: bubble.x = menu.x + menu.width - bubble.width
            bubbleParams.x = menuParams.x + menuWidth - bubbleSizePx;
            // 公式: bubble.y = menu.y - (menu.height/2) + (bubble.height/2)
            bubbleParams.y = menuParams.y - (menuHeight / 2) + (bubbleSizePx / 2);
        }

        isExpanded = false;
        final View viewToRemove = expandedView;
        expandedView = null; // 立即置空，防止在动画期间再次触发操作

        // 播放渐隐动画，并在动画结束后移除视图
        viewToRemove.animate()
                .alpha(0f)
                .setDuration(200)
                .withEndAction(() -> removeView(viewToRemove))
                .start();

        // 恢复显示悬浮球，并应用同步后的新位置
        if (floatingView != null) {
            if (floatingView.isAttachedToWindow()) {
                windowManager.updateViewLayout(floatingView, bubbleParams);
            }
            floatingView.setVisibility(View.VISIBLE);
            floatingView.setAlpha(0f);
            floatingView.animate().alpha(1f).setDuration(200).start();
        }
    }


    // =====================================================================================
    // 译文遮罩集成逻辑 (Overlay Integration Logic)
    // =====================================================================================

    /**
     * 设置一个广播接收器，用于监听译文遮罩服务的状态变化。
     */
    private void setupOverlayStateReceiver() {
        overlayStateReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (intent == null || intent.getAction() == null) return;

                String action = intent.getAction();
                // 使用在 TranslationOverlayService 中定义的公开常量
                String overlayShownAction = "com.example.transla_screen.ACTION_OVERLAY_SHOWN";
                String overlayHiddenAction = "com.example.transla_screen.ACTION_OVERLAY_HIDDEN";

                if (overlayShownAction.equals(action)) {
                    isOverlayActive = true;
                    updateBubbleState();
                    bringBubbleToFront();
                } else if (overlayHiddenAction.equals(action)) {
                    isOverlayActive = false;
                    updateBubbleState();
                }
            }
        };

        IntentFilter filter = new IntentFilter();
        filter.addAction("com.example.transla_screen.ACTION_OVERLAY_SHOWN");
        filter.addAction("com.example.transla_screen.ACTION_OVERLAY_HIDDEN");
        registerReceiver(overlayStateReceiver, filter);
    }

    /**
     * 根据译文遮罩的激活状态，更新悬浮球的外观和行为。
     */
    private void updateBubbleState() {
        if (floatingView == null || circleContainer == null || iconView == null) return;

        GradientDrawable background = (GradientDrawable) circleContainer.getBackground();

        if (isOverlayActive) {
            // 如果菜单当前是展开的，先将其收起，以确保悬浮球可见
            if (isExpanded) {
                // hideBubbleMenu() 会将 floatingView 设置为 VISIBLE
                hideBubbleMenu();
            }
            
            // 切换到 "关闭遮罩" 状态
            background.setColor(Color.parseColor("#D32F2F")); // 红色
            iconView.setImageResource(android.R.drawable.ic_menu_close_clear_cancel);
            // 单击关闭遮罩，拖动功能保留，禁用长按
            floatingView.setOnTouchListener(new DraggableTouchListener(bubbleParams, this::closeTranslationOverlay, null));
        } else {
            // 恢复到普通状态
            background.setColor(Color.parseColor("#AA9C27B0")); // 半透明紫色
            iconView.setImageResource(android.R.drawable.ic_menu_edit);
            // 恢复单击展开菜单、长按全局翻译的功能
            floatingView.setOnTouchListener(new DraggableTouchListener(bubbleParams, this::showBubbleMenu, onLongClickAction));
        }
    }

    /**
     * 将悬浮球视图带到最顶层。
     * 通过先从WindowManager移除，再重新添加的方式实现，这样可以使其显示在其他同类型窗口之上。
     */
    private void bringBubbleToFront() {
        if (floatingView != null && floatingView.isAttachedToWindow()) {
            Log.d(TAG, "Bringing bubble to front of the overlay.");
            windowManager.removeView(floatingView);
            windowManager.addView(floatingView, bubbleParams);
        }
    }

    /**
     * 处理关闭译文遮罩的点击事件。
     * 它通过停止 TranslationOverlayService 来实现关闭。
     */
    private void closeTranslationOverlay() {
        if (floatingView != null) {
            floatingView.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
        }
        Log.d(TAG, "Requesting to close translation overlay.");
        Intent intent = new Intent(this, TranslationOverlayService.class);
        stopService(intent);
        // `stopService` 是异步的。
        // `TranslationOverlayService` 的 `onDestroy` 会发送广播。
        // 广播接收后，`updateBubbleState` 会被调用以恢复悬浮球状态，无需在此处手动更新。
    }


    // =====================================================================================
    // UI 工厂和辅助方法
    // =====================================================================================

    /**
     * 创建并添加所有菜单项到布局中。
     *
     * @param menuLayout  菜单的父布局 (LinearLayout)。
     * @param menuDragger 父布局的拖动监听器，需要传递给可拖动的子按钮。
     */
    private void addMenuItemsToLayout(LinearLayout menuLayout, View.OnTouchListener menuDragger) {
        // 第一个按钮是折叠/拖动按钮，它比较特殊，需要父容器的拖动监听器
        menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_sort_by_size, "collapse", true, menuDragger, menuLayout));

        // 其他按钮是纯粹的功能按钮，不需要拖动功能
        menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_camera, "translate_fullscreen", false, null, null));
        menuLayout.addView(createMenuButton(android.R.drawable.ic_menu_crop, "start_area_selection", false, null, null));
    }

    /**
     * 创建单个菜单按钮 (ImageView)。
     *
     * @param iconResId        按钮的图标资源 ID。
     * @param action           与按钮关联的动作字符串，用于事件处理。
     * @param isCollapseButton 标记此按钮是否为特殊的"折叠/拖动"按钮。
     * @param dragListener     如果此按钮需要能拖动整个菜单，则传入父容器的拖动监听器。
     * @param parentView       父容器的视图实例，仅当 dragListener 不为 null 时需要。
     * @return 返回创建好的 ImageView 实例。
     */
    private ImageView createMenuButton(int iconResId, final String action, boolean isCollapseButton, @Nullable View.OnTouchListener dragListener, @Nullable View parentView) {
        ImageView button = new ImageView(this);
        button.setImageResource(iconResId);
        int padding = dpToPx(12);
        button.setPadding(padding, padding, padding, padding);

        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dpToPx(48), dpToPx(48));

        if (isCollapseButton) {
            // "折叠/拖动"按钮的特殊样式（蓝色圆形背景）
            GradientDrawable circleBg = new GradientDrawable();
            circleBg.setShape(GradientDrawable.OVAL);
            circleBg.setColor(Color.parseColor("#2196F3"));
            button.setBackground(circleBg);
            button.setColorFilter(Color.WHITE);
            params.setMargins(0, 0, 0, dpToPx(12)); // 底部留出更多间距
        } else {
            // 普通功能按钮的样式（透明背景）
            button.setBackgroundColor(Color.TRANSPARENT);
            button.setColorFilter(Color.parseColor("#555555")); // 深灰色图标
            params.setMargins(0, dpToPx(4), 0, dpToPx(4));
        }
        button.setLayoutParams(params);

        // **关键**: 根据按钮类型设置不同的触摸监听器
        if (isCollapseButton && dragListener != null && parentView != null) {
            // 对于折叠按钮，使用特殊的 DraggableButtonTouchListener，它既能响应点击（折叠），又能将拖动事件传递给父视图。
            button.setOnTouchListener(new DraggableButtonTouchListener(v -> hideBubbleMenu(), dragListener, parentView));
        } else {
            // 对于普通按钮，只设置一个简单的点击监听器。
            button.setOnClickListener(v -> {
                v.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
                handleButtonClick(action);
            });
        }
        return button;
    }

    // =====================================================================================
    // 事件处理
    // =====================================================================================

    /**
     * 统一处理菜单按钮的点击事件。
     * @param action 按钮关联的动作字符串。
     */
    private void handleButtonClick(String action) {
        switch (action) {
            case "collapse":
                // 此动作现在由 DraggableButtonTouchListener 直接处理，这里为空。
                break;
            case "start_area_selection":
            case "translate_fullscreen":
                if (channel != null) {
                    channel.invokeMethod(action, null);
                }
                hideBubbleMenu(); // 执行完操作后总是隐藏菜单
                break;
            default:
                Toast.makeText(this, "功能待实现: " + action, Toast.LENGTH_SHORT).show();
                hideBubbleMenu();
                break;
        }
    }

    /**
     * 处理没有悬浮窗权限的情况。
     */
    private void handlePermissionDenied() {
        Log.e(TAG, "没有悬浮窗权限，服务无法启动。");
        final String errorMsg = "悬浮窗权限被拒绝，请在系统设置中授予权限。";
        if (channel != null) {
            channel.invokeMethod("overlay_permission_denied", errorMsg);
        }
        Toast.makeText(this, "无法创建悬浮窗，请在设置中授予权限", Toast.LENGTH_LONG).show();
        stopSelf();
    }


    // =====================================================================================
    // 系统与工具方法
    // =====================================================================================

    /**
     * 创建前台服务所需的通知。
     */
    private Notification createNotification() {
        Intent notificationIntent = new Intent(this, MainActivity.class);
        PendingIntent pendingIntent = PendingIntent.getActivity(
                this, 0, notificationIntent, PendingIntent.FLAG_IMMUTABLE);

        return new NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_menu_edit)
                .setContentTitle("TranslaScreen翻译服务")
                .setContentText("悬浮球服务正在运行中")
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setContentIntent(pendingIntent)
                .build();
    }

    /**
     * 创建通知通道，适用于 Android 8.0 (Oreo) 及以上版本。
     */
    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "悬浮翻译服务",
                    NotificationManager.IMPORTANCE_LOW // 设置为低优先级，避免在状态栏发出声音或振动
            );
            channel.setDescription("用于保持悬浮球服务的持续运行。");
            channel.enableLights(false);
            channel.enableVibration(false);

            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    /**
     * 检查应用是否具有"在其他应用上层显示"的权限。
     */
    private boolean checkOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Settings.canDrawOverlays(this);
        }
        return true; // Android M 以下版本默认授予此权限
    }

    /**
     * 安全地从 WindowManager 移除一个视图。
     * @param view 要移除的视图。
     */
    private void removeView(View view) {
        if (view != null && view.isAttachedToWindow()) {
            try {
                windowManager.removeView(view);
            } catch (Exception e) {
                Log.e(TAG, "从 WindowManager 移除视图时出错", e);
            }
        }
    }

    /**
     * 获取适用于悬浮窗的 WindowManager.LayoutParams.type。
     * 在 Android 8.0 及以上，必须使用 TYPE_APPLICATION_OVERLAY。
     */
    private int getWindowLayoutType() {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
    }

    /**
     * 将 dp 单位转换为像素 (px) 单位。
     */
    private int dpToPx(int dp) {
        return Math.round(dp * getResources().getDisplayMetrics().density);
    }


    // =====================================================================================
    // 内部类 - 触摸事件监听器
    // =====================================================================================

    /**
     * 一个通用的可拖动视图触摸监听器。
     *
     * 该监听器能够智能地区分用户的三种手势：
     * 1.  **单击 (Click)**: 手指按下和抬起的时间很短，且移动距离很小。
     * 2.  **长按 (Long Press)**: 手指按下后，在原地停留超过一定时间。
     * 3.  **拖动 (Drag)**: 手指按下后，移动的距离超过了阈值。
     *
     * 它通过构造函数接收单击和长按的回调，并直接更新视图的 WindowManager.LayoutParams 来实现拖动。
     */
    private class DraggableTouchListener implements View.OnTouchListener {
        private final WindowManager.LayoutParams params;
        private final Runnable onClickAction;
        private final Runnable onLongClickAction;

        // 状态变量
        private int initialX, initialY;
        private float initialTouchX, initialTouchY;
        private long touchStartTime;
        private boolean longPressFired;

        // 手势判断阈值
        private static final int CLICK_TIME_THRESHOLD = 200; // 单击最大时长 (ms)
        private static final float DRAG_TOLERANCE = 10f;     // 判定为拖动的最小移动像素
        private static final int LONG_PRESS_TIMEOUT = 500;   // 判定为长按的超时时间 (ms)

        private final Handler longPressHandler = new Handler();
        private final Runnable longPressRunnable;

        public DraggableTouchListener(WindowManager.LayoutParams params, @Nullable Runnable onClickAction, @Nullable Runnable onLongClickAction) {
            this.params = params;
            this.onClickAction = onClickAction;
            this.onLongClickAction = onLongClickAction;
            this.longPressRunnable = () -> {
                longPressFired = true; // 标记长按已触发
                if (this.onLongClickAction != null) {
                    this.onLongClickAction.run();
                }
            };
        }

        @Override
        public boolean onTouch(View v, MotionEvent event) {
            switch (event.getAction()) {
                case MotionEvent.ACTION_DOWN:
                    // 1. 记录初始状态
                    initialX = params.x;
                    initialY = params.y;
                    initialTouchX = event.getRawX();
                    initialTouchY = event.getRawY();
                    touchStartTime = System.currentTimeMillis();
                    longPressFired = false;

                    // 2. 启动长按检测计时器
                    longPressHandler.postDelayed(longPressRunnable, LONG_PRESS_TIMEOUT);
                    return true;

                case MotionEvent.ACTION_MOVE:
                    float deltaX = event.getRawX() - initialTouchX;
                    float deltaY = event.getRawY() - initialTouchY;

                    // 3. 判断是否为拖动手势
                    if (Math.abs(deltaX) > DRAG_TOLERANCE || Math.abs(deltaY) > DRAG_TOLERANCE) {
                        // 一旦开始拖动，就取消长按检测
                        longPressHandler.removeCallbacks(longPressRunnable);

                        // 4. 更新视图在屏幕上的位置
                        // 注意：需要根据 gravity 的方向来正确计算坐标
                        if ((params.gravity & Gravity.END) == Gravity.END) {
                            params.x = initialX - (int) deltaX; // 从右侧计算
                        } else {
                            params.x = initialX + (int) deltaX; // 从左侧计算
                        }
                        params.y = initialY + (int) deltaY;
                        windowManager.updateViewLayout(v, params);
                    }
                    return true;

                case MotionEvent.ACTION_UP:
                    // 5. 手指抬起，无论如何都取消长按检测
                    longPressHandler.removeCallbacks(longPressRunnable);

                    long touchDuration = System.currentTimeMillis() - touchStartTime;
                    float totalDragDistance = Math.abs(event.getRawX() - initialTouchX) + Math.abs(event.getRawY() - initialTouchY);

                    // 6. 判断是否为单击手势
                    // 条件：长按未触发 AND 点击时间够短 AND 移动距离够小
                    if (!longPressFired && onClickAction != null &&
                        touchDuration < CLICK_TIME_THRESHOLD && totalDragDistance < DRAG_TOLERANCE) {
                        onClickAction.run();
                    }
                    return true;
            }
            return false;
        }
    }

    /**
     * 一个专为"可拖动菜单中的按钮"设计的触摸监听器。
     *
     * 这个监听器的巧妙之处在于它能同时处理两种交互：
     * 1.  **单击**：当用户快速点击按钮时，它会执行自己的 `clickListener`（例如，隐藏菜单）。
     * 2.  **拖动**：当用户在按钮上按下并拖动时，它会将所有的触摸事件 (DOWN, MOVE, UP)
     *     都转发给外部传入的 `dragListener`（即父视图的拖动监听器）。
     *
     * 这样就实现了"点击按钮本身执行操作，拖动按钮则移动整个菜单"的复合效果。
     */
    private static class DraggableButtonTouchListener implements View.OnTouchListener {
        private final View.OnClickListener clickListener;
        private final View.OnTouchListener dragListener;
        private final View parentView;

        // 状态变量，用于区分单击和拖动
        private float initialTouchX, initialTouchY;
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
                    // 记录初始触摸状态
                    initialTouchX = event.getRawX();
                    initialTouchY = event.getRawY();
                    touchStartTime = System.currentTimeMillis();
                    // **关键**: 立即将 DOWN 事件转发给父视图的拖动监听器，以便它能正确初始化拖动状态。
                    dragListener.onTouch(parentView, event);
                    return true;

                case MotionEvent.ACTION_MOVE:
                    // **关键**: 持续将 MOVE 事件转发，让父视图的监听器处理位置更新。
                    dragListener.onTouch(parentView, event);
                    return true;

                case MotionEvent.ACTION_UP:
                    long touchDuration = System.currentTimeMillis() - touchStartTime;
                    float totalDragDistance = Math.abs(event.getRawX() - initialTouchX) + Math.abs(event.getRawY() - initialTouchY);

                    // 判断是单击还是拖动结束
                    if (touchDuration < CLICK_TIME_THRESHOLD && totalDragDistance < DRAG_TOLERANCE) {
                        // 这是一个单击事件，执行按钮自己的点击逻辑
                        v.performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY);
                        clickListener.onClick(v);
                    }

                    // **关键**: 无论如何，都需要将 UP 事件转发给父视图的拖动监听器，以便它能正确地结束拖动状态（例如，判断是否为单击）。
                    dragListener.onTouch(parentView, event);
                    return true;
            }
            return false;
        }
    }
}