import 'dart:ui';

import 'package:background_location_tracker/src/model/config/android_config.dart';
import 'package:background_location_tracker/src/model/config/background_location_tracker_config.dart';
import 'package:background_location_tracker/src/model/config/ios_config.dart';
import 'package:background_location_tracker/src/util/logger.dart';
import 'package:flutter/services.dart';

class ForegroundChannel {
  static const _FOREGROUND_CHANNEL_NAME =
      'com.icapps.background_location_tracker/foreground_channel';

  static const MethodChannel _foregroundChannel =
      MethodChannel(_FOREGROUND_CHANNEL_NAME);
  
  // Callback for handling permission changes from native side
  static Function()? _onPermissionGrantedCallback;

  static Future<void> initialize(Function callbackDispatcher,
      {required BackgroundLocationTrackerConfig config}) async {
    final callback = PluginUtilities.getCallbackHandle(callbackDispatcher);
    if (callback == null) {
      throw ArgumentError(
          'The callbackDispatcher needs to be either a static function or a top level function to be accessible as a Flutter entry point.');
    }
    final handle = callback.toRawHandle();
    
    // Set up method call handler for permission change events
    _foregroundChannel.setMethodCallHandler(_handleMethodCall);
    
    await _foregroundChannel.invokeMethod<void>(
      'initialize',
      {
        'callback_handle': handle,
        'logging_enabled': config.loggingEnabled,
        'android_update_interval_msec':
            config.androidConfig.trackingInterval.inMilliseconds,
        'android_config_channel_name': config.androidConfig.channelName,
        'android_config_notification_body':
            config.androidConfig.notificationBody,
        'android_config_notification_icon':
            config.androidConfig.notificationIcon,
        'android_config_enable_notification_location_updates':
            config.androidConfig.enableNotificationLocationUpdates,
        'android_config_cancel_tracking_action_text':
            config.androidConfig.cancelTrackingActionText,
        'android_config_enable_cancel_tracking_action':
            config.androidConfig.enableCancelTrackingAction,
        'android_distance_filter': config.androidConfig.distanceFilterMeters,
        'ios_activity_type': _activityTypeString(config.iOSConfig.activityType),
        'ios_distance_filter': config.iOSConfig.distanceFilterMeters,
        'ios_restart_after_kill': config.iOSConfig.restartAfterKill,
      },
    );
  }

  static Future<bool> isTracking() async {
    final result = await _foregroundChannel.invokeMethod<bool>('isTracking');
    return result == true;
  }

  static Future<void> startTracking({AndroidConfig? config}) {
    return _foregroundChannel.invokeMethod(
      'startTracking',
      {
        'android_config_notification_body': config?.notificationBody,
        'android_config_notification_icon': config?.notificationIcon,
        'android_config_enable_notification_location_updates':
            config?.enableNotificationLocationUpdates,
        'android_config_cancel_tracking_action_text':
            config?.cancelTrackingActionText,
        'android_config_enable_cancel_tracking_action':
            config?.enableCancelTrackingAction,
      },
    );
  }

  static Future<void> stopTracking() =>
      _foregroundChannel.invokeMethod('stopTracking');

  static Future<void> setDriveActive(bool isActive) =>
      _foregroundChannel.invokeMethod('setDriveActive', {'isActive': isActive});

  /// Sets a callback to be called when location permission is granted
  static void setOnPermissionGrantedCallback(Function() callback) {
    _onPermissionGrantedCallback = callback;
  }

  /// Handles method calls from the native side
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    BackgroundLocationTrackerLogger.log('Received method call: ${call.method}');
    
    switch (call.method) {
      case 'onPermissionGranted':
        BackgroundLocationTrackerLogger.log('🚨 Location permission granted - triggering callback');
        BackgroundLocationTrackerLogger.log('🚨 Callback is null: ${_onPermissionGrantedCallback == null}');
        _onPermissionGrantedCallback?.call();
        BackgroundLocationTrackerLogger.log('🚨 Callback executed');
        return true;
      default:
        BackgroundLocationTrackerLogger.log('Unknown method call: ${call.method}');
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'ForegroundChannel does not recognize method ${call.method}',
        );
    }
  }
}

String _activityTypeString(ActivityType activityType) {
  switch (activityType) {
    case ActivityType.OTHER:
      return 'OTHER';
    case ActivityType.AUTOMOTIVE:
      return 'AUTOMOTIVE';
    case ActivityType.FITNESS:
      return 'FITNESS';
    case ActivityType.NAVIGATION:
      return 'NAVIGATION';
    case ActivityType.AIRBORNE:
      return 'AIRBORNE';
  }
}
