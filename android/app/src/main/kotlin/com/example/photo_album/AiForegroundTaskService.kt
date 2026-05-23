package com.example.photo_album

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class AiForegroundTaskService : Service() {
	override fun onBind(intent: Intent?): IBinder? = null

	override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
		val title = intent?.getStringExtra("title") ?: "Memoria 正在分析媒体"
		val text = intent?.getStringExtra("text") ?: "只处理你手动添加的媒体"
		startForeground(notificationId, buildNotification(title, text))
		return START_NOT_STICKY
	}

	private fun buildNotification(title: String, text: String): Notification {
		ensureChannel()
		return NotificationCompat.Builder(this, channelId)
			.setSmallIcon(android.R.drawable.ic_menu_gallery)
			.setContentTitle(title)
			.setContentText(text)
			.setOngoing(true)
			.setOnlyAlertOnce(true)
			.setPriority(NotificationCompat.PRIORITY_LOW)
			.build()
	}

	private fun ensureChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
			return
		}
		val manager = getSystemService(NotificationManager::class.java)
		val channel = NotificationChannel(
			channelId,
			"Memoria AI 分析",
			NotificationManager.IMPORTANCE_LOW,
		)
		manager.createNotificationChannel(channel)
	}

	companion object {
		const val channelId = "memoria_ai_foreground_task"
		const val notificationId = 43021
	}
}
