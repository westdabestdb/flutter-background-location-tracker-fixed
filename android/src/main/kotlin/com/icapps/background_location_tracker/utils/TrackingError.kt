package com.icapps.background_location_tracker.utils

/**
 * Tracking error types for reporting to Flutter
 */
internal sealed class TrackingError(
    val code: String,
    val message: String,
    val userMessage: String
) {
    
    class PermissionDenied : TrackingError(
        code = "permission_denied",
        message = "Location permission not granted",
        userMessage = "Please grant location permission to track your location"
    )
    
    class BackgroundPermissionDenied : TrackingError(
        code = "background_permission_denied",
        message = "Background location permission not granted (Android 10+)",
        userMessage = "Please grant 'Allow all the time' location permission for background tracking"
    )
    
    class NotificationPermissionDenied : TrackingError(
        code = "notification_permission_denied",
        message = "Notification permission not granted (Android 13+)",
        userMessage = "Please grant notification permission for background tracking"
    )
    
    class LocationDisabled : TrackingError(
        code = "location_disabled",
        message = "Location services are disabled",
        userMessage = "Please enable location services in your device settings"
    )
    
    class GooglePlayServicesUnavailable(val resultCode: Int) : TrackingError(
        code = "play_services_unavailable",
        message = "Google Play Services unavailable: $resultCode",
        userMessage = "Please update or enable Google Play Services"
    )
    
    class LocationSettingsInsufficient : TrackingError(
        code = "location_settings_insufficient",
        message = "Device location settings don't meet requirements",
        userMessage = "Please enable high accuracy location mode"
    )
    
    class LocationUnavailable : TrackingError(
        code = "location_unavailable",
        message = "Location is currently unavailable (GPS signal lost or location services disabled)",
        userMessage = "Location unavailable. Please ensure GPS signal is available."
    )
    
    class ServiceStartFailed(val reason: String) : TrackingError(
        code = "service_start_failed",
        message = "Failed to start location service: $reason",
        userMessage = "Failed to start location tracking. Please try again."
    )
    
    class ForegroundServiceRestricted : TrackingError(
        code = "foreground_service_restricted",
        message = "Cannot start foreground service due to Android 12+ restrictions",
        userMessage = "Background tracking restricted. Please open the app to start tracking."
    )
    
    class PreflightFailed(val issues: List<HealthCheck.HealthIssue>) : TrackingError(
        code = "preflight_failed",
        message = "Pre-flight checks failed: ${issues.joinToString(", ") { it.code }}",
        userMessage = "Cannot start tracking. ${issues.firstOrNull()?.userActionRequired ?: "Please check permissions and settings."}"
    )
    
    class AlreadyTracking : TrackingError(
        code = "already_tracking",
        message = "Location tracking is already active",
        userMessage = "Location tracking is already running"
    )
    
    class Unknown(val exception: Exception) : TrackingError(
        code = "unknown_error",
        message = "Unknown error: ${exception.message}",
        userMessage = "An unexpected error occurred. Please try again."
    )
    
    /**
     * Convert to map for sending to Flutter
     */
    fun toMap(): Map<String, Any> = mapOf(
        "code" to code,
        "message" to message,
        "userMessage" to userMessage,
        "timestamp" to System.currentTimeMillis()
    )
}

/**
 * Result type for operations that can fail
 */
internal sealed class Result<out T, out E> {
    data class Success<out T>(val value: T) : Result<T, Nothing>()
    data class Error<out E>(val error: E) : Result<Nothing, E>()
    
    inline fun <R> map(transform: (T) -> R): Result<R, E> = when (this) {
        is Success -> Success(transform(value))
        is Error -> Error(error)
    }
    
    inline fun onSuccess(action: (T) -> Unit): Result<T, E> {
        if (this is Success) action(value)
        return this
    }
    
    inline fun onError(action: (E) -> Unit): Result<T, E> {
        if (this is Error) action(error)
        return this
    }
}

