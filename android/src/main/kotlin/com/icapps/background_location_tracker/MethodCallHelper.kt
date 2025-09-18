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
import com.icapps.background_location_tracker.utils.Logger
import com.icapps.background_location_tracker.utils.NotificationUtil
import com.icapps.background_location_tracker.utils.SharedPrefsUtil
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class MethodCallHelper(private val ctx: Context) : MethodChannel.MethodCallHandler, LifecycleObserver, LocationUpdateListener {

    private var serviceConnection = LocationServiceConnection(this)
    private var isTrackingActive = false

    fun handle(call: MethodCall, result: MethodChannel.Result) = when (call.method) {
        "initialize" -> initialize(ctx, call, result)
        "isTracking" -> isTracking(ctx, call, result)
        "startTracking" -> startTracking(ctx, call, result)
        "stopTracking" -> stopTracking(ctx, call, result)
        "setTrackingActive" -> setTrackingActive(ctx, call, result)
        else -> result.error("404", "${call.method} is not supported", null)
    }

    private fun initialize(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
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
        SharedPrefsUtil.saveLoggingEnabled(ctx, loggingEnabled)
        SharedPrefsUtil.saveTrackingInterval(ctx, trackingInterval)
        SharedPrefsUtil.saveDistanceFilter(ctx, distanceFilter)
        Logger.enabled = loggingEnabled
        NotificationUtil.createNotificationChannels(ctx, channelName)
        SharedPrefsUtil.saveCallbackDispatcherHandleKey(ctx, callbackHandle)
        SharedPrefsUtil.saveNotificationConfig(ctx, notificationBody, notificationIcon, cancelTrackingActionText, enableNotificationLocationUpdates, enableCancelTrackingAction)
        result.success(true)
    }

    private fun getLongArgumentByKey(call: MethodCall, key: String): Long? {
        return try {
            call.argument<Number>(key)!!.toLong()
        } catch (exception: ClassCastException) {
            call.argument(key)
        }
    }

    private fun isTracking(ctx: Context, call: MethodCall, result: MethodChannel.Result) = result.success(SharedPrefsUtil.isTracking(ctx))

    private fun startTracking(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
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
        if (notificationBody != null || notificationIcon != null || cancelTrackingActionText != null
                || enableNotificationLocationUpdates != null || enableCancelTrackingAction != null) {
            SharedPrefsUtil.saveNotificationConfig(ctx, notificationBody ?: SharedPrefsUtil.getNotificationBody(ctx),
                                                   notificationIcon ?: SharedPrefsUtil.getNotificationIcon(ctx),
                                                   cancelTrackingActionText ?: SharedPrefsUtil.getCancelTrackingActionText(ctx),
                                                   enableNotificationLocationUpdates ?: SharedPrefsUtil.isNotificationLocationUpdatesEnabled(ctx),
                                                   enableCancelTrackingAction ?: SharedPrefsUtil.isCancelTrackingActionEnabled(ctx))
        }
        
        // Persist tracking intent BEFORE starting the service so a freshly created
        // service (after logout -> stopSelf) will auto-start in onCreate()
        SharedPrefsUtil.saveIsTracking(ctx, true)

        // Start the service immediately to avoid timing issues
        com.icapps.background_location_tracker.service.LocationUpdatesService.startServiceImmediately(ctx)
        
        // Ensure service connection is established and start tracking
        serviceConnection.bound(ctx)
        
        // Try to start tracking through service connection
        serviceConnection.service?.startTracking()
        result.success(true)
    }

    private fun stopTracking(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        // Persist stop intent immediately in case the service isn't currently bound/running
        SharedPrefsUtil.saveIsTracking(ctx, false)
        serviceConnection.service?.stopTracking()
        FlutterBackgroundManager.forceCleanup()
        result.success(true)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {}

    @OnLifecycleEvent(Lifecycle.Event.ON_START)
    fun onStart() {
        serviceConnection.bound(ctx)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_RESUME)
    fun onResume() {
        serviceConnection.onResume(ctx)
        
        // Re-check permissions when app resumes (user might have granted permission in settings)
        if (isTrackingActive) {
            Logger.debug(TAG, "App resumed, re-checking location permission")
            val hasLocationPermission = hasLocationPermission()
            Logger.debug(TAG, "Permission status on resume: $hasLocationPermission")
            
            if (hasLocationPermission) {
                handlePermissionGranted()
            }
            
            // Also ask the service to re-check permissions
            serviceConnection.service?.recheckPermissions()
        }
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_PAUSE)
    fun onPause() {
        serviceConnection.onPause(ctx)
    }

    @OnLifecycleEvent(Lifecycle.Event.ON_STOP)
    fun onStop() {
        serviceConnection.onStop(ctx)
    }

    override fun onLocationUpdate(location: Location) = FlutterBackgroundManager.sendLocation(ctx, location)

    private fun setTrackingActive(ctx: Context, call: MethodCall, result: MethodChannel.Result) {
        val isActive = call.argument<Boolean>("isActive") ?: false
        Logger.debug(TAG, "Setting tracking active state to: $isActive")
        
        isTrackingActive = isActive
        
        // Save the tracking active state
        SharedPrefsUtil.saveTrackingActive(ctx, isActive)
        
        // Notify the service about the tracking active state change
        serviceConnection.service?.setTrackingActive(isActive)
        
        if (isActive) {
            // Start monitoring location permission changes
            startPermissionMonitoring()
        } else {
            // Stop monitoring permission changes
            stopPermissionMonitoring()
        }
        
        result.success(true)
    }
    
    private fun startPermissionMonitoring() {
        Logger.debug(TAG, "Starting location permission monitoring")
        
        // Check current permission status
        val hasLocationPermission = hasLocationPermission()
        Logger.debug(TAG, "Current location permission status: $hasLocationPermission")
        
        // If already granted, start tracking immediately
        if (hasLocationPermission) {
            handlePermissionGranted()
        }
        
        // Note: For Android, we'll check permission status when the service tries to start
        // The service will handle the permission check and call handlePermissionGranted if needed
    }
    
    private fun stopPermissionMonitoring() {
        Logger.debug(TAG, "Stopping location permission monitoring")
        // Permission monitoring is handled by the service, no specific cleanup needed
    }
    
    private fun hasLocationPermission(): Boolean {
        return android.content.pm.PackageManager.PERMISSION_GRANTED == 
            ctx.checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) ||
            android.content.pm.PackageManager.PERMISSION_GRANTED == 
            ctx.checkSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION)
    }
    
    private fun handlePermissionGranted() {
        if (!isTrackingActive) {
            Logger.debug(TAG, "Permission granted but tracking is not active, skipping auto-start")
            return
        }
        
        Logger.debug(TAG, "Location permission granted and tracking is active, starting tracking")
        
        // Ensure background manager is ready before starting tracking
        FlutterBackgroundManager.ensureInitialized(ctx)
        
        // Start tracking automatically
        startTracking(ctx, MethodCall("startTracking", null)) { result ->
            if (result is Boolean && result) {
                Logger.debug(TAG, "Auto-started background location tracking")
            } else {
                Logger.debug(TAG, "Failed to auto-start tracking")
            }
        }
    }

    fun cleanup() {
        Logger.debug(TAG, "Cleaning up MethodCallHelper")
        serviceConnection.onStop(ctx)
        serviceConnection = LocationServiceConnection(this)
    }

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
