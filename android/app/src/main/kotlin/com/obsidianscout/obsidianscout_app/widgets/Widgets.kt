package com.obsidianscout.obsidianscout_app.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalSize
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import com.obsidianscout.obsidianscout_app.R
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

/** Countdowns switch to the clock time when the match is further away than this. */
private const val COUNTDOWN_MAX_SECONDS = 6 * 60 * 60L

/**
 * The widget's current size (dp), so each layout can adapt: a compact version when small, bigger text and
 * extra detail when there is room, and lists that fill whatever height is left.
 */
class Dims(val width: Float, val height: Float) {
    /** One home-screen row (or close to it): only the essentials, on as few lines as possible. */
    val short get() = height < 100
    val tall get() = height >= 180
    val wide get() = width >= 250

    /** Grows the headline text with the widget (0.85x on the smallest, up to 1.8x on big widgets). */
    fun hero(base: Float): TextUnit = (base * minOf(width / 150f, height / 140f).coerceIn(0.85f, 1.8f)).sp
    fun heroValue(base: Float): Float = base * minOf(width / 150f, height / 140f).coerceIn(0.85f, 1.8f)
}

@Composable
private fun dims(): Dims = LocalSize.current.let { Dims(it.width.value, it.height.value) }

abstract class ObsidianWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    // Redrawn at the exact size it's given, so layouts follow every resize.
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content(rememberWidgetEnv()) }
    }

    @Composable
    abstract fun Content(env: WidgetEnv)
}

/** Starts the background refresh when the first widget is placed and stops it when the last one goes. */
abstract class ObsidianWidgetReceiver<T : GlanceAppWidget> : HomeWidgetGlanceWidgetReceiver<T>() {
    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetScheduler.ensurePeriodic(context)
        WidgetScheduler.refreshSoon(context)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        WidgetScheduler.onWidgetsUpdated(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetScheduler.stopIfUnused(context)
    }
}

/** Time until a match: a live countdown when it's soon, otherwise the clock time; "On the field" once it starts. */
@Composable
private fun StartTime(env: WidgetEnv, start: Long?, sizeSp: Float) {
    val p = env.palette
    when {
        start == null -> Unit
        env.now >= start -> Label(env, env.s(R.string.w_on_field), (sizeSp * 0.65f).sp, p.accent, bold = true)
        start - env.now <= COUNTDOWN_MAX_SECONDS -> Countdown(env, start, p.text, sizeSp)
        else -> Label(env, env.clock(start), (sizeSp * 0.85f).sp, p.text, bold = true)
    }
}

/** "Updated 40 min ago" when the data is old; tapping it forces a fresh fetch; skipped on small widgets. */
@Composable
private fun Footer(env: WidgetEnv, d: Dims) {
    if (d.height < 120) return
    env.updatedAgo()?.let {
        Spacer(GlanceModifier.height(2.dp))
        Label(
            env = env,
            text = "$it ↻",
            size = 10.sp,
            color = env.palette.muted,
            modifier = GlanceModifier.clickable(androidx.glance.appwidget.action.actionRunCallback<RefreshWidgetAction>()),
        )
    }
}

/** A list that fills the rest of the widget and scrolls when there are more rows than fit. */
@Composable
private fun <T> ColumnScope.FillList(rows: List<T>, onClick: Action?, row: @Composable (T) -> Unit) {
    FillList(rows, onClick = { onClick }, row = row)
}

@Composable
private fun <T> ColumnScope.FillList(rows: List<T>, onClick: (T) -> Action?, row: @Composable (T) -> Unit) {
    LazyColumn(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
        items(rows) { item ->
            val itemAction = onClick(item)
            val modifier = if (itemAction != null) GlanceModifier.fillMaxWidth().clickable(itemAction) else GlanceModifier.fillMaxWidth()
            Box(modifier = modifier) { row(item) }
        }
    }
}

private fun allianceColor(env: WidgetEnv, alliance: String?): Color = when (alliance) {
    "red" -> env.palette.red
    "blue" -> env.palette.blue
    else -> env.palette.muted
}

private fun allianceName(env: WidgetEnv, alliance: String?) = when (alliance) {
    "red" -> env.s(R.string.w_red)
    "blue" -> env.s(R.string.w_blue)
    else -> ""
}

// ── Next Match ─────────────────────────────────────────────────────────────────────────────────────────────────

class NextMatchWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        WidgetFrame(env, env.openPage("matches")) {
            Gated(env, WidgetKind.NEXT_MATCH) {
                val d = dims()
                val snap = env.snapshot
                val next = snap.ourUpcoming(env.now).firstOrNull()
                val p = env.palette
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Header(env, R.drawable.fa_flag_checkered, env.s(R.string.widget_next_match_label), env.offset(snap.scheduleOffset), env.offsetColor(snap.scheduleOffset))
                    if (next == null) {
                        Message(env, R.drawable.fa_circle_check, env.s(R.string.w_no_matches))
                        return@Column
                    }
                    val ours = if (next.alliance == "red") next.red else next.blue
                    val theirs = if (next.alliance == "red") next.blue else next.red

                    if (d.short) {
                        // One row: "Qual 22  Red  12:34"
                        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Label(env, env.matchLabel(next), 15.sp, p.text, bold = true)
                            Spacer(GlanceModifier.width(6.dp))
                            Label(env, allianceName(env, next.alliance), 12.sp, allianceColor(env, next.alliance), bold = true, modifier = GlanceModifier.defaultWeight())
                            StartTime(env, next.start, 20f)
                        }
                        return@Column
                    }

                    Spacer(GlanceModifier.height(4.dp))
                    Row(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                        Column(modifier = GlanceModifier.defaultWeight()) {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Label(env, env.matchLabel(next), d.hero(16f), p.text, bold = true)
                                Spacer(GlanceModifier.width(8.dp))
                                Label(env, allianceName(env, next.alliance), 12.sp, allianceColor(env, next.alliance), bold = true)
                            }
                            StartTime(env, next.start, d.heroValue(28f))
                            next.start?.let { Label(env, env.s(R.string.w_at_time, env.clock(it)), 11.sp, p.muted) }
                            // Teams below when the widget is tall but narrow.
                            if (!d.wide && d.height >= 150) {
                                Spacer(GlanceModifier.height(4.dp))
                                Label(env, env.s(R.string.w_with, ours.filter { it != snap.teamNumber.toString() }.joinToString(", ")), 11.sp, allianceColor(env, next.alliance))
                                Label(env, env.s(R.string.w_vs, theirs.joinToString(", ")), 11.sp, p.muted)
                            }
                        }
                        // Teams beside the countdown when it's wide: one per line, both alliances.
                        if (d.wide) {
                            Spacer(GlanceModifier.width(10.dp))
                            Column(modifier = GlanceModifier.width((d.width * 0.38f).dp)) {
                                Label(env, allianceName(env, next.alliance), 11.sp, allianceColor(env, next.alliance), bold = true)
                                ours.forEach { Label(env, it, 12.sp, if (it == snap.teamNumber.toString()) p.text else allianceColor(env, next.alliance), bold = it == snap.teamNumber.toString()) }
                                if (d.height >= 150) {
                                    Spacer(GlanceModifier.height(4.dp))
                                    val other = if (next.alliance == "red") "blue" else "red"
                                    Label(env, allianceName(env, other), 11.sp, allianceColor(env, other), bold = true)
                                    theirs.forEach { Label(env, it, 12.sp, p.muted) }
                                }
                            }
                        }
                    }
                    Footer(env, d)
                }
            }
        }
    }
}

class NextMatchWidgetReceiver : ObsidianWidgetReceiver<NextMatchWidget>() {
    override val glanceAppWidget = NextMatchWidget()
}

// ── Match Schedule ─────────────────────────────────────────────────────────────────────────────────────────────

class ScheduleWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val open = env.openPage("matches")
        WidgetFrame(env, open) {
            Gated(env, WidgetKind.SCHEDULE) {
                val d = dims()
                val snap = env.snapshot
                val p = env.palette
                // The entire schedule: what's coming up first (a widget list can't open scrolled to the middle),
                // then every earlier match, newest first, under "Earlier results".
                val upcoming = snap.eventUpcoming(env.now)
                val played = snap.recentlyPlayed(env.now).reversed()
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Header(env, R.drawable.fa_calendar_days, snap.eventName ?: env.s(R.string.widget_schedule_label), env.offset(snap.scheduleOffset), env.offsetColor(snap.scheduleOffset))
                    Spacer(GlanceModifier.height(4.dp))
                    if (upcoming.isEmpty() && played.isEmpty()) {
                        Message(env, R.drawable.fa_circle_check, env.s(R.string.w_no_schedule))
                        return@Column
                    }
                    val rows: List<WMatch?> = upcoming + (if (played.isNotEmpty()) listOf(null) else emptyList()) + played
                    FillList(rows, onClick = { m ->
                        if (m != null) env.open("obsidianscout://widget/page/matches?matchKey=${android.net.Uri.encode(m.key)}") else open
                    }) { m ->
                        when {
                            // null marks where the earlier matches start.
                            m == null -> Label(env, env.s(R.string.w_earlier), 11.sp, p.muted, bold = true, modifier = GlanceModifier.padding(top = 6.dp, bottom = 2.dp))
                            m in upcoming -> {
                                val time = m.start?.let { if (env.now >= it) env.s(R.string.w_on_field) else env.clock(it) } ?: ""
                                ScheduleRow(env, d, m, time, if (m.alliance != null) p.text else p.muted)
                            }
                            else -> {
                                // A score when it's in, otherwise when it was played.
                                val result = if (m.redScore != null || m.blueScore != null) "${m.redScore ?: "-"} - ${m.blueScore ?: "-"}" else m.start?.let { env.clock(it) } ?: ""
                                ScheduleRow(env, d, m, result, p.muted)
                            }
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun ScheduleRow(env: WidgetEnv, d: Dims, m: WMatch, trailing: String, color: Color) {
        val ours = m.alliance != null
        Row(modifier = GlanceModifier.fillMaxWidth().height(22.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(modifier = GlanceModifier.width(3.dp).height(14.dp).background(env.c(if (ours) allianceColor(env, m.alliance) else Color.Transparent))) {}
            Spacer(GlanceModifier.width(6.dp))
            Label(env, env.matchLabel(m), 12.sp, color, bold = ours, modifier = GlanceModifier.width(if (d.wide) 78.dp else 70.dp))
            // Wide enough: both alliances in the row.
            if (d.width >= 300) {
                Label(env, m.red.joinToString(" "), 11.sp, env.palette.red, modifier = GlanceModifier.defaultWeight())
                Label(env, m.blue.joinToString(" "), 11.sp, env.palette.blue, modifier = GlanceModifier.defaultWeight())
            } else {
                Spacer(GlanceModifier.defaultWeight())
            }
            Label(env, trailing, 12.sp, color, bold = ours)
        }
    }
}

class ScheduleWidgetReceiver : ObsidianWidgetReceiver<ScheduleWidget>() {
    override val glanceAppWidget = ScheduleWidget()
}

// ── Match Predictor ────────────────────────────────────────────────────────────────────────────────────────────

class PredictorWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        WidgetFrame(env, env.openPage("predictor")) {
            Gated(env, WidgetKind.PREDICTOR) {
                val d = dims()
                val p = env.palette
                // Only while that match is still ahead; once it starts the next fetch brings the next prediction.
                // The match that's up now, by the same rule as Next Match.
                val pred = env.snapshot.prediction(env.now)
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    val title = pred?.match?.let { env.matchLabel(it.compLevel, it.set, it.number, it.label) } ?: env.s(R.string.widget_predictor_label)
                    Header(env, R.drawable.fa_chart_line, title, pred?.match?.predicted?.let { env.clock(it) })
                    if (pred == null) {
                        Message(env, R.drawable.fa_chart_line, env.s(R.string.w_no_prediction))
                        return@Column
                    }
                    val win = pred.redWinProb?.let { red ->
                        val ourChance = if (pred.alliance == "blue") 1 - red else red
                        val color = if (pred.alliance == null) p.text else if (ourChance >= 0.5) p.green else p.orange
                        val shown = if (pred.alliance == null) maxOf(red, 1 - red) else ourChance
                        env.s(R.string.w_win, Math.round(shown * 100).toInt()) to color
                    }
                    if (d.short) {
                        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Label(env, Math.round(pred.red).toString(), 20.sp, p.red, bold = true)
                            Label(env, "  -  ", 14.sp, p.muted)
                            Label(env, Math.round(pred.blue).toString(), 20.sp, p.blue, bold = true, modifier = GlanceModifier.defaultWeight())
                            win?.let { (text, color) -> Label(env, text, 12.sp, color, bold = true) }
                        }
                        return@Column
                    }
                    Spacer(GlanceModifier.height(4.dp))
                    // Teams under each alliance's score when there's room.
                    val showTeams = d.height >= 150
                    Row(modifier = GlanceModifier.fillMaxWidth()) {
                        listOf(Triple("red", pred.red, p.red), Triple("blue", pred.blue, p.blue)).forEach { (side, score, color) ->
                            Column(modifier = GlanceModifier.defaultWeight(), horizontalAlignment = Alignment.CenterHorizontally) {
                                Label(env, Math.round(score).toString(), d.hero(26f), color, bold = true)
                                Label(env, allianceName(env, side) + if (pred.alliance == side) " *" else "", 11.sp, color)
                                if (showTeams) {
                                    pred.teams.filter { it.alliance == side }.forEach { t ->
                                        val mine = t.team == env.snapshot.teamNumber.toString()
                                        Label(env, t.team + (t.points?.let { "  ${Math.round(it)}" } ?: ""), 11.sp, if (mine) p.text else p.muted, bold = mine)
                                    }
                                }
                            }
                        }
                    }
                    win?.let { (text, color) ->
                        Spacer(GlanceModifier.height(4.dp))
                        Row(modifier = GlanceModifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                            Label(env, text, 13.sp, color, bold = true)
                        }
                    }
                    Footer(env, d)
                }
            }
        }
    }
}

class PredictorWidgetReceiver : ObsidianWidgetReceiver<PredictorWidget>() {
    override val glanceAppWidget = PredictorWidget()
}

// ── My Assignments ─────────────────────────────────────────────────────────────────────────────────────────────

class AssignmentsWidget : ObsidianWidget() {
    private fun describe(env: WidgetEnv, a: WAssignment): String = buildList {
        if (a.type != "PIT") env.matchLabel(a.compLevel, null, a.number).takeIf { it.isNotEmpty() }?.let(::add)
        a.team?.let { add(env.s(R.string.w_team, it)) }
        a.alliance?.takeIf { it.isNotEmpty() }?.let { add(allianceName(env, it.lowercase()).ifEmpty { it }) }
    }.joinToString(" · ")

    private fun link(a: WAssignment): String {
        val params = buildList {
            add("type=${a.type}")
            add("id=${android.net.Uri.encode(a.id)}")
            a.matchKey?.let { add("matchKey=${android.net.Uri.encode(it)}") }
            a.number?.let { add("number=$it") }
            a.team?.let { add("team=$it") }
            a.alliance?.let { add("alliance=${android.net.Uri.encode(it)}") }
        }
        return "obsidianscout://widget/scout?" + params.joinToString("&")
    }

    @Composable
    override fun Content(env: WidgetEnv) {
        val next = env.snapshot.assignmentsUpcoming(env.now)
        val first = next.firstOrNull()
        WidgetFrame(env, if (first != null) env.open(link(first)) else env.openPage("my-assignments")) {
            Gated(env, WidgetKind.ASSIGNMENTS) {
                val d = dims()
                val snap = env.snapshot
                val p = env.palette
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Header(env, R.drawable.fa_clipboard_list, env.s(R.string.widget_assignments_label), env.s(R.string.w_left, snap.assignmentsRemaining))
                    if (first == null) {
                        Spacer(GlanceModifier.height(4.dp))
                        Label(env, env.s(R.string.w_no_assignments), 14.sp, p.text, bold = true, maxLines = 2)
                        if (snap.pitOpen > 0) Label(env, env.s(R.string.w_pit_left, snap.pitOpen), 12.sp, p.muted)
                    } else if (d.short) {
                        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Label(env, describe(env, first), 13.sp, p.text, bold = true, modifier = GlanceModifier.defaultWeight())
                            StartTime(env, first.predicted, 16f)
                        }
                    } else {
                        Spacer(GlanceModifier.height(4.dp))
                        Label(env, describe(env, first), d.hero(15f), p.text, bold = true, maxLines = 2)
                        StartTime(env, first.predicted, d.heroValue(18f))
                        val rest = next.drop(1)
                        if (rest.isNotEmpty()) {
                            Spacer(GlanceModifier.height(4.dp))
                            if (d.tall) {
                                // Taller: the rest of the queue with times, scrolling; each row opens that assignment.
                                Label(env, env.s(R.string.w_up_next, ""), 11.sp, p.muted, bold = true)
                                FillList(rest, onClick = { a -> env.open(link(a)) }) { a ->
                                    Row(modifier = GlanceModifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Label(env, describe(env, a), 12.sp, p.text, modifier = GlanceModifier.defaultWeight())
                                        a.predicted?.let { Label(env, env.clock(it), 12.sp, p.muted) }
                                    }
                                }
                            } else {
                                Label(env, env.s(R.string.w_up_next, describe(env, rest.first())), 11.sp, p.muted, maxLines = 2)
                            }
                        }
                    }
                    if (env.local.pendingUploads > 0 && !d.short) {
                        Spacer(GlanceModifier.height(4.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            FaIcon(env, R.drawable.fa_cloud_arrow_up, p.orange, 12.dp)
                            Spacer(GlanceModifier.width(4.dp))
                            Label(env, env.s(R.string.w_pending, env.local.pendingUploads), 11.sp, p.orange)
                        }
                    }
                    Footer(env, d)
                }
            }
        }
    }
}

class AssignmentsWidgetReceiver : ObsidianWidgetReceiver<AssignmentsWidget>() {
    override val glanceAppWidget = AssignmentsWidget()
}

// ── Battery ────────────────────────────────────────────────────────────────────────────────────────────────────

class BatteryWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val open = env.openPage("battery-tracker")
        WidgetFrame(env, open) {
            Gated(env, WidgetKind.BATTERY) {
                val d = dims()
                val snap = env.snapshot
                val p = env.palette
                val slots = snap.batterySlots
                val current = snap.pickCurrent(slots, env.now) { it.match }
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Header(env, R.drawable.fa_battery_full, env.s(R.string.widget_battery_label))
                    when {
                        snap.batteryCount == 0 -> Message(env, R.drawable.fa_battery_empty, env.s(R.string.w_no_batteries))
                        current == null -> Message(env, R.drawable.fa_circle_check, env.s(R.string.w_no_matches))
                        d.short -> Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Label(env, env.matchLabel(current.match.compLevel, current.match.set, current.match.number, current.match.label), 12.sp, p.muted, modifier = GlanceModifier.defaultWeight())
                            Label(env, current.battery ?: env.s(R.string.w_none_available), 18.sp, if (current.battery == null) p.red else p.text, bold = true)
                        }
                        else -> {
                            val m = current.match
                            Spacer(GlanceModifier.height(4.dp))
                            Label(env, env.s(R.string.w_battery_for, env.matchLabel(m.compLevel, m.set, m.number, m.label)), 11.sp, p.muted)
                            if (current.battery == null) {
                                Label(env, env.s(R.string.w_none_available), 14.sp, p.red, bold = true, maxLines = 2)
                            } else {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    FaIcon(env, R.drawable.fa_battery_full, p.green, d.heroValue(18f).dp)
                                    Spacer(GlanceModifier.width(6.dp))
                                    Label(env, current.battery, d.hero(24f), p.text, bold = true)
                                }
                            }
                            m.predicted?.let { Label(env, env.s(R.string.w_at_time, env.clock(it)), 11.sp, p.muted) }
                            if (current.skipped.isNotEmpty()) Label(env, env.s(R.string.w_skipped, current.skipped.joinToString(", ")), 11.sp, p.orange, maxLines = 2)
                            val later = slots.drop(slots.indexOf(current) + 1)
                            if (d.tall && later.isNotEmpty()) {
                                // Taller: the rotation for our next matches.
                                Spacer(GlanceModifier.height(4.dp))
                                FillList(later, open) { s ->
                                    Row(modifier = GlanceModifier.fillMaxWidth().height(20.dp), verticalAlignment = Alignment.CenterVertically) {
                                        Label(env, env.matchLabel(s.match.compLevel, s.match.set, s.match.number, s.match.label), 12.sp, p.muted, modifier = GlanceModifier.defaultWeight())
                                        Label(env, s.battery ?: "-", 12.sp, if (s.battery == null) p.red else p.text, bold = true)
                                    }
                                }
                            } else {
                                later.firstOrNull()?.battery?.let { Label(env, env.s(R.string.w_then, it), 11.sp, p.muted) }
                            }
                        }
                    }
                    Footer(env, d)
                }
            }
        }
    }
}

class BatteryWidgetReceiver : ObsidianWidgetReceiver<BatteryWidget>() {
    override val glanceAppWidget = BatteryWidget()
}

// ── Match Checklist ────────────────────────────────────────────────────────────────────────────────────────────

class ChecklistWidget : ObsidianWidget() {
    /** Rows of the big checklist: a list's title, or one of its items. */
    private sealed interface ChecklistRow {
        data class Title(val list: WChecklistList) : ChecklistRow
        data class Item(val list: WChecklistList, val item: WChecklistItem) : ChecklistRow
    }

    private fun title(env: WidgetEnv, l: WChecklistList): String = when {
        l.title.isNotBlank() -> l.title
        l.id == "pre" -> env.s(R.string.w_list_pre)
        l.id == "field" -> env.s(R.string.w_list_field)
        else -> env.s(R.string.w_list_untitled)
    }

    private fun scopeNote(env: WidgetEnv, l: WChecklistList): String? = when (l.frequency) {
        "daily" -> env.s(R.string.w_today)
        "event" -> env.s(R.string.w_this_event)
        "every_n" -> if (l.due) env.s(R.string.w_every_n, l.every) else env.s(R.string.w_not_due)
        else -> null
    }

    @Composable
    override fun Content(env: WidgetEnv) {
        val open = env.openPage("match-checklist")
        WidgetFrame(env, open) {
            Gated(env, WidgetKind.CHECKLIST) {
                val d = dims()
                val snap = env.snapshot
                val p = env.palette
                // The match that's up now, by the same rule as Next Match: it moves on when the match is played
                // or starts, whether or not its checklist was finished.
                val (match, lists) = snap.checklistNow(env.now)
                // Progress over everything that's due: this match's lists plus today's and the event's.
                val due = lists.filter { it.due }
                val done = due.sumOf { it.done }
                val total = due.sumOf { it.items.size }
                val complete = total > 0 && done >= total
                val label = match?.let { env.matchLabel(it.compLevel, it.set, it.number, it.label) } ?: env.s(R.string.widget_checklist_label)

                Column(modifier = GlanceModifier.fillMaxSize()) {
                    // Tapping the header/frame opens the app's checklist; tapping an item row checks it off directly.
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        FaIcon(env, R.drawable.fa_list_check, p.accent, 13.dp)
                        Spacer(GlanceModifier.width(6.dp))
                        Label(env, if (d.short) label else env.s(R.string.widget_checklist_label), 12.sp, p.muted, bold = true, modifier = GlanceModifier.defaultWeight())
                        if (total > 0) Label(env, "$done/$total", 12.sp, if (complete) p.green else p.text, bold = true)
                    }
                    if (lists.isEmpty()) {
                        Message(env, R.drawable.fa_list_check, env.s(R.string.w_no_items))
                        return@Column
                    }
                    if (d.short) {
                        Spacer(GlanceModifier.height(4.dp))
                        LinearProgressIndicator(
                            progress = if (total == 0) 0f else done.toFloat() / total,
                            modifier = GlanceModifier.fillMaxWidth().height(6.dp).cornerRadius(3.dp),
                            color = env.c(if (complete) p.green else p.accent),
                            backgroundColor = env.c(p.surface),
                        )
                        return@Column
                    }

                    // The upcoming match, always shown.
                    Spacer(GlanceModifier.height(4.dp))
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Label(env, label, d.hero(15f), p.text, bold = true, modifier = GlanceModifier.defaultWeight())
                        StartTime(env, match?.predicted, 16f)
                    }
                    Spacer(GlanceModifier.height(4.dp))
                    LinearProgressIndicator(
                        progress = if (total == 0) 0f else done.toFloat() / total,
                        modifier = GlanceModifier.fillMaxWidth().height(6.dp).cornerRadius(3.dp),
                        color = env.c(if (complete) p.green else p.accent),
                        backgroundColor = env.c(p.surface),
                    )

                    val big = d.height >= 190 && d.width >= 170
                    if (!big) {
                        Spacer(GlanceModifier.height(4.dp))
                        Label(env, env.s(R.string.w_done_of, done, total), 12.sp, if (complete) p.green else p.muted, bold = complete)
                        Footer(env, d)
                        return@Column
                    }

                    // Big: every list with its items and what's checked. Lists not due this match stay collapsed.
                    Spacer(GlanceModifier.height(4.dp))
                    val rows = lists.flatMap { l ->
                        listOf<ChecklistRow>(ChecklistRow.Title(l)) + if (l.due) l.items.map { ChecklistRow.Item(l, it) } else emptyList()
                    }
                    LazyColumn(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                        items(rows) { row ->
                            when (row) {
                                is ChecklistRow.Title -> ListTitle(env, row.list)
                                is ChecklistRow.Item -> ItemRow(env, snap.checklistEventKey, row.list.record, row.item)
                            }
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun ListTitle(env: WidgetEnv, l: WChecklistList) {
        val p = env.palette
        val allDone = l.items.isNotEmpty() && l.done == l.items.size
        Row(modifier = GlanceModifier.fillMaxWidth().padding(top = 6.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Label(env, title(env, l), 12.sp, if (l.due) p.text else p.muted, bold = true, modifier = GlanceModifier.defaultWeight())
            scopeNote(env, l)?.let {
                Label(env, it, 10.sp, p.muted)
                Spacer(GlanceModifier.width(6.dp))
            }
            if (l.due) Label(env, "${l.done}/${l.items.size}", 11.sp, if (allDone) p.green else p.muted, bold = true)
        }
    }

    /** Tapping an item row checks or unchecks it directly on the home screen and syncs in the background. */
    @Composable
    private fun ItemRow(env: WidgetEnv, eventKey: String, record: String, item: WChecklistItem) {
        val p = env.palette
        val priorityColor = when (item.priority) {
            "critical" -> p.red
            "high" -> p.orange
            else -> Color.Transparent
        }
        val base = GlanceModifier.fillMaxWidth().padding(vertical = 2.dp)
        val rowModifier = if (eventKey.isNotEmpty() && record.isNotEmpty() && item.id.isNotEmpty()) {
            base.clickable(
                androidx.glance.appwidget.action.actionRunCallback<ToggleChecklistItemAction>(
                    androidx.glance.action.actionParametersOf(
                        ToggleChecklistItemAction.KEY_EVENT_KEY to eventKey,
                        ToggleChecklistItemAction.KEY_RECORD to record,
                        ToggleChecklistItemAction.KEY_ITEM_ID to item.id,
                        ToggleChecklistItemAction.KEY_CHECKED to !item.checked,
                    )
                )
            )
        } else {
            base
        }
        Row(modifier = rowModifier, verticalAlignment = Alignment.CenterVertically) {
            // Critical and high-priority items get a colored edge, like on the checklist page.
            Box(modifier = GlanceModifier.width(3.dp).height(16.dp).background(env.c(priorityColor))) {}
            Spacer(GlanceModifier.width(6.dp))
            FaIcon(env, if (item.checked) R.drawable.fa_circle_check else R.drawable.fa_circle, if (item.checked) p.green else p.muted, 14.dp)
            Spacer(GlanceModifier.width(8.dp))
            Label(env, item.text, 13.sp, if (item.checked) p.muted else p.text, maxLines = 2, modifier = GlanceModifier.defaultWeight())
        }
    }
}

class ChecklistWidgetReceiver : ObsidianWidgetReceiver<ChecklistWidget>() {
    override val glanceAppWidget = ChecklistWidget()
}

// ── Rankings ───────────────────────────────────────────────────────────────────────────────────────────────────

class RankingsWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val targetPage = when {
            env.snapshot.page("rankings") -> "rankings"
            env.snapshot.page("event-predictor") -> "event-predictor"
            else -> "dashboard"
        }
        val target = env.openPage(targetPage)
        WidgetFrame(env, target) {
            Gated(env, WidgetKind.RANKINGS) {
                val d = dims()
                val r = env.snapshot.rankings
                val p = env.palette
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Header(env, R.drawable.fa_trophy, env.s(R.string.widget_rankings_label), if (r?.qualsComplete == true) env.s(R.string.w_final_rankings) else null)
                    val ours = r?.ours
                    if (r == null || (ours?.rank == null && ours?.projectedRank == null)) {
                        Message(env, R.drawable.fa_trophy, env.s(if (r == null) R.string.w_no_rankings else R.string.w_rankings_pending))
                        return@Column
                    }
                    val projected = ours?.projectedRank?.takeIf { !r.qualsComplete }?.let { env.s(R.string.w_projected, it) }
                    // Our standing: one compact line when the widget is short or will mostly be a list, a big number otherwise.
                    val compactHero = d.short || d.height < 160
                    if (compactHero) {
                        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Label(env, ours?.rank?.let { "#$it" } ?: "-", 18.sp, p.text, bold = true)
                            Spacer(GlanceModifier.width(6.dp))
                            ours?.let { Label(env, "${it.wins}-${it.losses}-${it.ties}", 12.sp, p.muted) }
                            Spacer(GlanceModifier.defaultWeight())
                            projected?.let { Label(env, it, 11.sp, p.accent, bold = true) }
                        }
                    } else {
                        Spacer(GlanceModifier.height(2.dp))
                        Row(verticalAlignment = Alignment.Bottom) {
                            Label(env, ours?.rank?.let { "#$it" } ?: "-", d.hero(28f), p.text, bold = true)
                            Spacer(GlanceModifier.width(8.dp))
                            ours?.let { Label(env, "${it.wins}-${it.losses}-${it.ties}", 13.sp, p.muted) }
                        }
                        projected?.let { Label(env, it, 12.sp, p.accent, bold = true) }
                        r.probTopSeeds?.takeIf { !r.qualsComplete }?.let { Label(env, env.s(R.string.w_top_seed, Math.round(it * 100).toInt()), 11.sp, p.muted) }
                    }
                    if (d.height >= 120 && r.top.isNotEmpty()) {
                        // Every team: the list fills the rest of the widget, so a longer widget shows more teams,
                        // and scrolls for the rest.
                        Spacer(GlanceModifier.height(4.dp))
                        if (d.wide) RankHeader(env)
                        FillList(r.top, onClick = { row -> env.open("obsidianscout://widget/page/$targetPage?team=${row.team}") }) { row ->
                            RankRow(env, d, row, row.team == env.snapshot.teamNumber)
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun RankHeader(env: WidgetEnv) {
        val p = env.palette
        Row(modifier = GlanceModifier.fillMaxWidth().height(16.dp), verticalAlignment = Alignment.CenterVertically) {
            Label(env, "#", 10.sp, p.muted, modifier = GlanceModifier.width(26.dp))
            Label(env, env.s(R.string.w_col_team), 10.sp, p.muted, modifier = GlanceModifier.defaultWeight())
            Label(env, "W-L-T", 10.sp, p.muted, modifier = GlanceModifier.width(52.dp))
            Label(env, "RP", 10.sp, p.muted, modifier = GlanceModifier.width(40.dp))
        }
    }

    @Composable
    private fun RankRow(env: WidgetEnv, d: Dims, row: WRankRow, mine: Boolean) {
        val p = env.palette
        val base = if (mine) GlanceModifier.fillMaxWidth().height(20.dp).background(env.c(p.surface)).cornerRadius(6.dp) else GlanceModifier.fillMaxWidth().height(20.dp)
        Row(modifier = base, verticalAlignment = Alignment.CenterVertically) {
            Label(env, row.rank?.toString() ?: row.projectedRank?.let { "~$it" } ?: "-", 12.sp, p.muted, modifier = GlanceModifier.width(26.dp))
            Label(env, row.team.toString(), 12.sp, if (mine) p.accent else p.text, bold = mine, modifier = GlanceModifier.defaultWeight())
            if (d.wide) Label(env, "${row.wins}-${row.losses}-${row.ties}", 12.sp, p.muted, modifier = GlanceModifier.width(52.dp))
            Label(env, String.format(java.util.Locale.US, "%.2f", row.rp), 12.sp, p.muted, modifier = GlanceModifier.width(40.dp))
        }
    }
}

class RankingsWidgetReceiver : ObsidianWidgetReceiver<RankingsWidget>() {
    override val glanceAppWidget = RankingsWidget()
}

// ── Team Chat ──────────────────────────────────────────────────────────────────────────────────────────────────

class ChatWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        val open = env.openPage("chat")
        WidgetFrame(env, open) {
            Gated(env, WidgetKind.CHAT, needsEvent = false) {
                val d = dims()
                val chat = env.snapshot.chat
                val p = env.palette
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    Header(env, R.drawable.fa_comments, env.s(R.string.widget_chat_label), chat?.mentions?.takeIf { it > 0 }?.let { "@ $it" }, p.orange)
                    if (chat == null || chat.unread == 0) {
                        Label(env, env.s(R.string.w_no_unread), 13.sp, p.muted)
                        return@Column
                    }
                    Label(env, env.s(R.string.w_unread, chat.unread), if (d.short) 15.sp else d.hero(18f), p.text, bold = true)
                    if (!d.short) {
                        FillList(chat.groups, onClick = { g ->
                            env.open("obsidianscout://widget/page/chat?group=${android.net.Uri.encode(g.group)}")
                        }) { g ->
                            Row(modifier = GlanceModifier.fillMaxWidth().height(18.dp), verticalAlignment = Alignment.CenterVertically) {
                                Label(env, "# ${g.group}", 12.sp, p.muted, modifier = GlanceModifier.defaultWeight())
                                Label(env, g.unread.toString(), 12.sp, if (g.mentions > 0) p.orange else p.text, bold = true)
                            }
                        }
                    }
                }
            }
        }
    }
}

class ChatWidgetReceiver : ObsidianWidgetReceiver<ChatWidget>() {
    override val glanceAppWidget = ChatWidget()
}

// ── Quick Actions ──────────────────────────────────────────────────────────────────────────────────────────────

class QuickActionsWidget : ObsidianWidget() {
    @Composable
    override fun Content(env: WidgetEnv) {
        WidgetFrame(env, null) {
            Gated(env, WidgetKind.QUICK_ACTIONS, needsEvent = false, worksWithoutServer = true) {
                val d = dims()
                // Only buttons for pages this user can open.
                val actions = listOfNotNull(
                    Triple(R.drawable.fa_clipboard_list, R.string.w_match_scout, env.openPage("scout")).takeIf { env.page("scout") },
                    Triple(R.drawable.fa_screwdriver_wrench, R.string.w_pit_scout, env.openPage("pit-scout")).takeIf { env.page("pit-scout") },
                    Triple(R.drawable.fa_comment_dots, R.string.w_qual_scout, env.openPage("qual-scout")).takeIf { env.page("qual-scout") },
                    Triple(R.drawable.fa_qrcode, R.string.w_scan, env.open("obsidianscout://widget/scan")).takeIf { env.page("qr-scanner") },
                )
                // Narrow and tall: a 2x2 grid. Otherwise a single row.
                val columns = if (d.width < 200 && d.height >= 140 && actions.size > 2) 2 else actions.size.coerceAtLeast(1)
                val showLabels = d.height >= 70
                Column(modifier = GlanceModifier.fillMaxSize()) {
                    actions.chunked(columns).forEachIndexed { r, rowActions ->
                        if (r > 0) Spacer(GlanceModifier.height(6.dp))
                        Row(modifier = GlanceModifier.fillMaxWidth().defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                            rowActions.forEachIndexed { i, (icon, label, action) ->
                                if (i > 0) Spacer(GlanceModifier.width(6.dp))
                                ActionButton(env, icon, if (showLabels) env.s(label) else null, action, d, GlanceModifier.defaultWeight())
                            }
                            // Keep buttons the same width when the last row is short.
                            repeat(columns - rowActions.size) {
                                Spacer(GlanceModifier.width(6.dp))
                                Spacer(GlanceModifier.defaultWeight())
                            }
                        }
                    }
                }
            }
        }
    }

    @Composable
    private fun ActionButton(env: WidgetEnv, icon: Int, label: String?, action: Action, d: Dims, modifier: GlanceModifier) {
        Column(
            modifier = modifier.fillMaxHeight().background(env.c(env.palette.surface)).cornerRadius(14.dp).padding(4.dp).clickable(action),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            FaIcon(env, icon, env.palette.accent, (if (d.height >= 140) 24 else 18).dp)
            if (label != null) {
                Spacer(GlanceModifier.height(3.dp))
                Label(env, label, 11.sp, env.palette.text, bold = true)
            }
        }
    }
}

class QuickActionsWidgetReceiver : ObsidianWidgetReceiver<QuickActionsWidget>() {
    override val glanceAppWidget = QuickActionsWidget()
}
