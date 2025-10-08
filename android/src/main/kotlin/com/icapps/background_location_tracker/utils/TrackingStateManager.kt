package com.icapps.background_location_tracker.utils

import android.content.Context
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Centralized tracking state manager - single source of truth for location tracking state.
 * Thread-safe implementation with state change listeners.
 */
internal object TrackingStateManager {
    
    private var currentState: TrackingState = TrackingState.Stopped
    private val stateListeners = CopyOnWriteArrayList<(TrackingState) -> Unit>()
    private var lastLocationTime: Long = 0
    private var updateCount: Int = 0
    
    /**
     * Represents the current state of location tracking
     */
    sealed class TrackingState {
        /** Tracking is completely stopped */
        object Stopped : TrackingState()
        
        /** Tracking is in the process of starting */
        object Starting : TrackingState()
        
        /** Tracking is active and receiving location updates */
        data class Running(
            val startTime: Long,
            val updateCount: Int
        ) : TrackingState()
        
        /** Tracking encountered an error */
        data class Error(
            val errorCode: String,
            val errorMessage: String
        ) : TrackingState()
        
        /** Tracking is in the process of stopping */
        object Stopping : TrackingState()
        
        /** User requested tracking but waiting for permission */
        object WaitingForPermission : TrackingState()
        
        /** User requested tracking but waiting for location services to be enabled */
        object WaitingForLocationServices : TrackingState()
    }
    
    /**
     * Initialize state from SharedPreferences on app start
     */
    @Synchronized
    fun initialize(context: Context) {
        val wasTracking = SharedPrefsUtil.isTracking(context)
        val wasActive = SharedPrefsUtil.isTrackingActive(context)
        
        currentState = when {
            wasTracking -> TrackingState.Starting // Will verify and transition appropriately
            wasActive -> TrackingState.WaitingForPermission
            else -> TrackingState.Stopped
        }
        
        Logger.debug("TrackingStateManager", "Initialized with state: ${getStateName()}")
    }
    
    /**
     * Get the current tracking state
     */
    @Synchronized
    fun getState(): TrackingState = currentState
    
    /**
     * Check if currently in a tracking state
     */
    @Synchronized
    fun isTracking(): Boolean = currentState is TrackingState.Running || currentState is TrackingState.Starting
    
    /**
     * Check if user wants to track (including waiting states)
     */
    @Synchronized
    fun wantsToTrack(): Boolean = when (currentState) {
        is TrackingState.Stopped, is TrackingState.Stopping -> false
        else -> true
    }
    
    /**
     * Update the tracking state and notify listeners
     */
    @Synchronized
    fun setState(newState: TrackingState, context: Context) {
        val oldState = currentState
        currentState = newState
        
        Logger.debug("TrackingStateManager", "State transition: ${getStateName(oldState)} -> ${getStateName(newState)}")
        
        // Persist state to SharedPreferences
        when (newState) {
            is TrackingState.Running -> {
                SharedPrefsUtil.saveIsTracking(context, true)
                SharedPrefsUtil.saveTrackingActive(context, true)
            }
            is TrackingState.Starting -> {
                SharedPrefsUtil.saveIsTracking(context, true)
                SharedPrefsUtil.saveTrackingActive(context, true)
            }
            is TrackingState.Stopped -> {
                SharedPrefsUtil.saveIsTracking(context, false)
                SharedPrefsUtil.saveTrackingActive(context, false)
            }
            is TrackingState.WaitingForPermission, 
            is TrackingState.WaitingForLocationServices -> {
                SharedPrefsUtil.saveIsTracking(context, false)
                SharedPrefsUtil.saveTrackingActive(context, true) // User wants to track
            }
            is TrackingState.Error -> {
                SharedPrefsUtil.saveIsTracking(context, false)
                // Don't clear active state - might recover
            }
            is TrackingState.Stopping -> {
                // Intermediate state, don't persist yet
            }
        }
        
        // Notify listeners
        notifyStateChange(newState)
    }
    
    /**
     * Record that a location update was received
     */
    @Synchronized
    fun recordLocationUpdate(context: Context) {
        updateCount++
        lastLocationTime = System.currentTimeMillis()
        
        // If we're in Starting state, transition to Running
        if (currentState is TrackingState.Starting) {
            setState(TrackingState.Running(System.currentTimeMillis(), updateCount), context)
        } else if (currentState is TrackingState.Running) {
            // Update the running state with new count
            setState(TrackingState.Running((currentState as TrackingState.Running).startTime, updateCount), context)
        }
    }
    
    /**
     * Get the last location update time
     */
    @Synchronized
    fun getLastLocationTime(): Long = lastLocationTime
    
    /**
     * Get the total number of location updates received
     */
    @Synchronized
    fun getUpdateCount(): Int = updateCount
    
    /**
     * Reset update counter (called when tracking stops)
     */
    @Synchronized
    fun resetCounters() {
        updateCount = 0
        lastLocationTime = 0
    }
    
    /**
     * Add a state change listener
     */
    fun addStateListener(listener: (TrackingState) -> Unit) {
        stateListeners.add(listener)
    }
    
    /**
     * Remove a state change listener
     */
    fun removeStateListener(listener: (TrackingState) -> Unit) {
        stateListeners.remove(listener)
    }
    
    /**
     * Notify all listeners of state change
     */
    private fun notifyStateChange(newState: TrackingState) {
        stateListeners.forEach { listener ->
            try {
                listener(newState)
            } catch (e: Exception) {
                Logger.error("TrackingStateManager", "Error notifying state listener: ${e.message}")
            }
        }
    }
    
    /**
     * Get a human-readable state name for logging
     */
    private fun getStateName(state: TrackingState = currentState): String = when (state) {
        is TrackingState.Stopped -> "Stopped"
        is TrackingState.Starting -> "Starting"
        is TrackingState.Running -> "Running (${state.updateCount} updates)"
        is TrackingState.Error -> "Error: ${state.errorCode}"
        is TrackingState.Stopping -> "Stopping"
        is TrackingState.WaitingForPermission -> "Waiting for Permission"
        is TrackingState.WaitingForLocationServices -> "Waiting for Location Services"
    }
    
    /**
     * Get state diagnostics for debugging
     */
    @Synchronized
    fun getDiagnostics(): Map<String, Any> = mapOf(
        "state" to getStateName(),
        "isTracking" to isTracking(),
        "wantsToTrack" to wantsToTrack(),
        "updateCount" to updateCount,
        "lastLocationTime" to lastLocationTime,
        "timeSinceLastUpdate" to if (lastLocationTime > 0) 
            System.currentTimeMillis() - lastLocationTime else -1
    )
}

