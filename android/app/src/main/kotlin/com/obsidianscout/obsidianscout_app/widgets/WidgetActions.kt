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
 * push instead of waiting for WorkManager. Several widgets redraw together, so only one fetch runs at a time.
 * Each caller's [finish] handle is released only by a fetch that started after the caller asked; callers that
 * arrive while a fetch is running get one more fetch when it ends.
 */
object WidgetFetchNow {
    private val running = AtomicBoolean(false)
    private val waiters = ConcurrentLinkedQueue<() -> Unit>()

    /** [finish] is the receiver's goAsync handle; it's released when the fetch is done. */
    fun start(context: Context, finish: () -> Unit) {
        waiters.add(finish)
        if (!running.compareAndSet(false, true)) return
        val app = context.applicationContext
        CoroutineScope(Dispatchers.IO).launch { runRounds(app) }
    }

    private suspend fun runRounds(app: Context) {
        while (true) {
            // The callers this round answers: everyone who asked before it started.
            val batch = generateSequence { waiters.poll() }.toList()
            try {
                fetchAndRedraw(app)
            } finally {
                batch.forEach { runCatching { it() } }
            }
            running.set(false)
            // Someone asked while this round ran: run again for them (unless another caller already took over).
            if (waiters.isEmpty() || !running.compareAndSet(false, true)) return
        }
    }

    suspend fun fetchAndRedraw(app: Context) {
        when (withTimeoutOrNull(9_000) { WidgetFetcher.fetch(app) }) {
            WidgetFetcher.Outcome.UPDATED, WidgetFetcher.Outcome.UNCHANGED, WidgetFetcher.Outcome.SIGNED_OUT -> {
                WidgetAccessGate.applyFromSnapshot(app, WidgetPrefs.snapshot(app))
                WidgetUpdater.updateAll(app)
            }
            WidgetFetcher.Outcome.NO_CREDENTIALS -> Unit
            else -> WidgetScheduler.refreshSoon(app) // Retry through WorkManager when the network is back.
        }
    }
}

/** Manual refresh triggered by tapping the stale-data footer or loading state on a widget. */
class RefreshWidgetAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        // Fetches directly; it doesn't set the push "refresh requested" flag, which would make the next redraw
        // fetch the same snapshot again.
        withContext(Dispatchers.IO) { WidgetFetchNow.fetchAndRedraw(context.applicationContext) }
    }
}
