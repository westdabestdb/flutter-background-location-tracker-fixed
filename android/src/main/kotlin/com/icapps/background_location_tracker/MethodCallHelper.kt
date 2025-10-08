package com.icapps.background_location_tracker

import android.content.Context
import android.location.Location
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleObserver
import androidx.lifecycle.OnLifecycleEvent
import com.icapps.background_location_tracker.ext.checkRequiredFields
import com.icapps.background_location_tracker.flutter.FlutterBackgroundManager
import com.icapps.background_location_tracker.service.LocationServiceConnection
import com.icapps.background_location_tracker.service.LocationUpdateListener
import com.icapps.background_location_tracker.utils.*
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Handles method calls from Flutter and manages service lifecycle.
 * Refactored to use centralized state management and consolidated startup logic.
 */
internal class MethodCallHelper(private val ctx: Context) : 
    MethodChannel.MethodCallHandler, 
    LifecycleObserver, 
    LocationUpdateListener {

    private var serviceConnection = LocationServiceConnection(this)

    fun handle(call: MethodCall, result: MethodChannel.Result) = when (call.method) {
        "initialize" -> initialize(ctx, call, result)
        "isTracking" -> isTracking(ctx, call, result)
        "startTracking" -> startTracking(ctx, call, result)
        "stopTracking" -> stopTracking(ctx, call, result)
        "getHealthCheck" -> getHealthCheck(ctx, result)
        else -> result.error("404", "${call.method} is not supported", null)
    }

    // ==================== INITIALIZATION ====================

    private fun initialize(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        Logger.debug(TAG, "=== Initializing ===")
        
        // Extract all configuration
        val callbackHandleKey = "callback_handle"
        val loggingEnabledKey = "logging_enabled"
        val trackingIntervalKey = "android_update_interval_msec"
        val channelNameKey = "android_config_channel_name"
        val notificationBodyKey = "android_config_notification_body"
        val notificationIconKey = "android_config_notification_icon"
        val enableNotificationLocationUpdatesKey = "android_config_enable_notification_location_updates"
        val enableCancelTrackingActionKey = "android_config_enable_cancel_tracking_action"
        val cancelTrackingActionTextKey = "android_config_cancel_tracking_action_text"
        val distanceFilterKey = "android_distance_filter"
        
        val keys = listOf(
            callbackHandleKey,
            loggingEnabledKey,
            channelNameKey,
            notificationBodyKey,
            enableNotificationLocationUpdatesKey,
            cancelTrackingActionTextKey,
            enableCancelTrackingActionKey,
            trackingIntervalKey
        )
        
        if (!call.checkRequiredFields(keys, result)) return
        
        val callbackHandle = getLongArgumentByKey(call, callbackHandleKey)!!
        val loggingEnabled = call.argument<Boolean>(loggingEnabledKey)!!
        val channelName = call.argument<String>(channelNameKey)!!
        val notificationBody = call.argument<String>(notificationBodyKey)!!
        val notificationIcon = call.argument<String>(notificationIconKey)
        val enableNotificationLocationUpdates = call.argument<Boolean>(enableNotificationLocationUpdatesKey)!!
        val cancelTrackingActionText = call.argument<String>(cancelTrackingActionTextKey)!!
        val enableCancelTrackingAction = call.argument<Boolean>(enableCancelTrackingActionKey)!!
        val trackingInterval = getLongArgumentByKey(call, trackingIntervalKey)!!
        val distanceFilter = (call.argument<Double>(distanceFilterKey) ?: 0.0).toFloat()
        
        // Save configuration
        SharedPrefsUtil.saveLoggingEnabled(ctx, loggingEnabled)
        SharedPrefsUtil.saveTrackingInterval(ctx, trackingInterval)
        SharedPrefsUtil.saveDistanceFilter(ctx, distanceFilter)
        SharedPrefsUtil.saveCallbackDispatcherHandleKey(ctx, callbackHandle)
        SharedPrefsUtil.saveNotificationConfig(
            ctx, 
            notificationBody, 
            notificationIcon, 
            cancelTrackingActionText, 
            enableNotificationLocationUpdates, 
            enableCancelTrackingAction
        )
        
        // Enable logging
        Logger.enabled = loggingEnabled
        Logger.debug(TAG, "Logging enabled: $loggingEnabled")
        
        // Create notification channels
        NotificationUtil.createNotificationChannels(ctx, channelName)
        
        // Initialize state manager
        TrackingStateManager.initialize(ctx)
        
        // Log current state
        Logger.debug(TAG, "State after init: ${TrackingStateManager.getState()::class.simpleName}")
        
        // Perform health check
        if (loggingEnabled) {
            HealthCheck.logHealthCheck(ctx)
            PermissionChecker.logPermissionStatus(ctx)
        }
        
        result.success(true)
    }

    private fun getLongArgumentByKey(call: MethodCall, key: String): Long? {
        return try {
            call.argument<Number>(key)!!.toLong()
        } catch (exception: ClassCastException) {
            call.argument(key)
        }
    }

    // ==================== TRACKING CONTROL ====================

    private fun isTracking(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val tracking = TrackingStateManager.isTracking()
        Logger.debug(TAG, "isTracking query: $tracking")
        result.success(tracking)
    }

    private fun startTracking(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        Logger.debug(TAG, "=== startTracking called from Flutter ===")
        
        // Update notification config if provided
        val notificationBodyKey = "android_config_notification_body"
        val notificationIconKey = "android_config_notification_icon"
        val enableNotificationLocationUpdatesKey = "android_config_enable_notification_location_updates"
        val enableCancelTrackingActionKey = "android_config_enable_cancel_tracking_action"
        val cancelTrackingActionTextKey = "android_config_cancel_tracking_action_text"

        val notificationBody = call.argument<String>(notificationBodyKey)
        val notificationIcon = call.argument<String>(notificationIconKey)
        val enableNotificationLocationUpdates = call.argument<Boolean>(enableNotificationLocationUpdatesKey)
        val cancelTrackingActionText = call.argument<String>(cancelTrackingActionTextKey)
        val enableCancelTrackingAction = call.argument<Boolean>(enableCancelTrackingActionKey)
        
        if (notificationBody != null || notificationIcon != null || cancelTrackingActionText != null ||
            enableNotificationLocationUpdates != null || enableCancelTrackingAction != null) {
            SharedPrefsUtil.saveNotificationConfig(
                ctx, 
                notificationBody ?: SharedPrefsUtil.getNotificationBody(ctx),
                notificationIcon ?: SharedPrefsUtil.getNotificationIcon(ctx),
                cancelTrackingActionText ?: SharedPrefsUtil.getCancelTrackingActionText(ctx),
                enableNotificationLocationUpdates ?: SharedPrefsUtil.isNotificationLocationUpdatesEnabled(ctx),
                enableCancelTrackingAction ?: SharedPrefsUtil.isCancelTrackingActionEnabled(ctx)
            )
        }
        
        // Perform health check before starting
        val healthCheck = HealthCheck.performHealthCheck(ctx)
        if (!healthCheck.canStartTracking) {
            Logger.error(TAG, "Cannot start tracking - health check failed")
            HealthCheck.logHealthCheck(ctx)
            
            // Return error to Flutter
            val firstCritical = healthCheck.criticalIssues.firstOrNull()
            result.error(
                firstCritical?.code ?: "preflight_failed",
                firstCritical?.message ?: "Pre-flight checks failed",
                mapOf(
                    "issues" to healthCheck.criticalIssues.map { 
                        mapOf(
                            "code" to it.code,
                            "message" to it.message,
                            "userAction" to it.userActionRequired
                        )
                    }
                )
            )
            return
        }
        
        // Update state to Starting
        TrackingStateManager.setState(TrackingStateManager.TrackingState.Starting, ctx)
        
        // Start the service
        com.icapps.background_location_tracker.service.LocationUpdatesService.startServiceImmediately(ctx)
        
        // Bind to service
        serviceConnection.bound(ctx)
        
        // Request tracking through service
        serviceConnection.service?.startTracking()
        
        Logger.debug(TAG, "Start tracking request sent")
        result.success(true)
    }

    private fun stopTracking(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        Logger.debug(TAG, "=== stopTracking called from Flutter ===")
        
        // Update state to Stopping
        TrackingStateManager.setState(TrackingStateManager.TrackingState.Stopping, ctx)
        
        // Stop tracking through service
        serviceConnection.service?.stopTracking()
        
        // Clean up Flutter background resources
        FlutterBackgroundManager.forceCleanup()
        
        Logger.debug(TAG, "Stop tracking request sent")
        result.success(true)
    }

    // ==================== HEALTH CHECK ====================

    private fun getHealthCheck(ctx: Context, result: MethodChannel.Result) {
        Logger.debug(TAG, "Health check requested")
        val healthCheckMap = HealthCheck.getHealthCheckMap(ctx)
        result.success(healthCheckMap)
    }

    // ==================== LIFECYCLE ====================

    @OnLifecycleEvent(Lifecycle.Event.ON_START)
    fun onStart() {
        Logger.debug(TAG, "Activity started")
        serviceConnection.bound(ctx)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_RESUME)
    fun onResume() {
        Logger.debug(TAG, "Activity resumed")
        serviceConnection.onResume(ctx)
        
        // Re-check permissions and state
        if (TrackingStateManager.wantsToTrack()) {
            Logger.debug(TAG, "App resumed and wants to track, checking permissions")
            PermissionChecker.logPermissionStatus(ctx)
            
            // Ask service to recheck permissions
            serviceConnection.service?.recheckPermissions()
        }
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_PAUSE)
    fun onPause() {
        Logger.debug(TAG, "Activity paused")
        serviceConnection.onPause(ctx)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
    fun onStop() {
        Logger.debug(TAG, "Activity stopped")
        serviceConnection.onStop(ctx)
    }

    // ==================== LOCATION UPDATES ====================

    override fun onLocationUpdate(location: Location) {
        // Forward to Flutter (only used when bound to service in foreground)
        FlutterBackgroundManager.sendLocation(ctx, location)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Not used
    }

    // ==================== CLEANUP ====================

    fun cleanup() {
        Logger.debug(TAG, "Cleaning up MethodCallHelper")
        serviceConnection.onStop(ctx)
        serviceConnection = LocationServiceConnection(this)
    }

    // ==================== COMPANION ====================

    companion object {
        private val TAG = MethodCallHelper::class.java.simpleName

        private var instance: MethodCallHelper? = null

        fun getInstance(ctx: Context): MethodCallHelper? {
            if (instance == null) {
                instance = MethodCallHelper(ctx)
            }
            return instance
        }
    }
}
