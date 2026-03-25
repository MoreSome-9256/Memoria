package com.example.photo_album

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object AppNavigationDispatcher {
    @Volatile
    var eventSink: EventChannel.EventSink? = null

    @Volatile
    private var pendingTarget: String? = null

    fun emitOrQueue(target: String) {
        val sink = eventSink
        if (sink != null) {
            Handler(Looper.getMainLooper()).post {
                sink.success(target)
            }
            return
        }
        pendingTarget = target
    }

    fun consumePendingTarget(): String? {
        val target = pendingTarget
        pendingTarget = null
        return target
    }
}
