package com.obsidianscout.obsidianscout_app.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.net.Uri
import android.os.SystemClock
import android.text.format.DateFormat
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.obsidianscout.obsidianscout_app.MainActivity
import com.obsidianscout.obsidianscout_app.R
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.actionStartActivity
import java.util.Date
import java.util.Locale

/** Colors from the app's Obsidian theme (lib/theme/obsidian_ui_theme.dart). */
data class Palette(
    val background: Color,
    val surface: Color,
    val text: Color,
    val muted: Color,
    val accent: Color,
    val red: Color,
    val blue: Color,
    val green: Color,
    val orange: Color,
) {
    companion object {
        val dark = Palette(
            background = Color(0xFF0A0C10), surface = Color(0xFF1A1F2C), text = Color(0xFFF5F7FF), muted = Color(0xFF9AA3B8),
            accent = Color(0xFF5B6CFF), red = Color(0xFFFF4D6A), blue = Color(0xFF4DA3FF), green = Color(0xFF00E676), orange = Color(0xFFFF9100),
        )
        val light = Palette(
            background = Color(0xFFF4F6FB), surface = Color(0xFFFFFFFF), text = Color(0xFF12141A), muted = Color(0xFF5B6475),
            accent = Color(0xFF4757E6), red = Color(0xFFD7263D), blue = Color(0xFF1E6FD9), green = Color(0xFF00A152), orange = Color(0xFFE67E00),
        )
    }
}

/** Everything a widget needs to draw: the snapshot, the device state, strings in the app's language, and the time. */
class WidgetEnv(val context: Context, val snapshot: Snapshot, val local: LocalState, val authExpired: Boolean, val palette: Palette) {
    val now: Long = System.currentTimeMillis() / 1000

    fun s(id: Int, vararg args: Any): String = if (args.isEmpty()) context.getString(id) else context.getString(id, *args)

    fun c(color: Color) = ColorProvider(color)

    /** Page access from the server snapshot, or from the app until the first snapshot arrives. */
    fun page(id: String) = if (snapshot.present) snapshot.page(id) else local.signedIn && local.pages[id] == true

    /** "Qual 22", "SF 2-1"... built from the match's level and numbers. */
    fun matchLabel(compLevel: String?, set: Int?, number: Int?, fallback: String = ""): String {
        val n = number ?: return fallback
        return when ((compLevel ?: "").lowercase()) {
            "qm", "q", "qual", "qualification" -> s(R.string.w_quals, n)
            "p", "pr", "pm", "practice" -> s(R.string.w_practice, n)
            "qf" -> s(R.string.w_qf, set ?: 1, n)
            "sf" -> s(R.string.w_sf, set ?: 1, n)
            "f" -> s(R.string.w_final, n)
            "playoff", "playoffs" -> s(R.string.w_playoff, set ?: n)
            else -> fallback.ifEmpty { "${compLevel.orEmpty().uppercase()} $n" }
        }
    }

    fun matchLabel(m: WMatch) = matchLabel(m.compLevel, m.set, m.number, m.label)

    /** Clock time in the phone's 12/24-hour style. */
    fun clock(epochSeconds: Long): String = DateFormat.getTimeFormat(context).format(Date(epochSeconds * 1000))

    /** "8 min behind" / "3 min ahead" / "On time" for the event's running offset. */
    fun offset(seconds: Long): String {
        val minutes = (kotlin.math.abs(seconds) + 30) / 60
        return when {
            minutes < 1 -> s(R.string.w_on_time)
            seconds > 0 -> s(R.string.w_behind, minutes.toInt())
            else -> s(R.string.w_ahead, minutes.toInt())
        }
    }

    fun offsetColor(seconds: Long): Color = when {
        seconds >= 5 * 60 -> palette.orange
        seconds <= -5 * 60 -> palette.blue
        else -> palette.green
    }

    fun updatedAgo(): String? {
        val at = snapshot.generatedAt.takeIf { it > 0 } ?: return null
        val minutes = (now - at) / 60
        if (minutes < 15) return null
        return s(R.string.w_updated, android.text.format.DateUtils.getRelativeTimeSpanString(at * 1000, now * 1000, android.text.format.DateUtils.MINUTE_IN_MILLIS).toString())
    }

    fun open(uri: String): Action = actionStartActivity<MainActivity>(context, Uri.parse(uri))
    fun openPage(page: String): Action = open("obsidianscout://widget/page/$page")
}

/** Reads the shared storage and resolves language and theme the way the app has them set. */
@Composable
fun rememberWidgetEnv(): WidgetEnv {
    val base = LocalContext.current
    val prefs = currentState<HomeWidgetGlanceState>().preferences
    val snapshot = Snapshot.parse(prefs.getString(WidgetPrefs.SNAPSHOT, null))
    val local = LocalState.parse(prefs.getString(WidgetPrefs.LOCAL, null))
    val config = Configuration(base.resources.configuration)
    local.locale?.let { config.setLocale(Locale.forLanguageTag(it)) }
    val context = base.createConfigurationContext(config)
    val systemDark = (base.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    val dark = when (local.theme) {
        "light" -> false
        "system" -> systemDark
        else -> true
    }
    return WidgetEnv(context, snapshot, local, prefs.getBoolean(WidgetPrefs.AUTH_EXPIRED, false), if (dark) Palette.dark else Palette.light)
}

@Composable
fun WidgetFrame(env: WidgetEnv, onClick: Action?, content: @Composable () -> Unit) {
    var modifier = GlanceModifier.fillMaxSize().background(env.c(env.palette.background)).cornerRadius(20.dp).padding(12.dp)
    if (onClick != null) modifier = modifier.clickable(onClick)
    Box(modifier = modifier) { content() }
}

@Composable
fun FaIcon(env: WidgetEnv, res: Int, color: Color, size: Dp = 14.dp) {
    Image(
        provider = ImageProvider(res),
        contentDescription = null,
        modifier = GlanceModifier.size(size),
        colorFilter = ColorFilter.tint(env.c(color)),
    )
}

@Composable
fun Label(env: WidgetEnv, text: String, size: TextUnit = 12.sp, color: Color = env.palette.text, bold: Boolean = false, maxLines: Int = 1, modifier: GlanceModifier = GlanceModifier) {
    Text(
        text = text,
        maxLines = maxLines,
        modifier = modifier,
        style = TextStyle(color = env.c(color), fontSize = size, fontWeight = if (bold) FontWeight.Bold else FontWeight.Normal),
    )
}

@Composable
fun Header(env: WidgetEnv, icon: Int, title: String, trailing: String? = null, trailingColor: Color = env.palette.muted) {
    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        FaIcon(env, icon, env.palette.accent, 13.dp)
        Spacer(GlanceModifier.width(6.dp))
        Label(env, title, 12.sp, env.palette.muted, bold = true, modifier = GlanceModifier.defaultWeight())
        if (trailing != null) Label(env, trailing, 11.sp, trailingColor, bold = true)
    }
}

/** A centered message for states with nothing to show (signed out, no access, no event...). */
@Composable
fun Message(env: WidgetEnv, icon: Int, text: String) {
    Column(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        FaIcon(env, icon, env.palette.muted, 20.dp)
        Spacer(GlanceModifier.size(6.dp))
        Label(env, text, 12.sp, env.palette.muted, maxLines = 3)
    }
}

/**
 * Draws [content] only when the user may have this widget and there is data for it; otherwise the matching
 * message. A widget the user lost access to is normally removed (WidgetAccessGate), but it can still be on screen
 * briefly before the launcher catches up, so it never shows that data.
 */
@Composable
fun Gated(env: WidgetEnv, kind: WidgetKind, needsEvent: Boolean = true, worksWithoutServer: Boolean = false, content: @Composable () -> Unit) {
    val snap = env.snapshot
    when {
        env.authExpired || snap.signedOut || (!snap.present && !env.local.signedIn) -> Message(env, R.drawable.fa_right_to_bracket, env.s(R.string.w_sign_in))
        !snap.present && worksWithoutServer && env.local.widgets[kind.id] == true -> content()
        !snap.present -> Message(env, R.drawable.fa_clock, env.s(R.string.w_loading))
        !snap.allowed(kind.id) -> Message(env, R.drawable.fa_lock, env.s(R.string.w_no_access))
        needsEvent && !snap.hasEvent -> Message(env, R.drawable.fa_calendar_days, env.s(R.string.w_no_event))
        else -> content()
    }
}

/** A countdown to [startEpochSeconds] that the launcher keeps ticking without redrawing the widget. */
@Composable
fun Countdown(env: WidgetEnv, startEpochSeconds: Long, color: Color, sizeSp: Float) {
    val base = SystemClock.elapsedRealtime() + (startEpochSeconds * 1000 - System.currentTimeMillis())
    val views = RemoteViews(env.context.packageName, R.layout.widget_countdown).apply {
        setChronometer(R.id.widget_countdown, base, null, true)
        setChronometerCountDown(R.id.widget_countdown, true)
        setTextColor(R.id.widget_countdown, android.graphics.Color.argb((color.alpha * 255).toInt(), (color.red * 255).toInt(), (color.green * 255).toInt(), (color.blue * 255).toInt()))
        setTextViewTextSize(R.id.widget_countdown, TypedValue.COMPLEX_UNIT_SP, sizeSp)
    }
    AndroidRemoteViews(views)
}

/** "254 · 1678 · 118" with our team marked. */
fun teamsLine(teams: List<String>, ours: Int): String = teams.joinToString(" · ") { if (it == ours.toString()) "[$it]" else it }

@Suppress("unused")
fun widgetIdsOf(context: Context, kind: WidgetKind): IntArray = AppWidgetManager.getInstance(context).getAppWidgetIds(kind.component(context))
