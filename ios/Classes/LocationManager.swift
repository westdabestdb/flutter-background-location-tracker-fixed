//
//  LocationManager.swift
//  background_location_tracker
//
//  Created by Dimmy Maenhout on 16/12/2020.
//

import Foundation
import CoreLocation

class LocationManager {
    
    private static var sharedLocationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.activityType = SharedPrefsUtil.activityType()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = SharedPrefsUtil.distanceFilter()
        manager.pausesLocationUpdatesAutomatically = false
        if #available(iOS 11, *) {
            manager.showsBackgroundLocationIndicator = true
        }
        if #available(iOS 9.0, *) {
            manager.allowsBackgroundLocationUpdates = true
        }
        return manager
    }()
    
    class func shared() -> CLLocationManager {
        return sharedLocationManager
    }
    
    // Method to completely reset the location manager state
    class func reset() {
        let manager = sharedLocationManager
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.delegate = nil
        manager.allowsBackgroundLocationUpdates = false
        
        // CRITICAL: Completely disable location services to remove status bar indicator
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = true
        
        // Force iOS to stop all location requests
        if #available(iOS 14.0, *) {
            manager.desiredAccuracy = kCLLocationAccuracyReduced
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        }
    }
    
    // Method to completely deactivate location manager
    class func deactivate() {
        CustomLogger.log(message: "=== LOCATION MANAGER DEACTIVATION STARTED ===")
        let manager = sharedLocationManager
        
        CustomLogger.log(message: "Before deactivation: \(getCurrentStatus())")
        
        // Stop location services multiple times to ensure iOS processes it
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        // Clear delegate
        manager.delegate = nil
        manager.allowsBackgroundLocationUpdates = false
        
        // Set to lowest accuracy to minimize GPS usage and remove status bar indicator
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = true
        
        // Force a complete stop multiple times to ensure iOS stops all requests
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        // Additional safety: ensure no background processing
        if #available(iOS 14.0, *) {
            manager.desiredAccuracy = kCLLocationAccuracyReduced
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        }
        
        // CRITICAL: Force one more stop after setting low accuracy
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        CustomLogger.log(message: "After deactivation: \(getCurrentStatus())")
        CustomLogger.log(message: "=== LOCATION MANAGER DEACTIVATION COMPLETED ===")
    }
    
    // Method to completely destroy and recreate location manager (nuclear option)
    class func destroyAndRecreate() {
        // First deactivate the current instance
        deactivate()
        
        // Create a completely new instance
        sharedLocationManager = CLLocationManager()
        let manager = sharedLocationManager
        manager.activityType = .other
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false
    }
    
    // Method to reactivate location manager for active tracking
    class func reactivateForTracking() {
        CustomLogger.logCritical(message: "🚨 REACTIVATING LOCATION MANAGER FOR TRACKING")
        let manager = sharedLocationManager
        
        CustomLogger.log(message: "Before reactivation: \(getCurrentStatus())")
        
        // CRITICAL: First ensure we're completely stopped to avoid conflicts
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        // Restore the original tracking settings from SharedPrefs
        manager.activityType = SharedPrefsUtil.activityType()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = SharedPrefsUtil.distanceFilter()
        manager.pausesLocationUpdatesAutomatically = false
        
        // Enable background location updates for tracking
        if #available(iOS 9.0, *) {
            manager.allowsBackgroundLocationUpdates = true
        }
        
        // Show background location indicator
        if #available(iOS 11, *) {
            manager.showsBackgroundLocationIndicator = true
        }
        
        // CRITICAL: Force a small delay to ensure iOS processes the settings change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            CustomLogger.log(message: "Verifying reactivation settings...")
            CustomLogger.log(message: "Final status: \(getCurrentStatus())")
            CustomLogger.log(message: "needsReactivation: \(needsReactivation())")
        }
        
        CustomLogger.log(message: "After reactivation: \(getCurrentStatus())")
        CustomLogger.log(message: "Location manager reactivated with tracking settings: accuracy=\(manager.desiredAccuracy), distanceFilter=\(manager.distanceFilter), activityType=\(manager.activityType.rawValue)")
        CustomLogger.log(message: "Status bar indicator should be visible: \(shouldShowStatusBarIndicator())")
        CustomLogger.logCritical(message: "🚨 REACTIVATION COMPLETED")
    }
    
    // Method to check if location manager needs reactivation
    class func needsReactivation() -> Bool {
        let manager = sharedLocationManager
        var hasLowAccuracy = manager.desiredAccuracy == kCLLocationAccuracyThreeKilometers
        if #available(iOS 14.0, *) {
            hasLowAccuracy = hasLowAccuracy || manager.desiredAccuracy == kCLLocationAccuracyReduced
        }
        return hasLowAccuracy ||
               manager.distanceFilter == CLLocationDistanceMax ||
               !manager.allowsBackgroundLocationUpdates
    }
    
    // Method to get current location manager status for debugging
    class func getCurrentStatus() -> String {
        let manager = sharedLocationManager
        return "LocationManager Status: accuracy=\(manager.desiredAccuracy), distanceFilter=\(manager.distanceFilter), activityType=\(manager.activityType.rawValue), allowsBackground=\(manager.allowsBackgroundLocationUpdates), delegate=\(manager.delegate != nil ? "set" : "nil")"
    }
    
    // Method to check if status bar indicator should be visible
    class func shouldShowStatusBarIndicator() -> Bool {
        let manager = sharedLocationManager
        // Status bar indicator shows when:
        // 1. Location services are active (not stopped)
        // 2. Accuracy is not at lowest level
        // 3. Background updates are enabled
        var hasLowAccuracy = manager.desiredAccuracy == kCLLocationAccuracyThreeKilometers
        if #available(iOS 14.0, *) {
            hasLowAccuracy = hasLowAccuracy || manager.desiredAccuracy == kCLLocationAccuracyReduced
        }
        return !hasLowAccuracy &&
               manager.allowsBackgroundLocationUpdates &&
               manager.delegate != nil
    }
    
    // Method to check if location manager is actually stopped
    class func isLocationManagerStopped() -> Bool {
        let manager = sharedLocationManager
        // Check if location manager is in a stopped state
        var hasLowAccuracy = manager.desiredAccuracy == kCLLocationAccuracyThreeKilometers
        if #available(iOS 14.0, *) {
            hasLowAccuracy = hasLowAccuracy || manager.desiredAccuracy == kCLLocationAccuracyReduced
        }
        return hasLowAccuracy ||
               manager.distanceFilter == CLLocationDistanceMax ||
               !manager.allowsBackgroundLocationUpdates
    }
    
    // Method to check if location manager is properly configured for tracking
    class func isConfiguredForTracking() -> Bool {
        let manager = sharedLocationManager
        return manager.desiredAccuracy == kCLLocationAccuracyBest &&
               manager.distanceFilter != CLLocationDistanceMax &&
               manager.allowsBackgroundLocationUpdates &&
               manager.delegate != nil &&
               !manager.pausesLocationUpdatesAutomatically
    }
    
    // Method to force complete stop of location manager
    class func forceStopLocationManager() {
        CustomLogger.logCritical(message: "🚨 FORCE STOPPING LOCATION MANAGER")
        let manager = sharedLocationManager
        
        // Stop all services multiple times
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        // Clear delegate
        manager.delegate = nil
        
        // Set to lowest possible settings
        manager.allowsBackgroundLocationUpdates = false
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = true
        
        // Force one more stop
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        CustomLogger.logCritical(message: "🚨 FORCE STOP COMPLETED: \(getCurrentStatus())")
    }
    
    // Method to check if location services are actually running
    class func areLocationServicesRunning() -> Bool {
        let manager = sharedLocationManager
        // Check if location services are in an active state
        return manager.desiredAccuracy == kCLLocationAccuracyBest ||
               manager.desiredAccuracy == kCLLocationAccuracyNearestTenMeters ||
               manager.desiredAccuracy == kCLLocationAccuracyHundredMeters ||
               manager.desiredAccuracy == kCLLocationAccuracyKilometer ||
               manager.desiredAccuracy == kCLLocationAccuracyThreeKilometers
    }
    
    // Method to completely restore location manager state for tracking after app restart
    class func restoreForTracking() {
        CustomLogger.logCritical(message: "🚨 RESTORING LOCATION MANAGER FOR TRACKING AFTER APP RESTART")
        let manager = sharedLocationManager
        
        CustomLogger.log(message: "Before restoration: \(getCurrentStatus())")
        
        // CRITICAL: First ensure we're completely stopped to avoid conflicts
        manager.stopUpdatingLocation()
        manager.stopMonitoringSignificantLocationChanges()
        
        // Clear any existing delegate
        manager.delegate = nil
        
        // Restore the original tracking settings from SharedPrefs
        manager.activityType = SharedPrefsUtil.activityType()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = SharedPrefsUtil.distanceFilter()
        manager.pausesLocationUpdatesAutomatically = false
        
        // Enable background location updates for tracking
        if #available(iOS 9.0, *) {
            manager.allowsBackgroundLocationUpdates = true
        }
        
        // Show background location indicator
        if #available(iOS 11, *) {
            manager.showsBackgroundLocationIndicator = true
        }
        
        // CRITICAL: Force a small delay to ensure iOS processes the settings change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            CustomLogger.log(message: "Verifying restoration settings...")
            CustomLogger.log(message: "Final status: \(getCurrentStatus())")
            CustomLogger.log(message: "isConfiguredForTracking: \(isConfiguredForTracking())")
            CustomLogger.log(message: "areLocationServicesRunning: \(areLocationServicesRunning())")
        }
        
        CustomLogger.log(message: "After restoration: \(getCurrentStatus())")
        CustomLogger.log(message: "Location manager restored with tracking settings: accuracy=\(manager.desiredAccuracy), distanceFilter=\(manager.distanceFilter), activityType=\(manager.activityType.rawValue)")
        CustomLogger.log(message: "Status bar indicator should be visible: \(shouldShowStatusBarIndicator())")
        CustomLogger.logCritical(message: "🚨 RESTORATION COMPLETED")
    }
    
    // Method to check if location manager needs restoration after app restart
    class func needsRestoration() -> Bool {
        let manager = sharedLocationManager
        let needsReactivation = needsReactivation()
        let isConfigured = isConfiguredForTracking()
        let isRunning = areLocationServicesRunning()
        
        // Need restoration if any of these conditions are true:
        // 1. Needs reactivation (basic settings are wrong)
        // 2. Not properly configured for tracking
        // 3. Location services are not running
        // 4. No delegate is set
        return needsReactivation || !isConfigured || !isRunning || manager.delegate == nil
    }
    
    // Method to perform complete health check of location manager
    class func performHealthCheck() -> (isHealthy: Bool, issues: [String]) {
        var issues: [String] = []
        let manager = sharedLocationManager
        
        // Check authorization status
        let authStatus = CLLocationManager.authorizationStatus()
        if authStatus != .authorizedAlways && authStatus != .authorizedWhenInUse {
            issues.append("Location authorization not granted: \(authStatus.rawValue)")
        }
        
        // Check configuration
        if !isConfiguredForTracking() {
            issues.append("Location manager not properly configured for tracking")
        }
        
        // Check if services are running
        if !areLocationServicesRunning() {
            issues.append("Location services are not running")
        }
        
        // Check delegate
        if manager.delegate == nil {
            issues.append("No delegate set on location manager")
        } else {
            // Verify delegate is the correct type (SwiftBackgroundLocationTrackerPlugin)
            let delegateType = String(describing: type(of: manager.delegate!))
            if !delegateType.contains("SwiftBackgroundLocationTrackerPlugin") {
                issues.append("Delegate is wrong type: \(delegateType) - should be SwiftBackgroundLocationTrackerPlugin")
            }
        }
        
        // Check if needs reactivation
        if needsReactivation() {
            issues.append("Location manager needs reactivation")
        }
        
        let isHealthy = issues.isEmpty
        return (isHealthy: isHealthy, issues: issues)
    }

}
