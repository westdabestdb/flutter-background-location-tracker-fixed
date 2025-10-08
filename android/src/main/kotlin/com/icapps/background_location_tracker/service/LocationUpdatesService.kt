package com.icapps.background_location_tracker.service

import android.app.ActivityManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.location.Location
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.icapps.background_location_tracker.flutter.FlutterBackgroundManager
import com.icapps.background_location_tracker.utils.*
import java.io.PrintWriter
import java.io.StringWriter

private const val WAKELOCK_TIMEOUT = 10 * 60 * 1000L // 10 minutes

/**
 * Service for location updates in foreground and background.
 * Refactored with consolidated startup logic, comprehensive error handling,
 * and centralized state management.
 */
internal class LocationUpdatesService : Service() {
    private val binder: IBinder = LocalBinder()
    
    // Lifecycle state
    private var changingConfiguration = false
    
    // Location components
    private var locationRequest: LocationRequest? = null
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var location: Location? = null
    
    // Power management
    private var wakeLock: PowerManager.WakeLock? = null
    
    // Track if we've already requested location updates (prevent duplicates)
    private var hasActiveLocationRequest = false

    override fun onCreate() {
        Logger.debug(TAG, "=== Service onCreate ===")
        
        // Initialize state manager
        TrackingStateManager.initialize(this)
        
        // Initialize location components
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createLocationCallback()
        createLocationRequest()
        wakeLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "blt:location_updates")
        
        // Get last known location
        getLastLocation()
        
        // Check if we should auto-start tracking
        handleServiceCreated()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Logger.debug(TAG, "Service started via onStartCommand")
        
        val startedFromNotification = intent?.getBooleanExtra(
            EXTRA_STARTED_FROM_NOTIFICATION,
            false
        ) ?: false

        if (startedFromNotification) {
            // User tapped "Stop" in notification
            Logger.debug(TAG, "Stop requested from notification")
            stopTracking()
            stopSelf()
            return START_NOT_STICKY
        }

        // Service restarted by system or started explicitly
        return START_STICKY
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        changingConfiguration = true
    }

    override fun onBind(intent: Intent): IBinder {
        Logger.debug(TAG, "Client bound to service")
        changingConfiguration = false
        
        // Don't stop foreground if actively tracking
        if (!TrackingStateManager.isTracking()) {
            stopForegroundService()
        }
        
        return binder
    }

    override fun onRebind(intent: Intent) {
        Logger.debug(TAG, "Client rebound to service")
        changingConfiguration = false
        
        if (!TrackingStateManager.isTracking()) {
            stopForegroundService()
        }
        
        super.onRebind(intent)
    }

    override fun onUnbind(intent: Intent): Boolean {
        Logger.debug(TAG, "Last client unbound from service")

        try {
            if (!changingConfiguration && TrackingStateManager.isTracking()) {
                Logger.debug(TAG, "Ensuring foreground service continues")
                ensureForegroundService()
            }
        } catch (e: Throwable) {
            val sw = StringWriter()
            val pw = PrintWriter(sw)
            e.printStackTrace(pw)
            pw.flush()
            Logger.error(TAG, "onUnbind failed: ${sw}")
        }

        return true // Ensures onRebind() is called
    }

    override fun onDestroy() {
        Logger.debug(TAG, "=== Service onDestroy ===")
        releaseWakeLock()
        
        // Clean up Flutter background resources
        FlutterBackgroundManager.forceCleanup()
    }

    // ==================== CONSOLIDATED STARTUP LOGIC ====================
    
    /**
     * Handle service creation - decide if we should auto-start tracking
     */
    private fun handleServiceCreated() {
        Logger.debug(TAG, "Handling service created, checking if should auto-start")
        
        val state = TrackingStateManager.getState()
        Logger.debug(TAG, "Current state: ${state::class.simpleName}")
        
        when (state) {
            is TrackingStateManager.TrackingState.Starting,
            is TrackingStateManager.TrackingState.Running -> {
                // We were tracking before, try to restart
                Logger.debug(TAG, "Was tracking before service restart, attempting to resume")
                startLocationTrackingInternal("service_restart")
            }
            is TrackingStateManager.TrackingState.WaitingForPermission -> {
                // Check if permission is now available
                if (PermissionChecker.hasForegroundLocationPermission(this)) {
                    Logger.debug(TAG, "Permission now available, attempting to start")
                    startLocationTrackingInternal("permission_granted")
                } else {
                    Logger.debug(TAG, "Still waiting for permission")
                }
            }
            else -> {
                Logger.debug(TAG, "State is ${state::class.simpleName}, not auto-starting")
            }
        }
    }

    /**
     * MAIN ENTRY POINT: Start location tracking
     * This is the ONLY method that actually starts location updates.
     * All other entry points must call this method.
     */
    fun startTracking() {
        startLocationTrackingInternal("direct_call")
    }
    
    /**
     * Internal consolidated startup logic with all safety checks
     */
    private fun startLocationTrackingInternal(source: String): Result<Unit, TrackingError> {
        Logger.debug(TAG, "=== startLocationTrackingInternal from: $source ===")
        
        // STEP 1: Check if already tracking (prevent duplicates)
        if (hasActiveLocationRequest) {
            Logger.debug(TAG, "Already have active location request, ignoring duplicate start")
            return Result.Success(Unit)
        }
        
        if (TrackingStateManager.getState() is TrackingStateManager.TrackingState.Running) {
            Logger.debug(TAG, "Already in Running state, ignoring duplicate start")
            return Result.Success(Unit)
        }
        
        // STEP 2: Update state to Starting
        TrackingStateManager.setState(TrackingStateManager.TrackingState.Starting, this)
        
        // STEP 3: Perform comprehensive health check
        Logger.debug(TAG, "Performing health check...")
        val healthCheck = HealthCheck.performHealthCheck(this)
        HealthCheck.logHealthCheck(this)
        
        if (!healthCheck.canStartTracking) {
            Logger.error(TAG, "Health check failed with ${healthCheck.criticalIssues.size} critical issues")
            
            // Determine specific error
            val error = when {
                healthCheck.criticalIssues.any { it.code == "play_services_missing" || it.code == "play_services_outdated" } -> {
                    val issue = healthCheck.criticalIssues.first { it.code.startsWith("play_services") }
                    TrackingError.GooglePlayServicesUnavailable(0)
                }
                healthCheck.criticalIssues.any { it.code == "no_location_permission" } -> {
                    TrackingError.PermissionDenied()
                }
                healthCheck.criticalIssues.any { it.code == "no_background_permission" } -> {
                    TrackingError.BackgroundPermissionDenied()
                }
                healthCheck.criticalIssues.any { it.code == "no_notification_permission" } -> {
                    TrackingError.NotificationPermissionDenied()
                }
                healthCheck.criticalIssues.any { it.code == "location_disabled" } -> {
                    TrackingError.LocationDisabled()
                }
                else -> {
                    TrackingError.PreflightFailed(healthCheck.criticalIssues)
                }
            }
            
            // Update state and report error
            TrackingStateManager.setState(
                TrackingStateManager.TrackingState.Error(error.code, error.message),
                this
            )
            FlutterBackgroundManager.sendTrackingError(this, error)
            
            return Result.Error(error)
        }
        
        // STEP 4: Ensure Flutter background manager is initialized
        FlutterBackgroundManager.ensureInitialized(this)
        
        // STEP 5: Start as foreground service (required for background tracking)
        val foregroundResult = ensureForegroundService()
        if (foregroundResult is Result.Error) {
            TrackingStateManager.setState(
                TrackingStateManager.TrackingState.Error(foregroundResult.error.code, foregroundResult.error.message),
                this
            )
            return foregroundResult
        }
        
        // STEP 6: Acquire wake lock
        acquireWakeLock()
        
        // STEP 7: Actually request location updates
        val requestResult = requestLocationUpdatesInternal()
        
        return when (requestResult) {
            is Result.Success -> {
                Logger.debug(TAG, "✓ Location tracking started successfully")
                hasActiveLocationRequest = true
                
                // State will transition to Running when first location is received
                // For now, keep it in Starting state
                
                Result.Success(Unit)
            }
            is Result.Error -> {
                // Clean up on failure
                releaseWakeLock()
                stopForegroundService()
                TrackingStateManager.setState(
                    TrackingStateManager.TrackingState.Error(requestResult.error.code, requestResult.error.message),
                    this
                )
                FlutterBackgroundManager.sendTrackingError(this, requestResult.error)
                
                requestResult
            }
        }
    }
    
    /**
     * Actually request location updates from FusedLocationProvider
     */
    private fun requestLocationUpdatesInternal(): Result<Unit, TrackingError> {
        val request = locationRequest
        val callback = locationCallback
        val client = fusedLocationClient
        
        if (request == null || callback == null || client == null) {
            val error = TrackingError.ServiceStartFailed("Location components not initialized")
            Logger.error(TAG, error.message)
            return Result.Error(error)
        }
        
        try {
            Logger.debug(TAG, "Requesting location updates from FusedLocationProvider")
            
            // Use main looper to avoid null issues
            client.requestLocationUpdates(
                request,
                callback,
                Looper.getMainLooper()
            )
            
            Logger.debug(TAG, "Location updates requested successfully")
            return Result.Success(Unit)
            
        } catch (e: SecurityException) {
            val error = TrackingError.PermissionDenied()
            Logger.error(TAG, "SecurityException: ${e.message}")
            return Result.Error(error)
            
        } catch (e: Exception) {
            val error = TrackingError.Unknown(e)
            Logger.error(TAG, "Exception requesting location updates: ${e.message}")
            return Result.Error(error)
        }
    }

    // ==================== STOP TRACKING ====================

    /**
     * Stop location tracking
     */
    fun stopTracking() {
        Logger.debug(TAG, "=== stopTracking ===")
        
        // Update state
        TrackingStateManager.setState(TrackingStateManager.TrackingState.Stopping, this)
        
        // Release wake lock
        releaseWakeLock()
        
        // Remove location updates
        val callback = locationCallback
        if (callback != null) {
            try {
                fusedLocationClient?.removeLocationUpdates(callback)
                Logger.debug(TAG, "Location updates removed")
                hasActiveLocationRequest = false
            } catch (e: SecurityException) {
                Logger.error(TAG, "SecurityException removing updates: ${e.message}")
            } catch (e: Exception) {
                Logger.error(TAG, "Exception removing updates: ${e.message}")
            }
        }
        
        // Reset counters
        TrackingStateManager.resetCounters()
        
        // Update to Stopped state
        TrackingStateManager.setState(TrackingStateManager.TrackingState.Stopped, this)
        
        // Stop self
        stopSelf()
    }

    // ==================== PERMISSION MONITORING ====================
    
    /**
     * Re-check permissions (called when app resumes)
     */
    fun recheckPermissions() {
        Logger.debug(TAG, "Re-checking permissions due to app lifecycle change")
        
        val state = TrackingStateManager.getState()
        
        // Only restart if we're in a waiting state and now have permission
        if (state is TrackingStateManager.TrackingState.WaitingForPermission) {
            if (PermissionChecker.hasForegroundLocationPermission(this)) {
                Logger.debug(TAG, "Permission granted, restarting tracking")
                startLocationTrackingInternal("permission_recheck")
            } else {
                Logger.debug(TAG, "Still no permission")
            }
        }
    }

    // ==================== LOCATION CALLBACK ====================
    
    /**
     * Create location callback with error handling
     */
    private fun createLocationCallback() {
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                super.onLocationResult(locationResult)
                val newLocation = locationResult.lastLocation
                if (newLocation != null) {
                    onNewLocation(newLocation)
                }
            }
            
            /**
             * IMPORTANT: Handle location availability changes
             * This catches when GPS is lost, location services disabled, etc.
             */
            override fun onLocationAvailability(availability: LocationAvailability) {
                super.onLocationAvailability(availability)
                
                if (!availability.isLocationAvailable) {
                    Logger.warning(TAG, "⚠️ Location became unavailable")
                    
                    val error = TrackingError.LocationUnavailable()
                    FlutterBackgroundManager.sendTrackingError(applicationContext, error)
                    
                    // Update state but don't stop tracking - might recover
                    TrackingStateManager.setState(
                        TrackingStateManager.TrackingState.Error(error.code, error.message),
                        applicationContext
                    )
                } else {
                    Logger.debug(TAG, "✓ Location is available again")
                    
                    // If we were in error state due to unavailability, transition back to Starting
                    val currentState = TrackingStateManager.getState()
                    if (currentState is TrackingStateManager.TrackingState.Error && 
                        currentState.errorCode == "location_unavailable") {
                        TrackingStateManager.setState(
                            TrackingStateManager.TrackingState.Starting,
                            applicationContext
                        )
                    }
                }
            }
        }
    }
    
    /**
     * Handle new location update
     */
    private fun onNewLocation(newLocation: Location) {
        Logger.debug(TAG, "New location: ${newLocation.latitude}, ${newLocation.longitude}")
        location = newLocation
        
        // Record location update in state manager
        TrackingStateManager.recordLocationUpdate(this)
        
        // Send to Flutter (handles both foreground and background)
        FlutterBackgroundManager.sendLocation(applicationContext, newLocation)
        
        // Update notification if enabled
        if (SharedPrefsUtil.isNotificationLocationUpdatesEnabled(applicationContext)) {
            Logger.debug(TAG, "Updating notification with location")
            NotificationUtil.showNotification(this, newLocation)
        }
    }

    // ==================== HELPER METHODS ====================

    /**
     * Create location request configuration
     */
    private fun createLocationRequest() {
        val interval = SharedPrefsUtil.trackingInterval(this)
        val distanceFilter = SharedPrefsUtil.distanceFilter(this)
        
        locationRequest = LocationRequest.create()
            .setInterval(interval)
            .setFastestInterval(interval / 2)
            .setPriority(Priority.PRIORITY_HIGH_ACCURACY)
            .setSmallestDisplacement(distanceFilter)
        
        Logger.debug(TAG, "Location request created: interval=${interval}ms, distance=${distanceFilter}m")
    }

    /**
     * Get last known location
     */
    private fun getLastLocation() {
        try {
            fusedLocationClient?.lastLocation?.addOnCompleteListener { task ->
                if (task.isSuccessful && task.result != null) {
                    location = task.result
                    Logger.debug(TAG, "Got last known location")
                } else {
                    Logger.warning(TAG, "Failed to get last location")
                }
            }
        } catch (unlikely: SecurityException) {
            Logger.error(TAG, "SecurityException getting last location: ${unlikely.message}")
        }
    }
    
    /**
     * Ensure service is running in foreground
     */
    private fun ensureForegroundService(): Result<Unit, TrackingError> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                Logger.debug(TAG, "Starting foreground service")
                NotificationUtil.startForeground(this, location)
                return Result.Success(Unit)
                
            } catch (e: Exception) {
                Logger.error(TAG, "Failed to start foreground service: ${e.message}")
                
                val error = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && 
                               e::class.simpleName == "ForegroundServiceStartNotAllowedException") {
                    TrackingError.ForegroundServiceRestricted()
                } else {
                    TrackingError.ServiceStartFailed(e.message ?: "Unknown error")
                }
                
                return Result.Error(error)
            }
        }
        
        return Result.Success(Unit)
    }
    
    /**
     * Stop foreground service
     */
    private fun stopForegroundService() {
        Logger.debug(TAG, "Stopping foreground service")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
    
    /**
     * Acquire wake lock for processing
     */
    private fun acquireWakeLock() {
        if (wakeLock?.isHeld != true) {
            wakeLock?.acquire(WAKELOCK_TIMEOUT)
            Logger.debug(TAG, "WakeLock acquired")
        }
    }
    
    /**
     * Release wake lock
     */
    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
            Logger.debug(TAG, "WakeLock released")
        }
    }

    // ==================== BINDER ====================

    inner class LocalBinder : Binder() {
        val service: LocationUpdatesService
            get() = this@LocationUpdatesService
    }

    // ==================== COMPANION ====================

    companion object {
        private const val PACKAGE_NAME = "com.icapps.background_location_tracker"
        private val TAG = LocationUpdatesService::class.java.simpleName

        const val ACTION_BROADCAST = "$PACKAGE_NAME.broadcast"
        const val EXTRA_LOCATION = "$PACKAGE_NAME.location"
        const val EXTRA_STARTED_FROM_NOTIFICATION = "$PACKAGE_NAME.started_from_notification"

        /**
         * Start service immediately
         */
        @JvmStatic
        fun startServiceImmediately(context: Context) {
            try {
                val intent = Intent(context, LocationUpdatesService::class.java)
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                
                Logger.debug(TAG, "Service started immediately")
            } catch (e: Exception) {
                Logger.error(TAG, "Failed to start service: ${e.message}")
            }
        }
    }
}
