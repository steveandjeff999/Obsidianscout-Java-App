package com.obsidianscout.obsidianscout_app.widgets

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Fetches the snapshot right away when the server says something changed, so widgets update within seconds of a
 * push instead of waiting for WorkManager. Several widgets redraw together, so only one fetch runs at a time and
 * every caller's [finish] handle is released together once the fetch completes.
 */
object WidgetFetchNow {
    private val running = AtomicBoolean(false)
    private val waiters = ConcurrentLinkedQueue<() -> Unit>()

    /** [finish] is the receiver's goAsync handle; it's released when the fetch is done. */
    fun start(context: Context, finish: () -> Unit) {
        waiters.add(finish)
        if (!running.compareAndSet(false, true)) return
        val app = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val outcome = withTimeoutOrNull(9_000) { WidgetFetcher.fetch(app) }
                when (outcome) {
                    WidgetFetcher.Outcome.UPDATED, WidgetFetcher.Outcome.UNCHANGED, WidgetFetcher.Outcome.SIGNED_OUT -> {
                        WidgetAccessGate.applyFromSnapshot(app, WidgetPrefs.snapshot(app))
                        WidgetUpdater.updateAll(app)
                    }
                    WidgetFetcher.Outcome.NO_CREDENTIALS -> Unit
                    else -> WidgetScheduler.refreshSoon(app) // Retry through WorkManager when the network is back.
                }
            } finally {
                running.set(false)
                while (true) {
                    val cb = waiters.poll() ?: break
                    runCatching { cb() }
                }
            }
        }
    }
}

/** Manual refresh triggered by tapping the stale-data footer or loading state on a widget. */
class RefreshWidgetAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val app = context.applicationContext
        WidgetPrefs.of(app).edit()
            .putLong(WidgetPrefs.REFRESH_REQUESTED, System.currentTimeMillis() / 1000)
            .apply()
        val outcome = withContext(Dispatchers.IO) {
            withTimeoutOrNull(9_000) { WidgetFetcher.fetch(app) }
        }
        when (outcome) {
            WidgetFetcher.Outcome.UPDATED, WidgetFetcher.Outcome.UNCHANGED, WidgetFetcher.Outcome.SIGNED_OUT -> {
                WidgetAccessGate.applyFromSnapshot(app, WidgetPrefs.snapshot(app))
                WidgetUpdater.updateAll(app)
            }
            WidgetFetcher.Outcome.NO_CREDENTIALS -> Unit
            else -> WidgetScheduler.refreshSoon(app)
        }
    }
}

/**
 * Optimistically checks/unchecks a checklist item right on the home screen and syncs it to the server
 * (`POST /api/widgets/checklist/toggle`) without needing to cold-start the Flutter app.
 */
class ToggleChecklistItemAction : ActionCallback {
    companion object {
        val KEY_EVENT_KEY = ActionParameters.Key<String>("eventKey")
        val KEY_RECORD = ActionParameters.Key<String>("record")
        val KEY_ITEM_ID = ActionParameters.Key<String>("itemId")
        val KEY_CHECKED = ActionParameters.Key<Boolean>("checked")
    }

    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val app = context.applicationContext
        val eventKey = parameters[KEY_EVENT_KEY]?.takeIf { it.isNotBlank() } ?: return
        val record = parameters[KEY_RECORD]?.takeIf { it.isNotBlank() } ?: return
        val itemId = parameters[KEY_ITEM_ID]?.takeIf { it.isNotBlank() } ?: return
        val checked = parameters[KEY_CHECKED] ?: return

        val prefs = WidgetPrefs.of(app)
        val currentRaw = prefs.getString(WidgetPrefs.SNAPSHOT, null)
        val optimistic = Snapshot.toggleChecklistItem(currentRaw, record, itemId, checked)
        if (optimistic != null) {
            prefs.edit()
                .putString(WidgetPrefs.SNAPSHOT, optimistic)
                .remove(WidgetPrefs.ETAG)
                .apply()
            WidgetUpdater.update(app, WidgetKind.CHECKLIST)
        }

        val ok = withContext(Dispatchers.IO) {
            withTimeoutOrNull(9_000) {
                WidgetFetcher.toggleChecklistItem(app, eventKey, record, itemId, checked)
            } == true
        }
        if (ok) {
            val outcome = withContext(Dispatchers.IO) {
                withTimeoutOrNull(9_000) { WidgetFetcher.fetch(app) }
            }
            if (outcome == WidgetFetcher.Outcome.UPDATED || outcome == WidgetFetcher.Outcome.SIGNED_OUT) {
                WidgetAccessGate.applyFromSnapshot(app, WidgetPrefs.snapshot(app))
                WidgetUpdater.updateAll(app)
            }
        } else {
            WidgetScheduler.refreshSoon(app)
        }
    }
}
