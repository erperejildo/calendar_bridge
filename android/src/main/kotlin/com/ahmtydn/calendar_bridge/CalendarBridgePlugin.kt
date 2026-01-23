package com.ahmtydn.calendar_bridge

import android.app.Activity
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/** CalendarBridgePlugin */
class CalendarBridgePlugin: FlutterPlugin, MethodCallHandler, ActivityAware, 
    PluginRegistry.RequestPermissionsResultListener {
  private lateinit var channel: MethodChannel
  private lateinit var calendarManager: CalendarManager
  private lateinit var eventManager: EventManager
  private var activity: Activity? = null
  private val scope = CoroutineScope(Dispatchers.Main)
  private var permissionResult: Result? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.ahmtydn/calendar_bridge")
    channel.setMethodCallHandler(this)
    
    calendarManager = CalendarManager(flutterPluginBinding.applicationContext)
    eventManager = EventManager(flutterPluginBinding.applicationContext)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    scope.launch {
      try {
        when (call.method) {
          "requestPermissions" -> {
            handleRequestPermissions(result)
          }
          
          "hasPermissions" -> {
            val hasPermission = calendarManager.hasPermissions()
            result.success(hasPermission)
          }
          
          "retrieveCalendars" -> {
            handleRetrieveCalendars(result)
          }
          
          "retrieveEvents" -> {
            handleRetrieveEvents(call, result)
          }
          
          "createEvent" -> {
            handleCreateEvent(call, result)
          }
          
          "updateEvent" -> {
            handleUpdateEvent(call, result)
          }
          
          "deleteEvent" -> {
            handleDeleteEvent(call, result)
          }
          
          "createCalendar" -> {
            handleCreateCalendar(call, result)
          }
          
          "deleteCalendar" -> {
            handleDeleteCalendar(call, result)
          }
          
          "retrieveCalendarColors" -> {
            handleRetrieveCalendarColors(result)
          }
          
          "retrieveEventColors" -> {
            handleRetrieveEventColors(call, result)
          }
          
          "updateCalendarColor" -> {
            handleUpdateCalendarColor(call, result)
          }
          
          "deleteEventInstance" -> {
            handleDeleteEventInstance(call, result)
          }
          
          else -> {
            result.notImplemented()
          }
        }
      } catch (e: Exception) {
        handleError(e, result)
      }
    }
  }

  private fun handleRequestPermissions(result: Result) {
    if (calendarManager.hasPermissionsBoolean()) {
      result.success(true)
      return
    }
    val currentActivity = activity
    if (currentActivity == null) {
      result.success(false)
      return
    }
    permissionResult = result
    calendarManager.requestPermissions(currentActivity)
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray
  ): Boolean {
    if (requestCode == CalendarManager.PERMISSION_REQUEST_CODE) {
      val granted = calendarManager.hasPermissionsBoolean()
      permissionResult?.let {
        it.success(granted)
        permissionResult = null
      }
      return true
    }
    return false
  }

  private suspend fun handleRetrieveCalendars(result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val calendars = calendarManager.retrieveCalendars()
    result.success(calendars)
  }

  private suspend fun handleRetrieveEvents(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendarId = arguments["calendarId"] as? String
      ?: throw CalendarException.InvalidArgument("Calendar ID is required")
    
    val events = eventManager.retrieveEvents(calendarId, arguments)
    result.success(events)
  }

  private suspend fun handleCreateEvent(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val eventId = eventManager.createEvent(arguments)
    result.success(eventId)
  }

  private suspend fun handleUpdateEvent(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val eventId = eventManager.updateEvent(arguments)
    result.success(eventId)
  }

  private suspend fun handleDeleteEvent(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendarId = arguments["calendarId"] as? String
      ?: throw CalendarException.InvalidArgument("Calendar ID is required")
    
    val eventId = arguments["eventId"] as? String
      ?: throw CalendarException.InvalidArgument("Event ID is required")
    
    val success = eventManager.deleteEvent(calendarId, eventId)
    result.success(success)
  }

  private suspend fun handleCreateCalendar(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendar = calendarManager.createCalendar(arguments)
    result.success(calendar)
  }

  private suspend fun handleDeleteCalendar(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendarId = arguments["calendarId"] as? String
      ?: throw CalendarException.InvalidArgument("Calendar ID is required")
    
    val success = calendarManager.deleteCalendar(calendarId)
    result.success(success)
  }

  private fun handleError(error: Throwable, result: Result) {
    when (error) {
      is CalendarException -> {
        result.error(error.code, error.message, error.details)
      }
      else -> {
        result.error("UNKNOWN_ERROR", "An unexpected error occurred", error.message)
      }
    }
  }

  private suspend fun handleRetrieveCalendarColors(result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val colors = calendarManager.getCalendarColors()
    result.success(colors)
  }

  private suspend fun handleRetrieveEventColors(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendarId = arguments["calendarId"] as? String
      ?: throw CalendarException.InvalidArgument("Missing calendarId")
    
    val colors = calendarManager.getEventColors(calendarId)
    result.success(colors)
  }

  private suspend fun handleUpdateCalendarColor(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendarId = arguments["calendarId"] as? String
      ?: throw CalendarException.InvalidArgument("Missing calendarId")
      
    val colorKey = arguments["colorKey"] as? String
      ?: throw CalendarException.InvalidArgument("Missing colorKey")
    
    val success = calendarManager.updateCalendarColor(calendarId, colorKey)
    result.success(success)
  }

  private suspend fun handleDeleteEventInstance(call: MethodCall, result: Result) {
    if (!calendarManager.hasPermissionsBoolean()) {
      throw CalendarException.PermissionDenied()
    }
    
    val arguments = call.arguments as? Map<String, Any>
      ?: throw CalendarException.InvalidArgument("Missing arguments")
    
    val calendarId = arguments["calendarId"] as? String
      ?: throw CalendarException.InvalidArgument("Missing calendarId")
      
    val eventId = arguments["eventId"] as? String
      ?: throw CalendarException.InvalidArgument("Missing eventId")
      
    val startDate = arguments["startDate"] as? Long
      ?: throw CalendarException.InvalidArgument("Missing startDate")
      
    val followingInstances = arguments["followingInstances"] as? Boolean ?: false
    
    val success = eventManager.deleteEventInstance(calendarId, eventId, startDate, followingInstances)
    result.success(success)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
    calendarManager.setActivity(activity)
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
    calendarManager.setActivity(null)
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
    calendarManager.setActivity(activity)
    binding.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivity() {
    activity = null
    calendarManager.setActivity(null)
  }
}