package com.obsidianscout.obsidianscout_app.widgets

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Fetches the snapshot right away when the server says something changed, so widgets update within seconds of a
 * push instead of waiting for WorkManager. Several widgets redraw together, so only one fetch runs at a time.
 */
object WidgetFetchNow {
    private val running = AtomicBoolean(false)

    /** [finish] is the receiver's goAsync handle; it's released when the fetch is done. */
    fun start(context: Context, finish: () -> Unit) {
        if (!running.compareAndSet(false, true)) {
            finish()
            return
        }
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
                finish()
            }
        }
    }
}
