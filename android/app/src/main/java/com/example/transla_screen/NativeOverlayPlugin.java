package com.example.transla_screen;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

import androidx.annotation.NonNull;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;

/**
 * 原生悬浮窗插件，用于连接Flutter和Java原生实现的悬浮窗功能
 */
public class NativeOverlayPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware,
        PluginRegistry.ActivityResultListener {
    private static final String TAG = "NativeOverlayPlugin";
    private static final String CHANNEL_NAME = "com.example.transla_screen/native_overlay";
    private static final int REQUEST_CODE_OVERLAY_PERMISSION = 1234;

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private Result pendingPermissionResult; // 用于存储权限请求的结果回调

    @Override
    public void onAttachedToEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL_NAME);
        channel.setMethodCallHandler(this);
        context = binding.getApplicationContext();

        // 设置MethodChannel给服务
        FloatingBubbleService.setMethodChannel(channel);
        TranslationOverlayService.setMethodChannel(channel);

        Log.d(TAG, "插件已附加到引擎");
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPlugin.FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
        context = null;
        Log.d(TAG, "插件已从引擎分离");
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        try {
            Log.d(TAG, "收到方法调用: " + call.method);

            switch (call.method) {
                case "checkOverlayPermission":
                    checkOverlayPermission(result);
                    break;
                case "requestOverlayPermission":
                    requestOverlayPermission(result);
                    break;
                case "showFloatingBubble":
                    showFloatingBubble(result);
                    break;
                case "hideFloatingBubble":
                    hideFloatingBubble();
                    result.success(true);
                    break;
                case "showTranslationOverlay":
                    String translationData = call.argument("translationData");
                    showTranslationOverlay(translationData, result);
                    break;
                case "hideTranslationOverlay":
                    hideTranslationOverlay();
                    result.success(true);
                    break;
                default:
                    result.notImplemented();
                    break;
            }
        } catch (Exception e) {
            Log.e(TAG, "处理方法调用时出错", e);
            result.error("NATIVE_ERROR", e.getMessage(), null);
        }
    }

    private void checkOverlayPermission(Result result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            boolean hasPermission = Settings.canDrawOverlays(context);
            result.success(hasPermission);
        } else {
            // 旧版本Android默认允许
            result.success(true);
        }
    }

    private void requestOverlayPermission(Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "没有活动的Activity来处理权限请求", null);
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(context)) {
                pendingPermissionResult = result;
                Intent intent = new Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:" + context.getPackageName())
                );
                activity.startActivityForResult(intent, REQUEST_CODE_OVERLAY_PERMISSION);
            } else {
                result.success(true);
            }
        } else {
            // 旧版本Android默认允许
            result.success(true);
        }
    }

    private void showFloatingBubble(Result result) {
        if (context == null) {
            result.error("NO_CONTEXT", "插件上下文为空", null);
            return;
        }

        // 检查权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(context)) {
                Log.e(TAG, "显示悬浮球: 没有SYSTEM_ALERT_WINDOW权限");
                result.error("PERMISSION_DENIED", "没有SYSTEM_ALERT_WINDOW权限", null);
                return;
            }
        }

        Log.d(TAG, "显示悬浮球");
        Intent intent = new Intent(context, FloatingBubbleService.class);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "启动FloatingBubbleService失败", e);
            result.error("SERVICE_START_FAILED", e.getMessage(), null);
        }
    }

    private void hideFloatingBubble() {
        if (context == null) return;
        Log.d(TAG, "隐藏悬浮球");
        context.stopService(new Intent(context, FloatingBubbleService.class));
    }

    private void showTranslationOverlay(String translationData, Result result) {
        if (context == null || translationData == null) {
            result.error("INVALID_ARGS", "上下文为空或翻译数据为空", null);
            return;
        }

        // 检查权限
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(context)) {
                Log.e(TAG, "显示译文蒙版: 没有SYSTEM_ALERT_WINDOW权限");
                result.error("PERMISSION_DENIED", "没有SYSTEM_ALERT_WINDOW权限", null);
                return;
            }
        }
        
        Log.d(TAG, "显示译文蒙版");
        Intent intent = new Intent(context, TranslationOverlayService.class);
        intent.putExtra("translation_data", translationData);
        
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent);
            } else {
                context.startService(intent);
            }
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "启动TranslationOverlayService失败", e);
            result.error("SERVICE_START_FAILED", e.getMessage(), null);
        }
    }

    private void hideTranslationOverlay() {
        if (context == null) return;
        Log.d(TAG, "隐藏译文蒙版");
        context.stopService(new Intent(context, TranslationOverlayService.class));
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        this.activity = binding.getActivity();
        binding.addActivityResultListener(this);
        Log.d(TAG, "插件已附加到活动");
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        this.activity = null;
        Log.d(TAG, "插件因配置更改而从活动分离");
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        this.activity = binding.getActivity();
        binding.addActivityResultListener(this);
        Log.d(TAG, "插件已重新附加到活动");
    }

    @Override
    public void onDetachedFromActivity() {
        this.activity = null;
        Log.d(TAG, "插件已从活动分离");
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQUEST_CODE_OVERLAY_PERMISSION) {
            if (pendingPermissionResult != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    boolean hasPermission = Settings.canDrawOverlays(context);
                    pendingPermissionResult.success(hasPermission);
                } else {
                    pendingPermissionResult.success(true);
                }
                pendingPermissionResult = null;
                return true;
            }
        }
        return false;
    }
} 