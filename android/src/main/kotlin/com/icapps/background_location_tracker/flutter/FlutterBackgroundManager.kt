package com.icapps.background_location_tracker.flutter

import android.content.Context
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.icapps.background_location_tracker.BackgroundLocationTrackerPlugin
import com.icapps.background_location_tracker.utils.Logger
import com.icapps.background_location_tracker.utils.SharedPrefsUtil
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

internal object FlutterBackgroundManager {
    private const val BACKGROUND_CHANNEL_NAME = "com.icapps.background_location_tracker/background_channel"

    private val flutterLoader = FlutterLoader()
    private var backgroundChannel: MethodChannel? = null
    private var isInitialized = false
    private var pendingLocation: Location? = null

    private fun getInitializedFlutterEngine(ctx: Context): FlutterEngine {
        Logger.debug("BackgroundManager", "Getting Flutter engine")

        return BackgroundLocationTrackerPlugin.getFlutterEngine(ctx)
    }

    fun sendLocation(ctx: Context, location: Location) {
        Logger.debug("BackgroundManager", "Location: ${location.latitude}: ${location.longitude}")
        
        if (isInitialized) {
            // Engine is already initialized, send location immediately
            sendLocationToChannel(ctx, location)
        } else {
            // Store the location and initialize if needed
            pendingLocation = location
            setupBackgroundChannelIfNeeded(ctx)
        }
    }

    private fun setupBackgroundChannelIfNeeded(ctx: Context) {
        if (backgroundChannel != null) {
            return // Already setup
        }

        Logger.debug("BackgroundManager", "Setting up background channel and dart executor")
        val engine = getInitializedFlutterEngine(ctx)
        
        backgroundChannel = MethodChannel(engine.dartExecutor, BACKGROUND_CHANNEL_NAME)
        backgroundChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialized" -> {
                    Logger.debug("BackgroundManager", "Dart background isolate initialized")
                    isInitialized = true
                    result.success(true)
                    
                    // Send any pending location
                    pendingLocation?.let { location ->
                        Logger.debug("BackgroundManager", "Sending pending location after initialization")
                        sendLocationToChannel(ctx, location)
                        pendingLocation = null
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        if (!flutterLoader.initialized()) {
            flutterLoader.startInitialization(ctx)
        }
        flutterLoader.ensureInitializationCompleteAsync(ctx, null, Handler(Looper.getMainLooper())) {
            val callbackHandle = SharedPrefsUtil.getCallbackHandle(ctx)
            val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)
            val dartBundlePath = flutterLoader.findAppBundlePath()
            engine.dartExecutor.executeDartCallback(DartExecutor.DartCallback(ctx.assets, dartBundlePath, callbackInfo))
        }
    }

    private fun sendLocationToChannel(ctx: Context, location: Location) {
        val channel = backgroundChannel ?: return
        Logger.debug("BackgroundManager", "Sending location to initialized channel")
        
        val data = mutableMapOf<String, Any>()
        data["lat"] = location.latitude
        data["lon"] = location.longitude
        data["alt"] = if (location.hasAltitude()) location.altitude else 0.0
        data["vertical_accuracy"] = -1.0
        data["horizontal_accuracy"] = if (location.hasAccuracy()) location.accuracy else -1.0
        data["course"] = if (location.hasBearing()) location.bearing else -1.0
        data["course_accuracy"] = -1.0
        data["speed"] = if (location.hasSpeed()) location.speed else -1.0
        data["speed_accuracy"] = -1.0
        data["logging_enabled"] = SharedPrefsUtil.isLoggingEnabled(ctx)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            data["vertical_accuracy"] = if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters else -1.0
            data["course_accuracy"] = if (location.hasBearingAccuracy()) location.bearingAccuracyDegrees else -1.0
            data["speed_accuracy"] = if (location.hasSpeedAccuracy()) location.speedAccuracyMetersPerSecond else -1.0
        }

        channel.invokeMethod("onLocationUpdate", data, object : MethodChannel.Result {
            override fun success(result: Any?) {
                Logger.debug("BackgroundManager", "Successfully sent location update")
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Logger.debug("BackgroundManager", "Error sending location update: $errorCode - $errorMessage : $errorDetails")
            }

            override fun notImplemented() {
                Logger.debug("BackgroundManager", "Method not implemented for location update")
            }
        })
    }
    
    fun cleanup() {
        Logger.debug("BackgroundManager", "Cleaning up background resources")
        isInitialized = false
        backgroundChannel = null
        pendingLocation = null
    }
}
