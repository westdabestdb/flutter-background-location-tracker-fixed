package com.icapps.background_location_tracker.utils

import android.content.Context
import android.os.Build
import android.os.PowerManager
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability

/**
 * Health check system for location tracking.
 * Validates all prerequisites for successful tracking.
 */
internal object HealthCheck {
    
    /**
     * Severity levels for health issues
     */
    enum class Severity {
        CRITICAL,  // Prevents tracking completely
        WARNING,   // May affect tracking reliability
        INFO       // Informational, doesn't affect tracking
    }
    
    /**
     * Represents a single health issue
     */
    data class HealthIssue(
        val severity: Severity,
        val code: String,
        val message: String,
        val userActionRequired: String?
    )
    
    /**
     * Result of health check
     */
    data class HealthCheckResult(
        val isHealthy: Boolean,
        val issues: List<HealthIssue>,
        val canStartTracking: Boolean
    ) {
        val criticalIssues: List<HealthIssue>
            get() = issues.filter { it.severity == Severity.CRITICAL }
        
        val warnings: List<HealthIssue>
            get() = issues.filter { it.severity == Severity.WARNING }
        
        val info: List<HealthIssue>
            get() = issues.filter { it.severity == Severity.INFO }
    }
    
    /**
     * Perform comprehensive health check
     */
    fun performHealthCheck(context: Context): HealthCheckResult {
        val issues = mutableListOf<HealthIssue>()
        
        // Check Google Play Services
        checkGooglePlayServices(context, issues)
        
        // Check permissions
        checkPermissions(context, issues)
        
        // Check location services
        checkLocationServices(context, issues)
        
        // Check battery optimization
        checkBatteryOptimization(context, issues)
        
        // Check OEM-specific issues
        checkOEMIssues(context, issues)
        
        // Check tracking state consistency
        checkStateConsistency(context, issues)
        
        val hasNoCriticalIssues = issues.none { it.severity == Severity.CRITICAL }
        val canStart = hasNoCriticalIssues
        
        return HealthCheckResult(
            isHealthy = issues.isEmpty(),
            issues = issues,
            canStartTracking = canStart
        )
    }
    
    /**
     * Check Google Play Services availability
     */
    private fun checkGooglePlayServices(context: Context, issues: MutableList<HealthIssue>) {
        val availability = GoogleApiAvailability.getInstance()
        val resultCode = availability.isGooglePlayServicesAvailable(context)
        
        when (resultCode) {
            ConnectionResult.SUCCESS -> {
                // All good
            }
            ConnectionResult.SERVICE_MISSING -> {
                issues.add(HealthIssue(
                    Severity.CRITICAL,
                    "play_services_missing",
                    "Google Play Services is not installed",
                    "Install Google Play Services from the Play Store"
                ))
            }
            ConnectionResult.SERVICE_VERSION_UPDATE_REQUIRED -> {
                issues.add(HealthIssue(
                    Severity.CRITICAL,
                    "play_services_outdated",
                    "Google Play Services needs to be updated",
                    "Update Google Play Services in the Play Store"
                ))
            }
            ConnectionResult.SERVICE_DISABLED -> {
                issues.add(HealthIssue(
                    Severity.CRITICAL,
                    "play_services_disabled",
                    "Google Play Services is disabled",
                    "Enable Google Play Services in device settings"
                ))
            }
            else -> {
                issues.add(HealthIssue(
                    Severity.CRITICAL,
                    "play_services_error",
                    "Google Play Services error: $resultCode",
                    "Check Google Play Services in device settings"
                ))
            }
        }
    }
    
    /**
     * Check all required permissions
     */
    private fun checkPermissions(context: Context, issues: MutableList<HealthIssue>) {
        val permissionResult = PermissionChecker.checkPermissions(context)
        
        if (!permissionResult.hasForegroundPermission) {
            issues.add(HealthIssue(
                Severity.CRITICAL,
                "no_location_permission",
                "Location permission not granted",
                "Grant location permission in app settings"
            ))
        }
        
        if (!permissionResult.hasBackgroundPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            issues.add(HealthIssue(
                Severity.CRITICAL,
                "no_background_permission",
                "Background location permission not granted (Android 10+ required)",
                "Grant 'Allow all the time' permission in app settings"
            ))
        }
        
        if (!permissionResult.hasNotificationPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            issues.add(HealthIssue(
                Severity.CRITICAL,
                "no_notification_permission",
                "Notification permission required for background tracking (Android 13+)",
                "Grant notification permission in app settings"
            ))
        }
    }
    
    /**
     * Check location services
     */
    private fun checkLocationServices(context: Context, issues: MutableList<HealthIssue>) {
        if (!PermissionChecker.isLocationEnabled(context)) {
            issues.add(HealthIssue(
                Severity.CRITICAL,
                "location_disabled",
                "Location services are disabled on the device",
                "Enable location in device settings"
            ))
        }
    }
    
    /**
     * Check battery optimization status
     */
    private fun checkBatteryOptimization(context: Context, issues: MutableList<HealthIssue>) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
            
            if (!isIgnoring) {
                issues.add(HealthIssue(
                    Severity.WARNING,
                    "battery_optimization_enabled",
                    "Battery optimization may stop background tracking",
                    "Disable battery optimization for this app in device settings"
                ))
            }
        }
    }
    
    /**
     * Check for OEM-specific battery management issues
     */
    private fun checkOEMIssues(context: Context, issues: MutableList<HealthIssue>) {
        val manufacturer = Build.MANUFACTURER.lowercase()
        
        val aggressiveOEMs = mapOf(
            "xiaomi" to "MIUI battery saver may kill background tracking. Add app to autostart and disable battery restrictions.",
            "huawei" to "EMUI PowerGenie may kill background apps. Add app to protected apps list.",
            "honor" to "Magic UI may kill background apps. Add app to protected apps list.",
            "samsung" to "Device Care may optimize background apps. Disable optimization for this app.",
            "oppo" to "ColorOS battery management may kill background apps. Add app to startup list.",
            "vivo" to "FuntouchOS may restrict background apps. Allow background activity for this app.",
            "realme" to "Realme UI may restrict background apps. Disable battery optimization.",
            "oneplus" to "OxygenOS battery optimization is aggressive. Disable for this app."
        )
        
        aggressiveOEMs[manufacturer]?.let { recommendation ->
            issues.add(HealthIssue(
                Severity.WARNING,
                "oem_battery_management",
                "${Build.MANUFACTURER} devices have aggressive battery management",
                recommendation
            ))
        }
    }
    
    /**
     * Check for state consistency issues
     */
    private fun checkStateConsistency(context: Context, issues: MutableList<HealthIssue>) {
        val isTrackingPref = SharedPrefsUtil.isTracking(context)
        val stateManagerTracking = TrackingStateManager.isTracking()
        
        if (isTrackingPref != stateManagerTracking) {
            issues.add(HealthIssue(
                Severity.WARNING,
                "inconsistent_state",
                "Tracking state is inconsistent between preferences and state manager",
                "Restart tracking to resolve inconsistency"
            ))
        }
    }
    
    /**
     * Log health check results
     */
    fun logHealthCheck(context: Context) {
        val result = performHealthCheck(context)
        
        Logger.debug("HealthCheck", "=== Health Check Results ===")
        Logger.debug("HealthCheck", "Overall Health: ${if (result.isHealthy) "HEALTHY ✓" else "ISSUES FOUND ✗"}")
        Logger.debug("HealthCheck", "Can Start Tracking: ${if (result.canStartTracking) "YES ✓" else "NO ✗"}")
        Logger.debug("HealthCheck", "Total Issues: ${result.issues.size}")
        
        if (result.criticalIssues.isNotEmpty()) {
            Logger.error("HealthCheck", "=== CRITICAL ISSUES (${result.criticalIssues.size}) ===")
            result.criticalIssues.forEach { issue ->
                Logger.error("HealthCheck", "[${issue.code}] ${issue.message}")
                issue.userActionRequired?.let { action ->
                    Logger.error("HealthCheck", "  → Action: $action")
                }
            }
        }
        
        if (result.warnings.isNotEmpty()) {
            Logger.warning("HealthCheck", "=== WARNINGS (${result.warnings.size}) ===")
            result.warnings.forEach { issue ->
                Logger.warning("HealthCheck", "[${issue.code}] ${issue.message}")
                issue.userActionRequired?.let { action ->
                    Logger.warning("HealthCheck", "  → Action: $action")
                }
            }
        }
        
        if (result.info.isNotEmpty()) {
            Logger.debug("HealthCheck", "=== INFO (${result.info.size}) ===")
            result.info.forEach { issue ->
                Logger.debug("HealthCheck", "[${issue.code}] ${issue.message}")
            }
        }
        
        Logger.debug("HealthCheck", "=========================")
    }
    
    /**
     * Get health check results as a map for Flutter
     */
    fun getHealthCheckMap(context: Context): Map<String, Any> {
        val result = performHealthCheck(context)
        
        return mapOf(
            "isHealthy" to result.isHealthy,
            "canStartTracking" to result.canStartTracking,
            "criticalIssues" to result.criticalIssues.map { issueToMap(it) },
            "warnings" to result.warnings.map { issueToMap(it) },
            "info" to result.info.map { issueToMap(it) }
        )
    }
    
    private fun issueToMap(issue: HealthIssue): Map<String, Any?> = mapOf(
        "severity" to issue.severity.name,
        "code" to issue.code,
        "message" to issue.message,
        "userActionRequired" to issue.userActionRequired
    )
}

