import 'dart:async';

import 'package:background_location_tracker/background_location_tracker.dart';
import 'package:background_location_tracker/src/channel/background_channel.dart';
import 'package:background_location_tracker/src/channel/foreground_channel.dart';
import 'package:background_location_tracker/src/util/logger.dart';

typedef LocationUpdateCallback = Future<void> Function(
    BackgroundLocationUpdateData data);

class BackgroundLocationTrackerManager {
  static Future<void> initialize(Function callback,
      {BackgroundLocationTrackerConfig? config}) {
    final pluginConfig = config ??= const BackgroundLocationTrackerConfig();
    BackgroundLocationTrackerLogger.enableLogging = pluginConfig.loggingEnabled;
    return ForegroundChannel.initialize(callback, config: pluginConfig);
  }

  static Future<bool> isTracking() async => ForegroundChannel.isTracking();

  static Future<void> startTracking({AndroidConfig? config}) async =>
      ForegroundChannel.startTracking(config: config);

  static Future<void> stopTracking() async => ForegroundChannel.stopTracking();

  static void handleBackgroundUpdated(LocationUpdateCallback callback) =>
      BackgroundChannel.handleBackgroundUpdated(callback);

  /// Sets the drive active state - native side will handle permission monitoring
  static Future<void> setDriveActive(bool isActive) async {
    BackgroundLocationTrackerLogger.log('Setting drive active state to: $isActive');
    return ForegroundChannel.setDriveActive(isActive);
  }

  /// Sets a callback to be called when location permission is granted
  /// This allows the Flutter side to handle permission changes and initialize tracking
  static void setOnPermissionGrantedCallback(Function() callback) {
    ForegroundChannel.setOnPermissionGrantedCallback(callback);
  }
}
