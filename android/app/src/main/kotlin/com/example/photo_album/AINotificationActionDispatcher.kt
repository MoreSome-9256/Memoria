package com.example.photo_album

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object AINotificationActionDispatcher {
    @Volatile
    var eventSink: EventChannel.EventSink? = null

    fun emit(action: String) {
        Handler(Looper.getMainLooper()).post {
            eventSink?.success(action)
        }
    }
}
