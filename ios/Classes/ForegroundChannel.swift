//
//  ForegroundChannel.swift
//  background_location_tracker
//
//  Created by Dimmy Maenhout on 17/12/2020.
//

import Foundation
import CoreLocation
import Flutter

fileprivate enum ForegroundMethods: String {
    case initialize = "initialize"
    case isTracking = "isTracking"
    case startTracking = "startTracking"
    case stopTracking = "stopTracking"
    case setDriveActive = "setDriveActive"
}

public class ForegroundChannel : NSObject {
    
    private var isTracking = false
    private var isDriveActive = false
    private static let FOREGROUND_CHANNEL_NAME = "com.icapps.background_location_tracker/foreground_channel"
    
    private let locationManager = LocationManager.shared()
    
    private let userDefaults = UserDefaults.standard
    
    // This method is kept for backwards compatibility but marked as deprecated
    @available(*, deprecated, message: "Use createMethodChannel(binaryMessenger:) instead")
    public static func getMethodChannel(with registrar: FlutterPluginRegistrar) -> FlutterMethodChannel {
        return createMethodChannel(binaryMessenger: registrar.messenger())
    }
    
    // New method that works with FlutterBinaryMessenger directly
    public static func createMethodChannel(binaryMessenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
        return FlutterMethodChannel(name: FOREGROUND_CHANNEL_NAME, binaryMessenger: binaryMessenger)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case ForegroundMethods.initialize.rawValue:
            initialize(call: call, result: result)
        case ForegroundMethods.isTracking.rawValue:
            isTracking(result)
        case ForegroundMethods.startTracking.rawValue:
            startTracking(result)
        case ForegroundMethods.stopTracking.rawValue:
            stopTracking(result)
        case ForegroundMethods.setDriveActive.rawValue:
            setDriveActive(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - private methods
    
    private func initialize(call: FlutterMethodCall, result: @escaping FlutterResult ) {
        print("🚨 FOREGROUND CHANNEL: Initialize method called")
        let callBackHandleKey = "callback_handle"
        let loggingEnabledKey = "logging_enabled"
        let activityTypeKey = "ios_activity_type"
        let distanceFilterKey = "ios_distance_filter"
        let restartAfterKillKey = "ios_restart_after_kill"
        let map = call.arguments as? [String: Any]
        print("🚨 FOREGROUND CHANNEL: Arguments map: \(map ?? [:])")
        guard let callbackDispatcherHandle = map?[callBackHandleKey] else {
            print("🚨 FOREGROUND CHANNEL: No callback handle found in arguments")
            result(false)
            return
        }
        print("🚨 FOREGROUND CHANNEL: Callback handle found: \(callbackDispatcherHandle)")
        
        
        let loggingEnabled: Bool = map?[loggingEnabledKey] as? Bool ?? false
        SharedPrefsUtil.saveLoggingEnabled(loggingEnabled)
        SharedPrefsUtil.saveRestartAfterKillEnabled(map?[restartAfterKillKey] as? Bool ?? false)
        
        let activityType: CLActivityType
        switch (map?[activityTypeKey] as? String ?? "AUTOMOTIVE") {
        case "OTHER":
            activityType = .other
        case "FITNESS":
            activityType = .fitness
        case "NAVIGATION":
            activityType = .otherNavigation
        case "AIRBORNE":
            if #available(iOS 12.0, *) {
                activityType = .airborne
            } else {
                activityType = .automotiveNavigation
            }
        case "AUTOMOTIVE":
            activityType = .automotiveNavigation
        default:
            activityType = .automotiveNavigation
        }
        
        SharedPrefsUtil.saveActivityType(activityType)
        SharedPrefsUtil.saveDistanceFilter(map?[distanceFilterKey] as? Double ?? kCLDistanceFilterNone)
        
        let callbackHandle = callbackDispatcherHandle as? Int64
        CustomLogger.logCritical(message: "🚨 INITIALIZE: Saving callback handle: \(callbackHandle ?? -1)")
        SharedPrefsUtil.saveCallBackDispatcherHandleKey(callBackHandle: callbackHandle)
        
        // Verify the callback handle was saved
        let savedHandle = SharedPrefsUtil.getCallbackHandle()
        CustomLogger.logCritical(message: "🚨 INITIALIZE: Saved callback handle verification: \(savedHandle ?? -1)")
        
        SharedPrefsUtil.saveIsTracking(isTracking)
        result(true)
    }
    
    private func startTracking(_ result: @escaping FlutterResult) {
        CustomLogger.logCritical(message: "=== START TRACKING STARTED ===")
        CustomLogger.logAlways(message: "Current location manager status: \(LocationManager.getCurrentStatus())")
        CustomLogger.logAlways(message: "Status bar indicator should be visible: \(LocationManager.shouldShowStatusBarIndicator())")
        CustomLogger.logAlways(message: "needsReactivation check: \(LocationManager.needsReactivation())")
        
        // CRITICAL: Check if this is a restoration attempt after app restart
        let isRestorationAttempt = SharedPrefsUtil.isTracking() && LocationManager.needsRestoration()
        if isRestorationAttempt {
            // Use the comprehensive restoration method for app restart scenarios
            SwiftBackgroundLocationTrackerPlugin.restoreLocationTrackingState()
            
            // For restoration, we don't need to set the tracking state again since it's already set
            // Just return success and let the restoration process handle everything
            result(true)
            return
        }
        
        // CRITICAL: Always reactivate after logout to ensure proper tracking
        CustomLogger.log(message: "Forcing location manager reactivation for tracking")
        LocationManager.reactivateForTracking()
        CustomLogger.log(message: "After reactivation: \(LocationManager.getCurrentStatus())")
        
        // CRITICAL: Set tracking state BEFORE setting delegate
        isTracking = true
        SharedPrefsUtil.saveIsTracking(isTracking)
        
        // CRITICAL: Force UserDefaults sync to ensure immediate persistence
        UserDefaults.standard.synchronize()
        
        // CRITICAL: Set the plugin as the delegate AFTER reactivation and state setting
        SwiftBackgroundLocationTrackerPlugin.setLocationManagerDelegate()
        
        // CRITICAL: Ensure background channel is initialized before starting location services
        // This is crucial for receiving location updates
        if let flutterEngine = SwiftBackgroundLocationTrackerPlugin.getFlutterEngine() {
            CustomLogger.log(message: "FlutterEngine available, initializing background channel")
            SwiftBackgroundLocationTrackerPlugin.initBackgroundMethodChannel(flutterEngine: flutterEngine)
        } else {
            CustomLogger.logCritical(message: "🚨 WARNING: No FlutterEngine available for background channel initialization")
            CustomLogger.logCritical(message: "Location updates will be cached but not sent to Flutter")
        }
        
        // Start location services with restored settings
        locationManager.startUpdatingLocation()
        locationManager.startMonitoringSignificantLocationChanges()
        
        // CRITICAL: Verify that tracking is properly configured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let isProperlyConfigured = LocationManager.isConfiguredForTracking()
            CustomLogger.log(message: "Tracking verification: isProperlyConfigured=\(isProperlyConfigured)")
            
            if !isProperlyConfigured {
                CustomLogger.logCritical(message: "🚨 WARNING: Location manager not properly configured after startTracking!")
                CustomLogger.logCritical(message: "Status: \(LocationManager.getCurrentStatus())")
            }
        }
        
        CustomLogger.log(message: "Location tracking started with settings: accuracy=\(locationManager.desiredAccuracy), distanceFilter=\(locationManager.distanceFilter)")
        CustomLogger.log(message: LocationManager.getCurrentStatus())
        CustomLogger.log(message: "Status bar indicator should be visible: \(LocationManager.shouldShowStatusBarIndicator())")
        
        // Simple verification that location services are running
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            CustomLogger.log(message: "=== VERIFICATION: LOCATION SERVICES STATUS ===")
            CustomLogger.log(message: "Tracking state: \(SharedPrefsUtil.isTracking())")
            CustomLogger.log(message: "Location manager status: \(LocationManager.getCurrentStatus())")
            CustomLogger.log(message: "Status bar indicator should be visible: \(LocationManager.shouldShowStatusBarIndicator())")
        }
        
        CustomLogger.log(message: "=== START TRACKING COMPLETED ===")
        result(true)
    }
    
    private func stopTracking(_ result: @escaping FlutterResult) {
        CustomLogger.logCritical(message: "=== STOP TRACKING STARTED ===")
        CustomLogger.logAlways(message: "Current location manager status: \(LocationManager.getCurrentStatus())")
        
        // CRITICAL: Clear delegate FIRST to prevent any new location callbacks
        locationManager.delegate = nil
        SwiftBackgroundLocationTrackerPlugin.clearLocationManagerDelegate()
        
        CustomLogger.log(message: "Delegates cleared to prevent new location callbacks")
        
        // CRITICAL: Stop all location services and remove from system's active requests
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        
        CustomLogger.log(message: "Location services stopped")
        
        // CRITICAL: Clear tracking state AFTER stopping services and clearing delegate
        isTracking = false
        SharedPrefsUtil.saveIsTracking(isTracking)
        UserDefaults.standard.synchronize()
        
        CustomLogger.log(message: "Tracking state cleared and persisted")
        
        // Use the deactivate method for complete cleanup and status bar indicator removal
        LocationManager.deactivate()
        
        CustomLogger.log(message: "Location manager deactivated")
        CustomLogger.log(message: "Final location manager status: \(LocationManager.getCurrentStatus())")
        CustomLogger.log(message: "Status bar indicator should be visible: \(LocationManager.shouldShowStatusBarIndicator())")
        
        // CRITICAL: Force cleanup after a small delay to ensure all queued updates are processed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            SwiftBackgroundLocationTrackerPlugin.forceCleanup()
            CustomLogger.log(message: "Force cleanup completed after delay")
        }
        
        CustomLogger.log(message: "=== STOP TRACKING COMPLETED ===")
        result(true)
    }
    
    private func isTracking(_ result: @escaping FlutterResult) {
        SharedPrefsUtil.saveIsTracking(isTracking)
        result(isTracking)
    }
    
    private func setDriveActive(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let isActive = args["isActive"] as? Bool else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "isActive parameter is required", details: nil))
            return
        }
        
        CustomLogger.log(message: "Setting drive active state to: \(isActive)")
        isDriveActive = isActive
        
        if isActive {
            // Start monitoring location permission changes
            startPermissionMonitoring()
        } else {
            // Stop monitoring permission changes
            stopPermissionMonitoring()
        }
        
        result(true)
    }
    
    private func startPermissionMonitoring() {
        CustomLogger.log(message: "Starting location permission monitoring")
        
        // Check current permission status
        let currentStatus = CLLocationManager.authorizationStatus()
        CustomLogger.log(message: "Current location permission status: \(currentStatus.rawValue)")
        
        // If already granted, notify Flutter immediately
        if isLocationPermissionGranted(currentStatus) {
            CustomLogger.log(message: "Permission already granted - notifying Flutter immediately")
            handlePermissionGranted()
        }
        
        // Set up location manager delegate to listen for permission changes
        locationManager.delegate = self
        
        // Listen for app lifecycle changes to re-check permissions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    private func stopPermissionMonitoring() {
        CustomLogger.log(message: "Stopping location permission monitoring")
        // Remove app lifecycle observer
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        // Note: We don't clear the delegate here as it might be used for other purposes
        // The permission monitoring will be handled by checking isDriveActive in delegate methods
    }
    
    @objc private func appDidBecomeActive() {
        guard isDriveActive else { return }
        
        CustomLogger.log(message: "App became active, re-checking location permission")
        
        // Re-check permission status when app becomes active
        let currentStatus = CLLocationManager.authorizationStatus()
        CustomLogger.log(message: "Permission status on app active: \(currentStatus.rawValue)")
        
        if isLocationPermissionGranted(currentStatus) {
            handlePermissionGranted()
        }
    }
    
    private func isLocationPermissionGranted(_ status: CLAuthorizationStatus) -> Bool {
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }
    
    private func handlePermissionGranted() {
        CustomLogger.logCritical(message: "🚨 handlePermissionGranted() called")
        CustomLogger.logCritical(message: "🚨 isDriveActive: \(isDriveActive)")
        
        guard isDriveActive else {
            CustomLogger.log(message: "Permission granted but drive is not active, skipping auto-start")
            return
        }
        
        CustomLogger.logCritical(message: "🚨 Location permission granted and drive is active")
        
        // Try to notify Flutter first
        notifyFlutterPermissionGranted()
        
        // Also try to start tracking directly as a fallback
        // This ensures tracking starts even if Flutter communication fails
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            
            CustomLogger.logCritical(message: "🚨 Fallback: Starting tracking directly after permission granted")
            self.startTracking { result in
                if let success = result as? Bool, success {
                    CustomLogger.logCritical(message: "🚨 Fallback tracking started successfully")
                } else {
                    CustomLogger.logCritical(message: "🚨 Fallback tracking failed")
                }
            }
        }
    }
    
    private func notifyFlutterPermissionGranted() {
        CustomLogger.logCritical(message: "🚨 notifyFlutterPermissionGranted() called")
        
        // Send a method call to Flutter to notify about permission granted
        // This allows Flutter to handle the initialization properly
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                CustomLogger.logCritical(message: "🚨 self is nil in notifyFlutterPermissionGranted")
                return 
            }
            
            // We need to get the method channel to send the notification
            // This should be available from the plugin registration
            if let methodChannel = SwiftBackgroundLocationTrackerPlugin.getForegroundMethodChannel() {
                CustomLogger.logCritical(message: "🚨 Method channel found, sending permission granted notification to Flutter")
                methodChannel.invokeMethod("onPermissionGranted", arguments: nil) { result in
                    if let error = result as? FlutterError {
                        CustomLogger.logCritical(message: "🚨 Failed to notify Flutter about permission granted: \(error.message ?? "Unknown error")")
                    } else {
                        CustomLogger.logCritical(message: "🚨 Successfully notified Flutter about permission granted")
                    }
                }
            } else {
                CustomLogger.logCritical(message: "🚨 CRITICAL: No method channel available to notify Flutter about permission granted")
                CustomLogger.logCritical(message: "This means the plugin was not properly initialized")
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension ForegroundChannel: CLLocationManagerDelegate {
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        CustomLogger.log(message: "Location permission status changed to: \(status.rawValue)")
        
        if isLocationPermissionGranted(status) {
            handlePermissionGranted()
        }
    }
}
