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
}

public class ForegroundChannel : NSObject {
    
    private var isTracking = false
    private var isTrackingActive = false
    private static let FOREGROUND_CHANNEL_NAME = "com.icapps.background_location_tracker/foreground_channel"
    
    private let locationManager = LocationManager.shared()
    
    private let userDefaults = UserDefaults.standard
    
    // Callback for handling authorization changes
    internal var onAuthorizationChanged: ((CLAuthorizationStatus) -> Void)?
    
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
        
        // CRITICAL: Restore tracking active state from previous session
        isTrackingActive = SharedPrefsUtil.isTrackingActive()
        if isTrackingActive {
            CustomLogger.log(message: "Restoring tracking active state from previous session")
            startPermissionMonitoring()
            
            // If we were tracking before app termination, check if we should restart tracking
            if SharedPrefsUtil.isTracking() {
                CustomLogger.log(message: "App was tracking before termination, checking if we should restart")
                let currentStatus = CLLocationManager.authorizationStatus()
                if isLocationPermissionGranted(currentStatus) {
                    CustomLogger.log(message: "Permission is granted, restarting tracking")
                    handlePermissionGranted()
                } else {
                    CustomLogger.log(message: "Permission not granted, will wait for permission change")
                }
            }
        }
        
        result(true)
    }
    
    private func startTracking(_ result: @escaping FlutterResult) {
        CustomLogger.logCritical(message: "=== START TRACKING CALLED FROM FLUTTER ===")
        
        // SAFETY: Check authorization status before attempting to start
        let authStatus = CLLocationManager.authorizationStatus()
        CustomLogger.log(message: "Current authorization status: \(authStatus.rawValue)")
        
        // CRITICAL: Check if this is a restoration attempt after app restart
        let isRestorationAttempt = SharedPrefsUtil.isTracking() && LocationManager.needsRestoration()
        if isRestorationAttempt {
            CustomLogger.log(message: "Detected restoration attempt - using restoration flow")
            // Use the comprehensive restoration method for app restart scenarios
            SwiftBackgroundLocationTrackerPlugin.restoreLocationTrackingState()
            result(true)
            return
        }
        
        // Start permission monitoring to handle authorization changes
        startPermissionMonitoring()
        
        startLocationTracking(isRestoration: false)
        
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
        
        // CRITICAL: Clear tracking active state and stop permission monitoring
        isTrackingActive = false
        SharedPrefsUtil.saveTrackingActive(isTrackingActive)
        stopPermissionMonitoring()
        
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
        
        // CRITICAL: Set up callback to receive authorization changes from the plugin
        // CLLocationManagerDelegate to avoid race conditions
        onAuthorizationChanged = { [weak self] status in
            guard let self = self, self.isTrackingActive else { return }
            CustomLogger.log(message: "ForegroundChannel received authorization change: \(status.rawValue)")
            if self.isLocationPermissionGranted(status) {
                self.handlePermissionGranted()
            }
        }
        
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
        onAuthorizationChanged = nil
    }
    
    @objc private func appDidBecomeActive() {
        guard isTrackingActive else { return }
        
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
        CustomLogger.logCritical(message: "🚨 isTrackingActive: \(isTrackingActive)")
        
        guard isTrackingActive else {
            CustomLogger.log(message: "Permission granted but tracking is not active, skipping auto-start")
            return
        }
        
        // Check if we're already tracking to avoid duplicate calls
        guard !isTracking else {
            CustomLogger.log(message: "Already tracking, skipping duplicate start")
            return
        }
        
        CustomLogger.logCritical(message: "🚨 Location permission granted and tracking is active - starting tracking")
        
        // Start tracking using consolidated method
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.startLocationTracking(isRestoration: false)
        }
    }
    
    // Public method to get ForegroundChannel instance from plugin for authorization forwarding
    internal func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        onAuthorizationChanged?(status)
    }
    
    
    // Single method to start location tracking - consolidates all startup paths
    private func startLocationTracking(isRestoration: Bool = false) {
        CustomLogger.log(message: "=== STARTING LOCATION TRACKING (restoration: \(isRestoration)) ===")
        
        // SAFETY: Verify location services are enabled at system level
        guard CLLocationManager.locationServicesEnabled() else {
            CustomLogger.logCritical(message: "🚨 SAFETY ERROR: Location services are disabled at system level!")
            CustomLogger.logCritical(message: "Cannot start tracking - user must enable in Settings")
            return
        }
        
        // CRITICAL: Always reactivate to ensure proper tracking configuration
        LocationManager.reactivateForTracking()
        CustomLogger.log(message: "After reactivation: \(LocationManager.getCurrentStatus())")
        
        // Set tracking state
        isTracking = true
        SharedPrefsUtil.saveIsTracking(isTracking)
        
        // Set tracking active state to enable permission monitoring
        isTrackingActive = true
        SharedPrefsUtil.saveTrackingActive(isTrackingActive)
        
        // Force UserDefaults sync for immediate persistence
        UserDefaults.standard.synchronize()
        
        // SAFETY: Verify plugin instance exists before setting delegate
        guard SwiftBackgroundLocationTrackerPlugin.getPluginInstance() != nil else {
            CustomLogger.logCritical(message: "🚨 SAFETY ERROR: Plugin instance is nil - cannot set delegate!")
            CustomLogger.logCritical(message: "This indicates a serious initialization problem")
            return
        }
        
        // Set the plugin as the delegate
        SwiftBackgroundLocationTrackerPlugin.setLocationManagerDelegate()
        
        // Initialize background channel if available
        if let flutterEngine = SwiftBackgroundLocationTrackerPlugin.getFlutterEngine() {
            CustomLogger.log(message: "✅ FlutterEngine available, initializing background channel")
            SwiftBackgroundLocationTrackerPlugin.initBackgroundMethodChannel(flutterEngine: flutterEngine)
        } else {
            CustomLogger.logCritical(message: "⚠️ WARNING: No FlutterEngine available for background channel initialization")
            CustomLogger.logCritical(message: "Location updates will be cached and sent when engine initializes")
        }
        
        // Start location services
        locationManager.startMonitoringSignificantLocationChanges()
        CustomLogger.log(message: "✅ Significant location change monitoring started")
        
        // Verify tracking is properly configured
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let isProperlyConfigured = LocationManager.isConfiguredForTracking()
            let healthCheck = LocationManager.performHealthCheck()
            
            CustomLogger.log(message: "Tracking verification: isProperlyConfigured=\(isProperlyConfigured)")
            CustomLogger.log(message: "Health check: isHealthy=\(healthCheck.isHealthy)")
            
            if !isProperlyConfigured {
                CustomLogger.logCritical(message: "🚨 WARNING: Location manager not properly configured after starting!")
                CustomLogger.logCritical(message: "Status: \(LocationManager.getCurrentStatus())")
                CustomLogger.logCritical(message: "Issues: \(healthCheck.issues)")
            } else {
                CustomLogger.log(message: "✅ Location tracking verified successfully")
            }
        }
        
        CustomLogger.log(message: "Location tracking started: \(LocationManager.getCurrentStatus())")
        CustomLogger.log(message: "=== LOCATION TRACKING START COMPLETED ===")
    }
    
}
