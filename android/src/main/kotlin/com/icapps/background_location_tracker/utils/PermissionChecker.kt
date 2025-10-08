package com.icapps.background_location_tracker.utils

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat

/**
 * Comprehensive permission checker for location tracking.
 * Handles all permission types needed for foreground and background tracking.
 */
internal object PermissionChecker {
    
    /**
     * Result of permission check with detailed information
     */
    data class PermissionCheckResult(
        val hasForegroundPermission: Boolean,
        val hasBackgroundPermission: Boolean,
        val hasNotificationPermission: Boolean,
        val isLocationEnabled: Boolean,
        val canTrackInForeground: Boolean,
        val canTrackInBackground: Boolean,
        val missingPermissions: List<String>,
        val recommendations: List<String>
    ) {
        val isFullyGranted: Boolean
            get() = canTrackInBackground && isLocationEnabled
        
        val canStartTracking: Boolean
            get() = canTrackInForeground && isLocationEnabled
    }
    
    /**
     * Perform comprehensive permission check
     */
    fun checkPermissions(context: Context): PermissionCheckResult {
        val hasForeground = hasForegroundLocationPermission(context)
        val hasBackground = hasBackgroundLocationPermission(context)
        val hasNotification = hasNotificationPermission(context)
        val locationEnabled = isLocationEnabled(context)
        
        val canForeground = hasForeground && locationEnabled
        val canBackground = hasForeground && hasBackground && locationEnabled && 
                           (hasNotification || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU)
        
        val missing = mutableListOf<String>()
        val recommendations = mutableListOf<String>()
        
        // Check what's missing
        if (!hasForeground) {
            missing.add("ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION")
            recommendations.add("Grant location permission in app settings")
        }
        
        if (!hasBackground && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            missing.add("ACCESS_BACKGROUND_LOCATION")
            recommendations.add("Grant 'Allow all the time' location permission in app settings")
        }
        
        if (!hasNotification && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            missing.add("POST_NOTIFICATIONS")
            recommendations.add("Grant notification permission for background tracking")
        }
        
        if (!locationEnabled) {
            recommendations.add("Enable location services in device settings")
        }
        
        return PermissionCheckResult(
            hasForegroundPermission = hasForeground,
            hasBackgroundPermission = hasBackground,
            hasNotificationPermission = hasNotification,
            isLocationEnabled = locationEnabled,
            canTrackInForeground = canForeground,
            canTrackInBackground = canBackground,
            missingPermissions = missing,
            recommendations = recommendations
        )
    }
    
    /**
     * Check if foreground location permission is granted
     */
    fun hasForegroundLocationPermission(context: Context): Boolean {
        val hasFine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        val hasCoarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        return hasFine || hasCoarse
    }
    
    /**
     * Check if background location permission is granted (Android 10+)
     */
    fun hasBackgroundLocationPermission(context: Context): Boolean {
        // Background permission only needed on Android 10+
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return true // Not required on older versions
        }
        
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Check if notification permission is granted (Android 13+)
     */
    fun hasNotificationPermission(context: Context): Boolean {
        // Notification permission only needed on Android 13+
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true // Not required on older versions
        }
        
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }
    
    /**
     * Check if location services are enabled on the device
     */
    fun isLocationEnabled(context: Context): Boolean {
        val locationManager = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            ?: return false
        
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Use isLocationEnabled on Android 9+
            locationManager.isLocationEnabled
        } else {
            // Check individual providers on older versions
            val gpsEnabled = try {
                locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
            } catch (e: Exception) {
                false
            }
            
            val networkEnabled = try {
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            } catch (e: Exception) {
                false
            }
            
            gpsEnabled || networkEnabled
        }
    }
    
    /**
     * Get required permissions for the current Android version
     */
    fun getRequiredPermissions(): List<String> {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION
        )
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissions.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        
        return permissions
    }
    
    /**
     * Log current permission status for debugging
     */
    fun logPermissionStatus(context: Context) {
        val result = checkPermissions(context)
        
        Logger.debug("PermissionChecker", "=== Permission Status ===")
        Logger.debug("PermissionChecker", "Foreground: ${result.hasForegroundPermission}")
        Logger.debug("PermissionChecker", "Background: ${result.hasBackgroundPermission} (required: ${Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q})")
        Logger.debug("PermissionChecker", "Notification: ${result.hasNotificationPermission} (required: ${Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU})")
        Logger.debug("PermissionChecker", "Location Enabled: ${result.isLocationEnabled}")
        Logger.debug("PermissionChecker", "Can Track Foreground: ${result.canTrackInForeground}")
        Logger.debug("PermissionChecker", "Can Track Background: ${result.canTrackInBackground}")
        
        if (result.missingPermissions.isNotEmpty()) {
            Logger.warning("PermissionChecker", "Missing permissions: ${result.missingPermissions.joinToString(", ")}")
        }
        
        if (result.recommendations.isNotEmpty()) {
            Logger.warning("PermissionChecker", "Recommendations:")
            result.recommendations.forEach { recommendation ->
                Logger.warning("PermissionChecker", "  - $recommendation")
            }
        }
    }
}

