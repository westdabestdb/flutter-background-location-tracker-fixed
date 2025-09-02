import Flutter
import UIKit
import CoreLocation

public class SwiftBackgroundLocationTrackerPlugin: FlutterPluginAppLifeCycleDelegate {
    
    static let identifier = "com.icapps.background_location_tracker"
    
    private static let flutterThreadLabelPrefix = "\(identifier).BackgroundLocationTracker"
    
    private static var foregroundChannel: ForegroundChannel? = nil
    private static var backgroundMethodChannel: FlutterMethodChannel? = nil
    
    private static var flutterEngine: FlutterEngine? = nil
    private static var hasRegisteredPlugins = false
    private static var initializedBackgroundCallbacks = false
    private static var initializedBackgroundCallbacksStarted = false
    private static var locationData: [String: Any]? = nil
    
    // This will store the plugin that registered engines
    private static var pluginRegistrants: [(FlutterEngine) -> Void] = []
    
    // Store the plugin instance for delegate management
    private static var pluginInstance: SwiftBackgroundLocationTrackerPlugin?
    
    private let locationManager = LocationManager.shared()
    
    // Methods to manage the delegate
    public static func setLocationManagerDelegate() {
        if let instance = pluginInstance {
            instance.locationManager.delegate = instance
        }
    }
    
    public static func clearLocationManagerDelegate() {
        if let instance = pluginInstance {
            instance.locationManager.delegate = nil
        }
    }
    
    // Force cleanup method to ensure complete stopping of location services
    public static func forceCleanup() {
        CustomLogger.logCritical(message: "🚨 FORCE CLEANUP STARTED - COMPLETE LOCATION SERVICES SHUTDOWN")
        
        // CRITICAL: Reset the tracking state in SharedPrefs to prevent auto-restart
        SharedPrefsUtil.saveIsTracking(false)
        
        // CRITICAL: Clear location data cache
        locationData = nil
        
        // CRITICAL: Reset initialization state to prevent background engine from restarting
        initializedBackgroundCallbacks = false
        initializedBackgroundCallbacksStarted = false
        
        // Force cleanup of any background tasks
        if let instance = pluginInstance {
            instance.locationManager.stopUpdatingLocation()
            instance.locationManager.stopMonitoringSignificantLocationChanges()
            instance.locationManager.delegate = nil
        }
        
        // CRITICAL: Completely deactivate location manager to remove status bar indicator
        LocationManager.deactivate()
        
        // CRITICAL: Force stop location manager to ensure no more updates are received
        LocationManager.forceStopLocationManager()
        
        // CRITICAL: Destroy the background Flutter engine to prevent battery drain
        // This ensures no background processes can restart location services
        if let engine = flutterEngine {
            CustomLogger.logCritical(message: "🚨 DESTROYING BACKGROUND FLUTTER ENGINE TO PREVENT BATTERY DRAIN")
            engine.destroyContext()
            flutterEngine = nil
        }
        
        // CRITICAL: Clear background method channel to prevent any communication
        backgroundMethodChannel = nil
        
        CustomLogger.logCritical(message: "🚨 FORCE CLEANUP COMPLETED - ALL LOCATION SERVICES AND BACKGROUND PROCESSES STOPPED")
    }
    

    
    // Method for complete cleanup only when app is terminating
    public static func forceCleanupOnTermination() {
        // This is the nuclear option - only use when app is actually terminating
        // forceCleanup() now handles engine destruction, so just call it
        forceCleanup()
    }
    

    
    // Method to get the plugin instance
    public static func getPluginInstance() -> SwiftBackgroundLocationTrackerPlugin? {
        return pluginInstance
    }
    
    // Helper method to safely check if tracking should be restarted
    private static func shouldRestartTracking() -> Bool {
        // Only restart if:
        // 1. Tracking was previously enabled
        // 2. Restart after kill is enabled
        // 3. We're not in the middle of cleanup
        // 4. The plugin instance exists
        return SharedPrefsUtil.isTracking() && 
               SharedPrefsUtil.restartAfterKill() && 
               !initializedBackgroundCallbacksStarted &&
               pluginInstance != nil
    }
    
    // Method to reset initialization state when needed (e.g., after app relaunch)
    public static func resetInitializationState() {
        CustomLogger.log(message: "=== RESETTING INITIALIZATION STATE ===")
        initializedBackgroundCallbacks = false
        initializedBackgroundCallbacksStarted = false
        locationData = nil
        
        // CRITICAL: Also clear background method channel to ensure clean state
        backgroundMethodChannel = nil
        
        CustomLogger.log(message: "Initialization state reset completed")
    }

    // Method to completely restore location tracking state after app restart
    public static func restoreLocationTrackingState() {
        CustomLogger.log(message: "=== RESTORING LOCATION TRACKING STATE AFTER APP RESTART ===")
        
        // Check if we should even attempt restoration
        guard SharedPrefsUtil.isTracking() else {
            CustomLogger.log(message: "No tracking state to restore")
            return
        }
        
        // Perform health check to identify issues
        let healthCheck = LocationManager.performHealthCheck()
        CustomLogger.log(message: "Health check result: isHealthy=\(healthCheck.isHealthy)")
        if !healthCheck.isHealthy {
            CustomLogger.log(message: "Issues found: \(healthCheck.issues)")
        }
        
        // Check if restoration is needed
        if LocationManager.needsRestoration() {
            CustomLogger.log(message: "Location manager needs restoration, proceeding...")
            
            // Verify location permissions
            let authStatus = CLLocationManager.authorizationStatus()
            CustomLogger.log(message: "Location authorization status: \(authStatus.rawValue)")
            
            if authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse {
                CustomLogger.log(message: "Permissions verified, performing restoration")
                
                // Perform complete restoration
                LocationManager.restoreForTracking()
                
                // Set delegate
                if let instance = pluginInstance {
                    instance.locationManager.delegate = instance
                    CustomLogger.log(message: "Delegate set after restoration")
                }
                
                // Verify restoration was successful
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    let postRestorationHealth = LocationManager.performHealthCheck()
                    CustomLogger.log(message: "Post-restoration health check: isHealthy=\(postRestorationHealth.isHealthy)")
                    
                    if postRestorationHealth.isHealthy {
                        CustomLogger.log(message: "✅ Location tracking state restoration successful!")
                        
                        // Start location services
                        if let instance = pluginInstance {
                            instance.locationManager.startUpdatingLocation()
                            instance.locationManager.startMonitoringSignificantLocationChanges()
                            CustomLogger.log(message: "Location services started after restoration")
                        }
                    } else {
                        CustomLogger.logCritical(message: "🚨 CRITICAL: Location tracking state restoration failed!")
                        CustomLogger.logCritical(message: "Issues: \(postRestorationHealth.issues)")
                        
                        // Force cleanup if restoration failed
                        SharedPrefsUtil.saveIsTracking(false)
                        forceCleanup()
                    }
                }
            } else {
                CustomLogger.logCritical(message: "🚨 WARNING: Cannot restore tracking without location permissions!")
                CustomLogger.logCritical(message: "Authorization status: \(authStatus.rawValue)")
                
                // Clear tracking state since we can't restore it
                SharedPrefsUtil.saveIsTracking(false)
                forceCleanup()
            }
        } else {
            CustomLogger.log(message: "Location manager is healthy, no restoration needed")
        }
        
        CustomLogger.log(message: "=== LOCATION TRACKING STATE RESTORATION COMPLETED ===")
    }
}

extension SwiftBackgroundLocationTrackerPlugin: FlutterPlugin {
    
    @objc
    public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
        // Store the callback in our new pluginRegistrants array
        pluginRegistrants.append(callback)
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        foregroundChannel = ForegroundChannel()
        let methodChannel = ForegroundChannel.createMethodChannel(binaryMessenger: registrar.messenger())
        let instance = SwiftBackgroundLocationTrackerPlugin()
        
        // Store the plugin instance
        pluginInstance = instance
        
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        registrar.addApplicationDelegate(instance)

        // Don't automatically start location services
        instance.locationManager.requestAlwaysAuthorization()
        
        // CRITICAL: Reset initialization state on app relaunch to ensure proper reinitialization
        resetInitializationState()
        
        // Only start if we were tracking before AND restartAfterKill is enabled
        if shouldRestartTracking() {
            instance.locationManager.delegate = instance
            instance.locationManager.startMonitoringSignificantLocationChanges()
            instance.locationManager.startUpdatingLocation()
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Don't interfere with location management - let ForegroundChannel handle it
        SwiftBackgroundLocationTrackerPlugin.foregroundChannel?.handle(call, result: result)
    }
    
    public static func getFlutterEngine()-> FlutterEngine? {
        if flutterEngine == nil {
            let flutterEngine = FlutterEngine(name: flutterThreadLabelPrefix, project: nil, allowHeadlessExecution: true)
            
            guard let callbackHandle = SharedPrefsUtil.getCallbackHandle(),
                  let flutterCallbackInformation = FlutterCallbackCache.lookupCallbackInformation(callbackHandle) else {
                CustomLogger.log(message: "No flutter callback cache ...")
                return nil
            }
            let success = flutterEngine.run(withEntrypoint: flutterCallbackInformation.callbackName, libraryURI: flutterCallbackInformation.callbackLibraryPath)
            
            CustomLogger.log(message: "FlutterEngine.run returned `\(success)`")
            if success {
                // Run all the registered plugin registrants
                for registrant in pluginRegistrants {
                    registrant(flutterEngine)
                }
                self.flutterEngine = flutterEngine
                
                // CRITICAL: Initialize the background method channel immediately after engine creation
                // This ensures the background callback is set up before any location updates
                initBackgroundMethodChannel(flutterEngine: flutterEngine)
                CustomLogger.log(message: "Background method channel initialized immediately after engine creation")
            } else {
                CustomLogger.log(message: "FlutterEngine.run returned `false` we will cleanup the flutterEngine")
                flutterEngine.destroyContext()
            }
        }
        return flutterEngine
    }
    
    public static func initBackgroundMethodChannel(flutterEngine: FlutterEngine) {
        if backgroundMethodChannel == nil {
            let backgroundMethodChannel = FlutterMethodChannel(name: SwiftBackgroundLocationTrackerPlugin.BACKGROUND_CHANNEL_NAME, binaryMessenger: flutterEngine.binaryMessenger)
            backgroundMethodChannel.setMethodCallHandler { (call, result) in
                switch call.method {
                case BackgroundMethods.initialized.rawValue:
                    initializedBackgroundCallbacks = true
                    if let data = SwiftBackgroundLocationTrackerPlugin.locationData {
                        CustomLogger.log(message: "Initialized with cached value, sending location update")
                        sendLocationupdate(locationData: data)
                    } else {
                        CustomLogger.log(message: "Initialized without cached value")
                    }
                    result(true)
                default:
                    CustomLogger.log(message: "Not implemented method -> \(call.method)")
                    result(FlutterMethodNotImplemented)
                }
            }
            self.backgroundMethodChannel = backgroundMethodChannel
        }
    }
    
    public static func sendLocationupdate(locationData: [String: Any]){
        guard let backgroundMethodChannel = SwiftBackgroundLocationTrackerPlugin.backgroundMethodChannel else {
            CustomLogger.log(message: "No background channel available ...")
            return
        }
        backgroundMethodChannel.invokeMethod(BackgroundMethods.onLocationUpdate.rawValue, arguments: locationData, result: { flutterResult in
            CustomLogger.log(message: "Received result: \(flutterResult.debugDescription)")
        })
    }
}

fileprivate enum BackgroundMethods: String {
    case initialized = "initialized"
    case onLocationUpdate = "onLocationUpdate"
}

extension SwiftBackgroundLocationTrackerPlugin: CLLocationManagerDelegate {
    private static let BACKGROUND_CHANNEL_NAME = "com.icapps.background_location_tracker/background_channel"
    
    // App lifecycle handling
    public func applicationWillTerminate(_ application: UIApplication) {
        // If tracking is active, keep it running in background
        if SharedPrefsUtil.isTracking() {
            CustomLogger.log(message: "App terminating, but keeping tracking active for background processing")
        } else {
            // If tracking is stopped, do complete cleanup since app is terminating
            CustomLogger.log(message: "App terminating and tracking is stopped, doing complete cleanup")
            SwiftBackgroundLocationTrackerPlugin.forceCleanupOnTermination()
        }
    }
    
    public func applicationDidEnterBackground(_ application: UIApplication) {
        // If tracking is stopped, ensure complete cleanup
        if !SharedPrefsUtil.isTracking() {
            CustomLogger.log(message: "App entering background and tracking is stopped, cleaning up")
            SwiftBackgroundLocationTrackerPlugin.forceCleanup()
        } else {
            CustomLogger.log(message: "App entering background but tracking is active, keeping it running")
        }
    }
    
    public func applicationDidBecomeActive(_ application: UIApplication) {
        CustomLogger.log(message: "=== APP DID BECOME ACTIVE ===")
        
        // CRITICAL: Use the new comprehensive restoration method for app restart scenarios
        if SharedPrefsUtil.isTracking() {
            CustomLogger.log(message: "App became active with tracking enabled, checking if restoration is needed")
            
            // Use the comprehensive restoration method
            SwiftBackgroundLocationTrackerPlugin.restoreLocationTrackingState()
        }
        
        CustomLogger.log(message: "=== APP DID BECOME ACTIVE COMPLETED ===")
    }
    
    public func applicationWillEnterForeground(_ application: UIApplication) {
        CustomLogger.log(message: "=== APP WILL ENTER FOREGROUND ===")
        
        // Additional check for app foreground transition
        if SharedPrefsUtil.isTracking() {
            CustomLogger.log(message: "App entering foreground with active tracking")
            
            // Verify tracking is properly configured
            let isConfigured = LocationManager.isConfiguredForTracking()
            CustomLogger.log(message: "Tracking verification: isConfigured=\(isConfigured)")
            
            if !isConfigured {
                CustomLogger.log(message: "Tracking not properly configured, attempting to restore")
                LocationManager.reactivateForTracking()
                
                if let instance = SwiftBackgroundLocationTrackerPlugin.pluginInstance {
                    instance.locationManager.delegate = instance
                    instance.locationManager.startUpdatingLocation()
                    instance.locationManager.startMonitoringSignificantLocationChanges()
                    CustomLogger.log(message: "Tracking restored after entering foreground")
                }
            }
        }
        
        CustomLogger.log(message: "=== APP WILL ENTER FOREGROUND COMPLETED ===")
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // CRITICAL: If tracking is disabled, we should NOT be receiving location updates at all
        guard SharedPrefsUtil.isTracking() else {
            CustomLogger.logCritical(message: "🚨 CRITICAL: Location updates still being received after tracking disabled!")
            CustomLogger.logCritical(message: "This means the location manager is not fully stopped")
            CustomLogger.logCritical(message: "Current tracking state: \(SharedPrefsUtil.isTracking())")
            CustomLogger.logCritical(message: "Location manager status: \(LocationManager.getCurrentStatus())")
            
            // Force stop the location manager immediately
            manager.stopUpdatingLocation()
            manager.stopMonitoringSignificantLocationChanges()
            manager.delegate = nil
            
            // Also force cleanup through our plugin
            SwiftBackgroundLocationTrackerPlugin.forceCleanup()
            
            CustomLogger.logCritical(message: "Forced location manager stop due to unauthorized updates")
            return
        }
        
        // Additional safety check: verify the location manager still has a delegate
        guard manager.delegate != nil else {
            CustomLogger.log(message: "Location manager delegate is nil, ignoring update")
            return
        }
        
        // Additional safety check: verify we're still the delegate
        guard manager.delegate === self else {
            CustomLogger.log(message: "We are no longer the delegate, ignoring update")
            return
        }
        
        // Additional safety check: verify location manager is properly configured
        guard LocationManager.isConfiguredForTracking() else {
            CustomLogger.logCritical(message: "🚨 WARNING: Location manager not properly configured but receiving updates!")
            CustomLogger.logCritical(message: "Status: \(LocationManager.getCurrentStatus())")
            return
        }
        
        guard let location = locations.last else {
            CustomLogger.log(message: "No location ...")
            return
        }
        
        CustomLogger.log(message: "NEW LOCATION: \(location.coordinate.latitude): \(location.coordinate.longitude)")
        CustomLogger.log(message: "Tracking state: \(SharedPrefsUtil.isTracking()), Manager configured: \(LocationManager.isConfiguredForTracking())")
        
        var locationData: [String: Any] = [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "alt": location.altitude,
            "vertical_accuracy": location.verticalAccuracy,
            "horizontal_accuracy": location.horizontalAccuracy,
            "course": location.course,
            "course_accuracy": -1,
            "speed": location.speed,
            "speed_accuracy": location.speedAccuracy,
            "logging_enabled": SharedPrefsUtil.isLoggingEnabled(),
        ]
        
        if #available(iOS 13.4, *) {
            locationData["course_accuracy"] = location.courseAccuracy
        }
        
        if SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacks {
            CustomLogger.log(message: "INITIALIZED, ready to send location updates")
            SwiftBackgroundLocationTrackerPlugin.sendLocationupdate(locationData: locationData)
        } else {
            CustomLogger.log(message: "NOT YET INITIALIZED. Cache the location data")
            SwiftBackgroundLocationTrackerPlugin.locationData = locationData
            
            if !SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacksStarted {
                SwiftBackgroundLocationTrackerPlugin.initializedBackgroundCallbacksStarted = true
            
                // Create the Flutter engine - the background method channel will be initialized automatically
                guard let flutterEngine = SwiftBackgroundLocationTrackerPlugin.getFlutterEngine() else {
                    CustomLogger.log(message: "No Flutter engine available ...")
                    return
                }
                CustomLogger.log(message: "Flutter engine created, background channel should be ready")
            }
        }
    }
}
