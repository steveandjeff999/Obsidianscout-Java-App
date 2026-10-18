package com.obsidianscout.obsidianscout_app.widgets

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Storage shared with the Flutter side (home_widget's "HomeWidgetPreferences"): the snapshot the server builds
 * for the widgets, the app's local state, and the read-only widget token used to refresh while the app is closed.
 * Keys match lib/services/home_widget_service.dart.
 */
object WidgetPrefs {
    private const val FILE = "HomeWidgetPreferences"
    const val SNAPSHOT = "snapshot_v1"
    const val LOCAL = "local_v1"
    const val TOKEN = "widget_token"
    const val SERVER_URL = "widget_server_url"
    const val REFRESH_REQUESTED = "widget_refresh_requested"
    const val ETAG = "widget_snapshot_etag"
    const val FETCHED_AT = "widget_snapshot_fetched_at"
    const val AUTH_EXPIRED = "widget_auth_expired"

    fun of(context: Context): SharedPreferences = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun snapshot(context: Context) = Snapshot.parse(of(context).getString(SNAPSHOT, null))

    fun local(context: Context) = LocalState.parse(of(context).getString(LOCAL, null))

    fun authExpired(context: Context) = of(context).getBoolean(AUTH_EXPIRED, false)

    /** home_widget stores Dart ints as Longs; tolerate either. */
    fun long(prefs: SharedPreferences, key: String): Long = when (val v = prefs.all[key]) {
        is Long -> v
        is Int -> v.toLong()
        is String -> v.toLongOrNull() ?: 0L
        else -> 0L
    }
}

/** What the app writes about the device itself: pending uploads, language and theme. */
data class LocalState(
    val signedIn: Boolean,
    val pendingUploads: Int,
    val locale: String?,
    val theme: String,
    /** Access the app worked out itself; used until a server snapshot arrives. */
    val widgets: Map<String, Boolean>,
    val pages: Map<String, Boolean>,
) {
    companion object {
        private fun bools(o: JSONObject?): Map<String, Boolean> =
            o?.keys()?.asSequence()?.associateWith { o.optBoolean(it, false) } ?: emptyMap()

        fun parse(raw: String?): LocalState {
            val o = raw?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
            return LocalState(
                signedIn = o.optBoolean("signedIn", false),
                pendingUploads = o.optInt("pendingUploads", 0),
                locale = o.optString("locale").takeIf { it.isNotEmpty() },
                theme = o.optString("theme", "dark"),
                widgets = bools(o.optJSONObject("widgets")),
                pages = bools(o.optJSONObject("pages")),
            )
        }
    }
}

data class WMatch(
    val key: String,
    val compLevel: String,
    val set: Int?,
    val number: Int?,
    val label: String,
    val scheduled: Long?,
    val predicted: Long?,
    val red: List<String>,
    val blue: List<String>,
    val redScore: Int?,
    val blueScore: Int?,
    val played: Boolean,
    val alliance: String?,
) {
    /** Expected start in epoch seconds: the server's predicted time, which accounts for the event running ahead/behind. */
    val start: Long? get() = predicted ?: scheduled
}

data class WPredictionTeam(val team: String, val alliance: String, val points: Double?)
data class WPrediction(val matchKey: String, val label: String, val match: WMatchRef?, val alliance: String?, val red: Double, val blue: Double, val redWinProb: Double?, val teams: List<WPredictionTeam>)
data class WAssignment(val id: String, val type: String, val matchKey: String?, val compLevel: String?, val number: Int?, val team: Int?, val alliance: String?, val predicted: Long?)
/** A match's label and predicted start (epoch seconds), carried by sections that don't get the full schedule. */
data class WMatchRef(val key: String, val compLevel: String, val set: Int?, val number: Int?, val label: String, val predicted: Long?)
data class WBatterySlot(val match: WMatchRef, val battery: String?, val source: String, val skipped: List<String>)
data class WChecklistMatch(val matchKey: String, val done: Int, val total: Int, val match: WMatchRef?)
data class WChecklistItem(val id: String, val text: String, val priority: String, val checked: Boolean, val by: String?)
/** One of the team's checklists, filled out in [record] (a match key, "day_YYYY-MM-DD" or "event"). */
data class WChecklistList(val id: String, val title: String, val frequency: String, val every: Int, val record: String, val due: Boolean, val items: List<WChecklistItem>) {
    val done get() = items.count { it.checked }
}
data class WRankRow(val team: Int, val rank: Int?, val projectedRank: Int?, val wins: Int, val losses: Int, val ties: Int, val rp: Double)
data class WRankings(val ours: WRankRow?, val probTopSeeds: Double?, val top: List<WRankRow>, val qualsComplete: Boolean)
data class WChatGroup(val group: String, val unread: Int, val mentions: Int)
data class WChat(val unread: Int, val mentions: Int, val groups: List<WChatGroup>)

/**
 * The server's widget snapshot (GET /api/widgets/snapshot). Sections the user may not see are absent.
 * Times are UTC epoch seconds. Widgets pick "what's next" against the clock, so they stay right between fetches.
 */
class Snapshot private constructor(private val o: JSONObject?) {
    val present get() = o != null && !o.optBoolean("signedOut", false)
    val signedOut get() = o?.optBoolean("signedOut", false) == true
    val generatedAt: Long get() = o?.optLong("generatedAt", 0L) ?: 0L
    val teamNumber: Int get() = o?.optInt("teamNumber", 0) ?: 0
    val eventName: String? get() = o?.optJSONObject("event")?.optString("name")?.takeIf { it.isNotEmpty() }
    val hasEvent get() = o?.optJSONObject("event") != null

    fun allowed(kind: String) = o?.optJSONObject("widgets")?.optBoolean(kind, false) == true
    fun page(id: String) = o?.optJSONObject("pages")?.optBoolean(id, false) == true

    val scheduleOffset: Long get() = o?.optJSONObject("schedule")?.optLong("offsetSeconds", 0L) ?: 0L
    val hasSchedule get() = o?.optJSONObject("schedule") != null

    val matches: List<WMatch> by lazy {
        val arr = o?.optJSONObject("schedule")?.optJSONArray("matches") ?: return@lazy emptyList()
        arr.objects().map {
            WMatch(
                key = it.optString("key"),
                compLevel = it.optString("compLevel"),
                set = it.optIntOrNull("set"),
                number = it.optIntOrNull("number"),
                label = it.optString("label"),
                scheduled = it.optLongOrNull("scheduled"),
                predicted = it.optLongOrNull("predicted"),
                red = it.optJSONArray("red").strings(),
                blue = it.optJSONArray("blue").strings(),
                redScore = it.optIntOrNull("redScore"),
                blueScore = it.optIntOrNull("blueScore"),
                played = it.optBoolean("played", false),
                alliance = it.optString("alliance").takeIf { a -> a == "red" || a == "blue" },
            )
        }
    }

    /** A match counts as "now" from its predicted start until [ON_FIELD_SECONDS] later, then the next one is up. */
    private fun stillAhead(m: WMatch, now: Long) = !m.played && (m.start?.let { it + ON_FIELD_SECONDS > now } ?: true)

    fun ourUpcoming(now: Long): List<WMatch> = matches.filter { it.alliance != null && stillAhead(it, now) }
    fun eventUpcoming(now: Long): List<WMatch> = matches.filter { stillAhead(it, now) }
    fun recentlyPlayed(now: Long): List<WMatch> = matches.filter { !stillAhead(it, now) }

    val prediction: WPrediction? by lazy {
        val p = o?.optJSONObject("prediction") ?: return@lazy null
        WPrediction(
            matchKey = p.optString("matchKey"),
            label = p.optString("label"),
            match = p.optJSONObject("match")?.let(::matchRef),
            alliance = p.optString("alliance").takeIf { it.isNotEmpty() && it != "null" },
            red = p.optDouble("red", 0.0),
            blue = p.optDouble("blue", 0.0),
            redWinProb = if (p.isNull("redWinProb")) null else p.optDouble("redWinProb"),
            teams = p.optJSONArray("teams").objects().map { WPredictionTeam(it.optString("team"), it.optString("alliance"), if (it.isNull("points")) null else it.optDouble("points")) },
        )
    }

    val hasAssignments get() = o?.optJSONObject("assignments") != null
    val assignmentsRemaining: Int get() = o?.optJSONObject("assignments")?.optInt("remaining", 0) ?: 0
    val pitOpen: Int get() = o?.optJSONObject("assignments")?.optInt("pitOpen", 0) ?: 0

    private val assignmentList: List<WAssignment> by lazy {
        val arr = o?.optJSONObject("assignments")?.optJSONArray("upcoming") ?: return@lazy emptyList()
        arr.objects().map {
            WAssignment(
                id = it.optString("id"),
                type = it.optString("type", "MATCH"),
                matchKey = it.optString("matchKey").takeIf { k -> k.isNotEmpty() && k != "null" },
                compLevel = it.optString("compLevel").takeIf { k -> k.isNotEmpty() && k != "null" },
                number = it.optIntOrNull("number"),
                team = it.optIntOrNull("team"),
                alliance = it.optString("alliance").takeIf { k -> k.isNotEmpty() && k != "null" },
                predicted = it.optLongOrNull("predicted"),
            )
        }
    }

    /** Open match assignments whose match hasn't been over for [ASSIGNMENT_GRACE_SECONDS] (same grace as the app). */
    fun assignmentsUpcoming(now: Long): List<WAssignment> {
        val ahead = assignmentList.filter { a -> a.predicted?.let { it + ASSIGNMENT_GRACE_SECONDS >= now } ?: true }
        return ahead.ifEmpty { assignmentList }
    }

    val hasBattery get() = o?.optJSONObject("battery") != null
    val batteryCount: Int get() = o?.optJSONObject("battery")?.optInt("batteryCount", 0) ?: 0
    val batterySlots: List<WBatterySlot> by lazy {
        o?.optJSONObject("battery")?.optJSONArray("slots").objects().map {
            WBatterySlot(matchRef(it.optJSONObject("match") ?: JSONObject()), it.optString("battery").takeIf { b -> b.isNotEmpty() && b != "null" }, it.optString("source"), it.optJSONArray("skipped").strings())
        }
    }

    val hasChecklist get() = o?.optJSONObject("checklist") != null
    val checklistEventKey: String get() = o?.optJSONObject("checklist")?.optString("eventKey").orEmpty()

    /** Our upcoming match; the Checklist widget always shows its lists. */
    val checklistMatch: WMatchRef? by lazy { o?.optJSONObject("checklist")?.optJSONObject("match")?.let(::matchRef) }

    /** Every checklist with its items for [checklistMatch], plus today's and the event's lists. */
    val checklistLists: List<WChecklistList> by lazy {
        o?.optJSONObject("checklist")?.optJSONArray("lists").objects().map { l ->
            WChecklistList(
                id = l.optString("id"),
                title = l.optString("title"),
                frequency = l.optString("frequency", "match"),
                every = l.optInt("every", 2),
                record = l.optString("record"),
                due = l.optBoolean("due", true),
                items = l.optJSONArray("items").objects().map {
                    WChecklistItem(it.optString("id"), it.optString("text"), it.optString("priority", "normal"), it.optBoolean("checked", false), it.optString("by").takeIf { b -> b.isNotEmpty() && b != "null" })
                },
            )
        }
    }
    val checklistMatches: List<WChecklistMatch> by lazy {
        o?.optJSONObject("checklist")?.optJSONArray("matches").objects().map { WChecklistMatch(it.optString("matchKey"), it.optInt("done"), it.optInt("total"), it.optJSONObject("match")?.let(::matchRef)) }
    }

    val rankings: WRankings? by lazy {
        val r = o?.optJSONObject("rankings") ?: return@lazy null
        fun row(j: JSONObject) = WRankRow(j.optInt("team"), j.optIntOrNull("rank"), j.optIntOrNull("projectedRank"), j.optInt("wins"), j.optInt("losses"), j.optInt("ties"), j.optDouble("rp", 0.0))
        WRankings(
            ours = r.optJSONObject("ours")?.let(::row),
            probTopSeeds = if (r.isNull("probTopSeeds")) null else r.optDouble("probTopSeeds"),
            top = r.optJSONArray("top").objects().map(::row),
            qualsComplete = r.optBoolean("qualsComplete", false),
        )
    }

    val chat: WChat? by lazy {
        val c = o?.optJSONObject("chat") ?: return@lazy null
        WChat(c.optInt("unread"), c.optInt("mentions"), c.optJSONArray("groups").objects().map { WChatGroup(it.optString("group"), it.optInt("unread"), it.optInt("mentions")) })
    }

    /** First entry whose match is still ahead (or on the field), judged by its predicted start. */
    fun <T> firstAhead(items: List<T>, now: Long, ref: (T) -> WMatchRef?): T? =
        items.firstOrNull { item -> ref(item)?.predicted?.let { it + ON_FIELD_SECONDS > now } ?: true }

    /** The next time (epoch seconds) a widget would show something different without new data. */
    fun nextTransition(now: Long): Long? {
        val times = buildList {
            matches.filter { !it.played }.forEach { m -> m.start?.let { add(it); add(it + ON_FIELD_SECONDS) } }
            assignmentList.forEach { a -> a.predicted?.let { add(it + ASSIGNMENT_GRACE_SECONDS) } }
            (batterySlots.map { it.match } + checklistMatches.mapNotNull { it.match } + listOfNotNull(prediction?.match, checklistMatch))
                .forEach { r -> r.predicted?.let { add(it); add(it + ON_FIELD_SECONDS) } }
        }
        return times.filter { it > now }.minOrNull()
    }

    companion object {
        const val ON_FIELD_SECONDS = 5 * 60L
        const val ASSIGNMENT_GRACE_SECONDS = 10 * 60L
        const val VERSION = 1

        fun parse(raw: String?): Snapshot {
            val o = raw?.let { runCatching { JSONObject(it) }.getOrNull() }
            return Snapshot(o?.takeIf { it.optInt("v", 0) == VERSION })
        }
    }
}

private fun matchRef(j: JSONObject) = WMatchRef(
    key = j.optString("key"),
    compLevel = j.optString("compLevel"),
    set = if (!j.has("set") || j.isNull("set")) null else j.optInt("set"),
    number = if (!j.has("number") || j.isNull("number")) null else j.optInt("number"),
    label = j.optString("label"),
    predicted = if (!j.has("predicted") || j.isNull("predicted")) null else j.optLong("predicted"),
)

private fun JSONArray?.objects(): List<JSONObject> = if (this == null) emptyList() else (0 until length()).mapNotNull { optJSONObject(it) }
private fun JSONArray?.strings(): List<String> = if (this == null) emptyList() else (0 until length()).map { optString(it) }
private fun JSONObject.optIntOrNull(key: String): Int? = if (!has(key) || isNull(key)) null else optInt(key)
private fun JSONObject.optLongOrNull(key: String): Long? = if (!has(key) || isNull(key)) null else optLong(key)
