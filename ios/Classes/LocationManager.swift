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
        return manager.desiredAccuracy == kCLLocationAccuracyThreeKilometers ||
               manager.desiredAccuracy == kCLLocationAccuracyReduced ||
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
        return manager.desiredAccuracy != kCLLocationAccuracyThreeKilometers &&
               manager.desiredAccuracy != kCLLocationAccuracyReduced &&
               manager.allowsBackgroundLocationUpdates &&
               manager.delegate != nil
    }
    
    // Method to check if location manager is actually stopped
    class func isLocationManagerStopped() -> Bool {
        let manager = sharedLocationManager
        // Check if location manager is in a stopped state
        return manager.desiredAccuracy == kCLLocationAccuracyThreeKilometers ||
               manager.desiredAccuracy == kCLLocationAccuracyReduced ||
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
    

}
