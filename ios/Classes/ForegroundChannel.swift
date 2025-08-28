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
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - private methods
    
    private func initialize(call: FlutterMethodCall, result: @escaping FlutterResult ) {
        let callBackHandleKey = "callback_handle"
        let loggingEnabledKey = "logging_enabled"
        let activityTypeKey = "ios_activity_type"
        let distanceFilterKey = "ios_distance_filter"
        let restartAfterKillKey = "ios_restart_after_kill"
        let map = call.arguments as? [String: Any]
        guard let callbackDispatcherHandle = map?[callBackHandleKey] else {
            result(false)
            return
        }
        
        
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
        
        SharedPrefsUtil.saveCallBackDispatcherHandleKey(callBackHandle: callbackDispatcherHandle as? Int64)
        SharedPrefsUtil.saveIsTracking(isTracking)
        result(true)
    }
    
    private func startTracking(_ result: @escaping FlutterResult) {
        CustomLogger.logCritical(message: "=== START TRACKING STARTED ===")
        CustomLogger.logAlways(message: "Current location manager status: \(LocationManager.getCurrentStatus())")
        CustomLogger.logAlways(message: "Status bar indicator should be visible: \(LocationManager.shouldShowStatusBarIndicator())")
        CustomLogger.logAlways(message: "needsReactivation check: \(LocationManager.needsReactivation())")
        
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
        return result(isTracking)
    }
}
