package com.obsidianscout.obsidianscout_app.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.PowerManager
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** Every home-screen widget, keyed by the id the server's snapshot uses for it. */
enum class WidgetKind(val id: String, val receiver: Class<*>, val widget: () -> GlanceAppWidget) {
    NEXT_MATCH("next_match", NextMatchWidgetReceiver::class.java, ::NextMatchWidget),
    SCHEDULE("schedule", ScheduleWidgetReceiver::class.java, ::ScheduleWidget),
    PREDICTOR("predictor", PredictorWidgetReceiver::class.java, ::PredictorWidget),
    ASSIGNMENTS("assignments", AssignmentsWidgetReceiver::class.java, ::AssignmentsWidget),
    BATTERY("battery", BatteryWidgetReceiver::class.java, ::BatteryWidget),
    CHECKLIST("checklist", ChecklistWidgetReceiver::class.java, ::ChecklistWidget),
    RANKINGS("rankings", RankingsWidgetReceiver::class.java, ::RankingsWidget),
    CHAT("chat", ChatWidgetReceiver::class.java, ::ChatWidget),
    QUICK_ACTIONS("quick_actions", QuickActionsWidgetReceiver::class.java, ::QuickActionsWidget);

    fun component(context: Context) = ComponentName(context, receiver)

    fun placedIds(context: Context): IntArray =
        runCatching { AppWidgetManager.getInstance(context).getAppWidgetIds(component(context)) }.getOrDefault(IntArray(0))
}

/**
 * Shows only the widgets the signed-in user may have. A widget's receiver is a manifest component that starts
 * turned off; this turns each one on or off to match the snapshot's `widgets` map (the server works that out from
 * the user's role page permissions, the team's chat switch and their Non-Scouting Tools opt-in). A turned-off
 * widget is not offered in the widget picker, and one already on the home screen is removed by the launcher.
 */
object WidgetAccessGate {
    /** With [onlyEnable], widgets are only turned on, never off (used before the server has confirmed access). */
    fun apply(context: Context, allowed: Map<String, Boolean>, onlyEnable: Boolean = false) {
        val pm = context.packageManager
        for (kind in WidgetKind.entries) {
            val want = if (allowed[kind.id] == true) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            val component = kind.component(context)
            val current = pm.getComponentEnabledSetting(component)
            val isOn = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            val wantOn = want == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            if (onlyEnable && !wantOn) continue
            if (isOn != wantOn) pm.setComponentEnabledSetting(component, want, PackageManager.DONT_KILL_APP)
        }
    }

    /** Signing out leaves widgets where they are (showing "sign in"); the next account's access decides what stays. */
    fun applyFromSnapshot(context: Context, snapshot: Snapshot) {
        if (snapshot.present) {
            apply(context, WidgetKind.entries.associate { it.id to snapshot.allowed(it.id) })
        }
    }
}

/** Redraws placed widgets from the stored snapshot. */
object WidgetUpdater {
    suspend fun updateAll(context: Context) {
        for (kind in WidgetKind.entries) update(context, kind)
        WidgetScheduler.armClock(context)
    }

    suspend fun update(context: Context, kind: WidgetKind) {
        if (kind.placedIds(context).isEmpty()) return
        val widget = kind.widget()
        runCatching {
            GlanceAppWidgetManager(context).getGlanceIds(widget.javaClass).forEach { id ->
                updateAppWidgetState<HomeWidgetGlanceState>(context, HomeWidgetGlanceStateDefinition(), id) { it }
                widget.update(context, id)
            }
        }
    }

    fun anyPlaced(context: Context) = WidgetKind.entries.any { it.placedIds(context).isNotEmpty() }
}

/**
 * Keeps widgets current while the app is closed:
 * - a WorkManager job fetches the snapshot every 15 minutes (the shortest period Android allows) while widgets are placed,
 * - an expedited one-off fetch runs when the server sends a silent refresh push (or the stored snapshot is old when a widget redraws),
 * - an alarm redraws the widgets when the next match is due, so the countdown and "next match" move on with no network.
 */
object WidgetScheduler {
    private const val PERIODIC = "obsidian_widget_refresh"
    private const val ONE_OFF = "obsidian_widget_refresh_now"
    private const val STALE_SECONDS = 15 * 60L
    private const val MIN_GAP_SECONDS = 3L
    private const val HANDLED_REQUEST = "widget_refresh_handled"

    private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    private fun isInteractive(context: Context): Boolean =
        runCatching { (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isInteractive ?: true }.getOrDefault(true)

    fun ensurePeriodic(context: Context) {
        val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(15, TimeUnit.MINUTES).setConstraints(network).build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(PERIODIC, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun refreshSoon(context: Context) {
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setConstraints(network)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(ONE_OFF, ExistingWorkPolicy.REPLACE, request)
    }

    fun stopIfUnused(context: Context) {
        if (WidgetUpdater.anyPlaced(context)) return
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pollIntent(context))
        pollFired(context)
        WorkManager.getInstance(context).cancelUniqueWork(PERIODIC)
        clockIntent(context)?.let { (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(it) }
    }

    /**
     * Called whenever a widget redraws. When the server pushed a change, or the screen is interactive and data is
     * older than the poll window, it triggers [WidgetPollReceiver] (which holds its own independent `goAsync()`
     * handle rather than conflicting with Glance's receiver).
     */
    fun onWidgetsUpdated(context: Context) {
        val prefs = WidgetPrefs.of(context)
        val now = System.currentTimeMillis() / 1000
        val fetchedAt = WidgetPrefs.long(prefs, WidgetPrefs.FETCHED_AT)
        val requested = WidgetPrefs.long(prefs, WidgetPrefs.REFRESH_REQUESTED)
        val handled = WidgetPrefs.long(prefs, HANDLED_REQUEST)
        val newest = maxOf(fetchedAt, WidgetPrefs.snapshot(context).generatedAt)
        val pushed = requested > handled
        val signedIn = !prefs.getString(WidgetPrefs.TOKEN, null).isNullOrBlank()
        val interactive = isInteractive(context)
        val dueOnScreen = interactive && signedIn && (now - newest >= POLL_SECONDS)
        if (pushed || (now - fetchedAt >= MIN_GAP_SECONDS && (now - newest > STALE_SECONDS || dueOnScreen))) {
            prefs.edit().putLong(HANDLED_REQUEST, requested).apply()
            WidgetPollReceiver.triggerNow(context)
        }
        ensurePeriodic(context)
        armClock(context)
        armPoll(context)
    }

    /** How often placed widgets poll the server while the screen is interactive, so they stay current even without push. */
    private const val POLL_SECONDS = 45L
    private const val NEXT_POLL = "widget_next_poll_at"

    private fun pollIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 1, Intent(context, WidgetPollReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /**
     * Schedules the next 45s poll while any widget is placed, the widgets are signed in, and the screen is on.
     * While the screen is off in a pocket, 45s alarm polling is paused to save battery (WorkManager and push
     * still update in the background, and unlocking/viewing the home screen resumes polling immediately).
     */
    fun armPoll(context: Context) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val signedIn = !WidgetPrefs.of(context).getString(WidgetPrefs.TOKEN, null).isNullOrBlank()
        if (!signedIn || !WidgetUpdater.anyPlaced(context) || !isInteractive(context)) {
            alarm.cancel(pollIntent(context))
            pollFired(context)
            return
        }
        // Widgets redraw often; keep an already scheduled poll instead of pushing it back every time.
        val prefs = WidgetPrefs.of(context)
        val now = System.currentTimeMillis()
        val scheduled = WidgetPrefs.long(prefs, NEXT_POLL)
        if (scheduled in (now + 1)..(now + POLL_SECONDS * 1000)) return
        val next = now + POLL_SECONDS * 1000
        prefs.edit().putLong(NEXT_POLL, next).apply()
        alarm.setAndAllowWhileIdle(AlarmManager.RTC, next, pollIntent(context))
    }

    /** The poll receiver clears the schedule so its own re-arm always goes through. */
    fun pollFired(context: Context) {
        WidgetPrefs.of(context).edit().remove(NEXT_POLL).apply()
    }

    private fun clockIntent(context: Context): PendingIntent? = PendingIntent.getBroadcast(
        context, 0, Intent(context, WidgetClockReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** Inexact, allowed while idle, no special permission: a minute or two late is fine for a countdown hand-off. */
    fun armClock(context: Context) {
        val next = WidgetPrefs.snapshot(context).nextTransition(System.currentTimeMillis() / 1000) ?: return
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = clockIntent(context) ?: return
        alarm.setAndAllowWhileIdle(AlarmManager.RTC, (next + 1) * 1000, pi)
    }
}

/** Fetches the snapshot on the poll timer or explicit trigger, then schedules the next poll. */
class WidgetPollReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        WidgetScheduler.pollFired(context)
        WidgetScheduler.armPoll(context)
        WidgetFetchNow.start(context) { runCatching { pending.finish() } }
    }

    companion object {
        fun triggerNow(context: Context) {
            runCatching {
                context.sendBroadcast(Intent(context, WidgetPollReceiver::class.java))
            }.onFailure {
                WidgetScheduler.refreshSoon(context)
            }
        }
    }
}

class WidgetClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                WidgetUpdater.updateAll(context)
            } finally {
                runCatching { pending.finish() }
            }
        }
    }
}

/** Re-arms alarms and refreshes placed widgets after a phone reboot or app update. */
class WidgetBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) return
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                WidgetScheduler.pollFired(context)
                WidgetAccessGate.applyFromSnapshot(context, WidgetPrefs.snapshot(context))
                if (WidgetUpdater.anyPlaced(context)) {
                    WidgetUpdater.updateAll(context)
                    WidgetScheduler.ensurePeriodic(context)
                    WidgetScheduler.armClock(context)
                    WidgetScheduler.armPoll(context)
                    WidgetScheduler.refreshSoon(context)
                }
            } finally {
                runCatching { pending.finish() }
            }
        }
    }
}

/** Fetches the snapshot with the widget token, applies who-may-see-what, and redraws. */
class WidgetRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val ctx = applicationContext
        if (!WidgetUpdater.anyPlaced(ctx)) return Result.success()
        return when (WidgetFetcher.fetch(ctx)) {
            WidgetFetcher.Outcome.UPDATED, WidgetFetcher.Outcome.UNCHANGED, WidgetFetcher.Outcome.SIGNED_OUT -> {
                WidgetAccessGate.applyFromSnapshot(ctx, WidgetPrefs.snapshot(ctx))
                WidgetUpdater.updateAll(ctx)
                Result.success()
            }
            WidgetFetcher.Outcome.NO_CREDENTIALS -> Result.success()
            WidgetFetcher.Outcome.FAILED -> Result.retry()
        }
    }
}

object WidgetFetcher {
    enum class Outcome { UPDATED, UNCHANGED, SIGNED_OUT, NO_CREDENTIALS, FAILED }

    fun fetch(context: Context): Outcome {
        val prefs = WidgetPrefs.of(context)
        val token = prefs.getString(WidgetPrefs.TOKEN, null)?.takeIf { it.isNotBlank() }
        val server = prefs.getString(WidgetPrefs.SERVER_URL, null)?.trimEnd('/')?.takeIf { it.isNotBlank() }
        if (token == null || server == null) return Outcome.NO_CREDENTIALS

        val placed = WidgetKind.entries.filter { it.placedIds(context).isNotEmpty() }.joinToString(",") { it.id }
        val url = Uri.parse("$server/api/widgets/snapshot").buildUpon().appendQueryParameter("placed", placed).build().toString()
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 10_000
            readTimeout = 20_000
            setRequestProperty("Authorization", "Widget $token")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Mobile-App", "true")
            prefs.getString(WidgetPrefs.ETAG, null)?.let { setRequestProperty("If-None-Match", it) }
        }
        return try {
            val now = System.currentTimeMillis() / 1000
            when (conn.responseCode) {
                200 -> {
                    val body = conn.inputStream.bufferedReader().use { it.readText() }
                    if (!Snapshot.parse(body).present) return Outcome.FAILED
                    prefs.edit()
                        .putString(WidgetPrefs.SNAPSHOT, body)
                        .putString(WidgetPrefs.ETAG, conn.getHeaderField("ETag"))
                        .putLong(WidgetPrefs.FETCHED_AT, now)
                        .putBoolean(WidgetPrefs.AUTH_EXPIRED, false)
                        .apply()
                    Outcome.UPDATED
                }
                304 -> {
                    prefs.edit()
                        .putLong(WidgetPrefs.FETCHED_AT, now)
                        .putBoolean(WidgetPrefs.AUTH_EXPIRED, false)
                        .apply()
                    Outcome.UNCHANGED
                }
                401 -> {
                    // Signed out elsewhere, the device was revoked, or the token ran out: stop showing account data.
                    prefs.edit()
                        .remove(WidgetPrefs.TOKEN)
                        .remove(WidgetPrefs.ETAG)
                        .putBoolean(WidgetPrefs.AUTH_EXPIRED, true)
                        .putString(WidgetPrefs.SNAPSHOT, """{"v":1,"signedOut":true}""")
                        .putLong(WidgetPrefs.FETCHED_AT, now)
                        .apply()
                    Outcome.SIGNED_OUT
                }
                else -> Outcome.FAILED
            }
        } catch (_: Exception) {
            Outcome.FAILED
        } finally {
            conn.disconnect()
        }
    }

    /** Sends an item check/uncheck to `POST /api/widgets/checklist/toggle` using the widget token. */
    fun toggleChecklistItem(context: Context, eventKey: String, record: String, itemId: String, checked: Boolean): Boolean {
        val prefs = WidgetPrefs.of(context)
        val token = prefs.getString(WidgetPrefs.TOKEN, null)?.takeIf { it.isNotBlank() } ?: return false
        val server = prefs.getString(WidgetPrefs.SERVER_URL, null)?.trimEnd('/')?.takeIf { it.isNotBlank() } ?: return false
        val payload = JSONObject().apply {
            put("eventKey", eventKey)
            put("record", record)
            put("itemId", itemId)
            put("checked", checked)
        }.toString()
        val conn = (URL("$server/api/widgets/checklist/toggle").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 8_000
            readTimeout = 10_000
            setRequestProperty("Authorization", "Widget $token")
            setRequestProperty("Content-Type", "application/json; charset=utf-8")
            setRequestProperty("Accept", "application/json")
            setRequestProperty("X-Mobile-App", "true")
        }
        return try {
            conn.outputStream.use { it.write(payload.toByteArray(Charsets.UTF_8)) }
            when (conn.responseCode) {
                in 200..299 -> {
                    prefs.edit().remove(WidgetPrefs.ETAG).apply()
                    true
                }
                401 -> {
                    val now = System.currentTimeMillis() / 1000
                    prefs.edit()
                        .remove(WidgetPrefs.TOKEN)
                        .remove(WidgetPrefs.ETAG)
                        .putBoolean(WidgetPrefs.AUTH_EXPIRED, true)
                        .putString(WidgetPrefs.SNAPSHOT, """{"v":1,"signedOut":true}""")
                        .putLong(WidgetPrefs.FETCHED_AT, now)
                        .apply()
                    false
                }
                else -> false
            }
        } catch (_: Exception) {
            false
        } finally {
            conn.disconnect()
        }
    }
}
