//
//  CustomLogger.swift
//  background_location_tracker
//
//  Created by Dimmy Maenhout on 21/12/2020.
//

import os
import Foundation
struct CustomLogger {
    
    static func log(message: String) {
        if SharedPrefsUtil.isLoggingEnabled() {
            if #available(iOS 10.0, *) {
                let app = OSLog(subsystem: "com.icapps.background_location_tracker", category: "background tracker")
                os_log("🔥 background-location log: %{public}@", log: app, type: .error, message)
            }
            print(message)
        }
    }
    
    // Enhanced logging that's always visible in Xcode console
    static func logAlways(message: String) {
        // Always log to console (visible in Xcode)
        print("🔥 [ALWAYS] \(message)")
        
        // Also log to os_log if enabled
        if SharedPrefsUtil.isLoggingEnabled() {
            if #available(iOS 10.0, *) {
                let app = OSLog(subsystem: "com.icapps.background_location_tracker", category: "background tracker")
                os_log("🔥 [ALWAYS] background-location log: %{public}@", log: app, type: .error, message)
            }
        }
    }
    
    // Critical logging for important events (always visible)
    static func logCritical(message: String) {
        // Always log to console with CRITICAL prefix
        print("🚨 [CRITICAL] \(message)")
        
        // Also log to os_log if enabled
        if SharedPrefsUtil.isLoggingEnabled() {
            if #available(iOS 10.0, *) {
                let app = OSLog(subsystem: "com.icapps.background_location_tracker", category: "background tracker")
                os_log("🚨 [CRITICAL] background-location log: %{public}@", log: app, type: .error, message)
            }
        }
    }
}
