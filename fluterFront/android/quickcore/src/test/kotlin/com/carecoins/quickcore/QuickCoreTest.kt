package com.carecoins.quickcore

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.time.Instant
import javax.xml.parsers.DocumentBuilderFactory

class QuickCoreTest {
    @get:Rule
    val tempFolder = TemporaryFolder()

    private lateinit var testFilesDir: File

    @Before
    fun setUp() {
        testFilesDir = tempFolder.newFolder("files")
        SnapshotStore.fallbackFilesDir = testFilesDir
    }

    private fun loadFixture(name: String): String {
        val stream = javaClass.classLoader?.getResourceAsStream(name)
            ?: error("Missing test fixture: $name")
        return stream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    @Test
    fun `parses GET api quick fixture with flexible ids and fractional or plain ISO dates`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))

        assertEquals("101", snap.family.id)
        assertEquals("The Hendersons", snap.family.name)
        assertEquals(240, snap.balance)
        assertEquals(2, snap.needsYou)
        assertEquals(2, snap.tasks.size)

        assertEquals("11", snap.tasks[0].id)
        assertEquals("Bath time", snap.tasks[0].title)
        assertEquals(30, snap.tasks[0].durationMinutes)
        assertEquals(30, snap.tasks[0].coinValue)

        assertEquals("12", snap.tasks[1].id)
        assertEquals("Dishes", snap.tasks[1].title)
        assertEquals(15, snap.tasks[1].durationMinutes)
        assertEquals(15, snap.tasks[1].coinValue)

        assertEquals(4, snap.upcoming.size)
        assertNotNull(snap.running)
        assertEquals("701", snap.running?.id)
        assertEquals("11111111-2222-3333-4444-555555555555", snap.running?.clientRef)
        assertEquals(Instant.parse("2026-11-05T16:00:00Z"), snap.serverTime)
    }

    @Test
    fun `nextUpcoming skips items with startsAt le now and returns first task with startsAt gt now`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))

        // At 16:00:00Z, items 501 (14:30), 502 (14:30) and 503 (15:45..16:15, already under way) have startsAt <= now
        val now = Instant.parse("2026-11-05T16:00:00Z")
        val next = snap.nextUpcoming(now)
        assertNotNull(next)
        assertEquals("504", next?.id)
        assertEquals("Dinner prep", next?.title)

        // Exact startsAt == now is also skipped (not strictly future)
        val exact504Start = Instant.parse("2026-11-05T18:00:00Z")
        assertNull(snap.nextUpcoming(exact504Start))

        val lateNight = Instant.parse("2026-11-05T22:00:00Z")
        assertNull(snap.nextUpcoming(lateNight))
    }

    @Test
    fun `SnapshotStore saves and loads snapshot and enforces 30s undo window`() {
        val raw = loadFixture("quick_snapshot.json")
        assertTrue(SnapshotStore.save(testFilesDir, raw))
        assertFalse(SnapshotStore.save(testFilesDir, "{not valid snapshot}"))

        val loaded = SnapshotStore.load(testFilesDir)
        assertNotNull(loaded)
        assertEquals("101", loaded?.family?.id)

        val t0 = Instant.parse("2026-11-05T16:00:00Z")
        val startedAction = LastAction(
            kind = LastAction.Kind.started,
            taskId = "11",
            activityId = "900",
            clientRef = "ref-abc-12345678",
            at = t0,
        )
        SnapshotStore.recordAction(testFilesDir, startedAction)

        // Within 30s -> canUndo is true
        assertNotNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(15)))
        assertTrue(SnapshotStore.canUndo(testFilesDir, t0.plusSeconds(30)))

        // Past 30s -> lastAction is null and canUndo is false
        assertNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(31)))
        assertFalse(SnapshotStore.canUndo(testFilesDir, t0.plusSeconds(31)))

        // Stopped actions cannot be undone even within 30s
        val stoppedAction = LastAction(
            kind = LastAction.Kind.stopped,
            activityId = "900",
            clientRef = "ref-abc-12345678",
            at = t0,
        )
        SnapshotStore.recordAction(testFilesDir, stoppedAction)
        assertNotNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(5)))
        assertFalse(SnapshotStore.canUndo(testFilesDir, t0.plusSeconds(5)))

        SnapshotStore.clearLastAction(testFilesDir)
        assertNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(5)))
    }

    @Test
    fun `QuickActionResult parses wrapped activity, flat completion and undo responses`() {
        val startJson = JSONObject(
            """
            {
              "activity": {
                "id": 888,
                "title": "Bath time",
                "type": "care",
                "status": "approved",
                "starts_at": "2026-11-05T16:00:00Z",
                "ends_at": "2026-11-05T16:30:00Z",
                "duration_minutes": 30,
                "coin_value": 30,
                "client_ref": "uuid-12345678"
              },
              "warning": "budgetLow"
            }
            """.trimIndent()
        )
        val startRes = QuickActionResult.fromJson(startJson)
        assertEquals("888", startRes.activity?.id)
        assertEquals("Bath time", startRes.activity?.title)
        assertEquals("budgetLow", startRes.warning)
        assertFalse(startRes.replayed)

        val stopJson = JSONObject(
            """
            {
              "id": "889",
              "status": "completed",
              "completed": true,
              "coinsAwarded": 15
            }
            """.trimIndent()
        )
        val stopRes = QuickActionResult.fromJson(stopJson)
        assertEquals("889", stopRes.activity?.id)
        assertEquals(true, stopRes.completed)
        assertEquals(15, stopRes.coinsAwarded)

        val undoRes = QuickActionResult.fromJson(JSONObject("""{"undone": true}"""))
        assertTrue(undoRes.undone)
    }

    @Test
    fun `QuickApi parseErrorBody extracts status, code, message and params`() {
        val body = """
            {
              "error": "You already have \"Bath time\" scheduled during this time.",
              "code": "scheduleOverlap",
              "params": {
                "title": "Bath time",
                "slot": 2
              }
            }
        """.trimIndent()
        val ex = QuickApi.parseErrorBody(body, 409)
        assertEquals(409, ex.status)
        assertEquals("scheduleOverlap", ex.code)
        assertEquals("You already have \"Bath time\" scheduled during this time.", ex.message)
        assertEquals(mapOf("title" to "Bath time", "slot" to "2"), ex.params)

        val plainEx = QuickApi.parseErrorBody("Bad Gateway", 502)
        assertEquals(502, plainEx.status)
        assertNull(plainEx.code)
        assertEquals("Bad Gateway", plainEx.message)
        assertTrue(plainEx.params.isEmpty())

        val emptyEx = QuickApi.parseErrorBody("", 401)
        assertEquals(401, emptyEx.status)
        assertNull(emptyEx.code)
        assertEquals("HTTP 401", emptyEx.message)
    }

    @Test
    fun `strings xml files across en, es, fr, de have identical keys, matching placeholders, and cover Localizable xcstrings`() {
        fun locateProjectDir(): File {
            val candidates = listOf(
                File("."),
                File(".."),
                File("../.."),
                File("fluterFront/android/quickcore"),
            )
            return candidates.firstOrNull { File(it, "src/main/res/values/strings.xml").exists() }
                ?: error("Could not locate quickcore module directory from ${File(".").absolutePath}")
        }

        val moduleDir = locateProjectDir()
        val locales = mapOf(
            "en" to File(moduleDir, "src/main/res/values/strings.xml"),
            "es" to File(moduleDir, "src/main/res/values-es/strings.xml"),
            "fr" to File(moduleDir, "src/main/res/values-fr/strings.xml"),
            "de" to File(moduleDir, "src/main/res/values-de/strings.xml"),
        )

        val placeholderRegex = Regex("""%(\d+\$[sd])""")
        val unescapedApostrophe = Regex("""(?<!\\)'""")

        fun parseStringsXml(file: File): Map<String, String> {
            assertTrue("Missing ${file.path}", file.exists())
            val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
            val nodes = doc.getElementsByTagName("string")
            val result = linkedMapOf<String, String>()
            for (i in 0 until nodes.length) {
                val el = nodes.item(i)
                val name = el.attributes.getNamedItem("name").nodeValue
                val text = el.textContent
                assertFalse(
                    "Unescaped apostrophe in ${file.name} key $name: $text",
                    unescapedApostrophe.containsMatchIn(text),
                )
                result[name] = text
            }
            return result
        }

        val parsedByLocale = locales.mapValues { (_, file) -> parseStringsXml(file) }
        val enMap = parsedByLocale.getValue("en")
        assertTrue("Expected strings in values/strings.xml", enMap.isNotEmpty())

        for ((lang, map) in parsedByLocale) {
            assertEquals("Key set mismatch for locale $lang", enMap.keys, map.keys)
            for ((key, enValue) in enMap) {
                val langValue = map.getValue(key)
                assertTrue("Empty value for $key in $lang", langValue.isNotEmpty())
                val enPlaceholders = placeholderRegex.findAll(enValue).map { it.value }.sorted().toList()
                val langPlaceholders = placeholderRegex.findAll(langValue).map { it.value }.sorted().toList()
                assertEquals(
                    "Placeholder mismatch for key $key in locale $lang",
                    enPlaceholders,
                    langPlaceholders,
                )
            }
        }

        val removedKeys = setOf(
            "widget_didYouFinish",
            "widget_notDone",
            "widget_notDone_done",
            "watch_notDone_confirm",
            "watch_logWhole",
            "widget_until",
        )
        assertTrue(
            "Removed keys must not be present in strings.xml: ${enMap.keys.intersect(removedKeys)}",
            enMap.keys.intersect(removedKeys).isEmpty(),
        )

        // Also check parity with ios/Shared/Localizable.xcstrings if present
        val xcstringsCandidates = listOf(
            File(moduleDir, "../../ios/Shared/Localizable.xcstrings"),
            File("../ios/Shared/Localizable.xcstrings"),
            File("ios/Shared/Localizable.xcstrings"),
        )
        val xcstringsFile = xcstringsCandidates.firstOrNull { it.exists() }
        if (xcstringsFile != null) {
            val xcJson = JSONObject(xcstringsFile.readText(Charsets.UTF_8))
            val xcStrings = xcJson.getJSONObject("strings")
            val expectedKeys = mutableSetOf<String>()
            val iter = xcStrings.keys()
            while (iter.hasNext()) {
                val resName = L10n.resourceName(iter.next())
                if (resName !in removedKeys) {
                    expectedKeys.add(resName)
                }
            }
            assertTrue(
                "Missing Localizable.xcstrings keys in strings.xml: ${expectedKeys - enMap.keys}",
                enMap.keys.containsAll(expectedKeys),
            )
            val extraKeys = enMap.keys - expectedKeys
            assertTrue(
                "Unexpected extra keys in strings.xml: $extraKeys",
                extraKeys.all { it.startsWith("android_") || it == "widget_preview_task" },
            )
        }
    }

    @Test
    fun `pickBanner returns Running only when unplanned task is running, otherwise None`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        val banner1 = QuickSurfaceState.pickBanner(snap, now)
        assertTrue(banner1 is QuickBannerState.Running)
        assertEquals("701", (banner1 as QuickBannerState.Running).running.id)

        // Without running -> None (even when predefined tasks are in progress or recently ended)
        val noRunning = snap.copy(running = null)
        assertEquals(QuickBannerState.None, QuickSurfaceState.pickBanner(noRunning, now))
        assertEquals(QuickBannerState.None, QuickSurfaceState.pickBanner(null, now))
    }

    @Test
    fun `pickNotification posts only for running task with STOP action and cancels otherwise`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        // 1. Running task -> Running notification with STOP action
        val runningState = QuickSurfaceState.pickNotification(snap, now)
        assertTrue(runningState is QuickNotificationState.Running)
        val r = runningState as QuickNotificationState.Running
        assertEquals("701", r.activityId)
        assertTrue(r.ongoing)
        assertEquals(listOf(QuickNotificationAction(QuickNotificationActionKind.STOP, "701")), r.actions)

        // 2. Without running -> None
        val noRunning = snap.copy(running = null)
        assertEquals(QuickNotificationState.None, QuickSurfaceState.pickNotification(noRunning, now))
        assertEquals(QuickNotificationState.None, QuickSurfaceState.pickNotification(null, now))
    }

    @Test
    fun `PendingActionQueue prunes items older than 12h, dedupes by clientRef, and persists to pendingActions json`() {
        val now = Instant.parse("2026-11-05T16:00:00Z")
        val expiredAt = now.minusSeconds(12 * 3600L + 1L)
        val boundaryAt = now.minusSeconds(12 * 3600L)
        val recentAt = now.minusSeconds(600L)

        val items = listOf(
            PendingAction(
                kind = PendingAction.Kind.start,
                taskId = "11",
                clientRef = "ref-expired",
                createdAt = expiredAt,
            ),
            PendingAction(
                kind = PendingAction.Kind.done,
                taskId = "11",
                clientRef = "ref-boundary",
                createdAt = boundaryAt,
            ),
            PendingAction(
                kind = PendingAction.Kind.startNow,
                type = "care",
                title = "Care",
                clientRef = "ref-dup",
                createdAt = recentAt,
            ),
            PendingAction(
                kind = PendingAction.Kind.startNow,
                type = "care",
                title = "Duplicate Care",
                clientRef = "ref-dup",
                createdAt = now,
            ),
            PendingAction(
                kind = PendingAction.Kind.stop,
                activityId = "701",
                clientRef = "ref-stop",
                createdAt = now,
            ),
        )

        val pruned = PendingActionQueue.pruneAndDedupe(items, now)
        assertEquals(3, pruned.size)
        assertEquals(listOf("ref-boundary", "ref-dup", "ref-stop"), pruned.map { it.clientRef })
        assertEquals("Care", pruned[1].title)

        // Disk persistence and enqueue dedupe
        PendingActionQueue.save(testFilesDir, items)
        val loaded = PendingActionQueue.load(testFilesDir, now)
        assertEquals(3, loaded.size)
        assertEquals(listOf("ref-boundary", "ref-dup", "ref-stop"), loaded.map { it.clientRef })

        // Enqueueing a duplicate clientRef does not add a second copy
        val afterDup = PendingActionQueue.enqueue(
            testFilesDir,
            PendingAction(
                kind = PendingAction.Kind.stop,
                activityId = "701",
                clientRef = "ref-stop",
                createdAt = now,
            ),
            now,
        )
        assertEquals(3, afterDup.size)

        PendingActionQueue.clear(testFilesDir)
        assertTrue(PendingActionQueue.load(testFilesDir, now).isEmpty())
    }

    @Test
    fun `wearSections orders Running, Now, Tasks, Coins and hides Now while running`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        // 1. With running task ("701"): [Running, Tasks, Coins] — Now is hidden while running
        val runningSections = QuickSurfaceState.wearSections(snap, now)
        assertEquals(3, runningSections.size)
        assertTrue(runningSections[0] is WearSection.Running)
        assertEquals("701", (runningSections[0] as WearSection.Running).running.id)
        assertTrue(runningSections[1] is WearSection.Tasks)
        assertEquals(WearSection.Coins(240), runningSections[2])

        // 2. Without running: [Now, Tasks, Coins]
        val noRunning = snap.copy(running = null)
        val idleSections = QuickSurfaceState.wearSections(noRunning, now)
        assertEquals(listOf(WearSection.Now, WearSection.Tasks(snap.tasks), WearSection.Coins(240)), idleSections)

        // 3. Null snapshot -> empty
        assertTrue(QuickSurfaceState.wearSections(null, now).isEmpty())
    }

    @Test
    fun `selectReminders filters excluded statuses, enforces startsAt minus 15m gt now, respects enabled and caps at 20`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        // Fixture has 504 at 18:00Z (status pending_validation -> allowed, reminder at 17:45Z)
        val fixtureReminders = QuickSurfaceState.selectReminders(snap, now, enabled = true)
        assertEquals(1, fixtureReminders.size)
        assertEquals("504", fixtureReminders[0].id)
        assertEquals(Instant.parse("2026-11-05T17:45:00Z"), fixtureReminders[0].at)

        // Disabled, disconnected or null snapshot -> empty
        assertTrue(QuickSurfaceState.selectReminders(snap, now, enabled = false).isEmpty())
        assertTrue(QuickSurfaceState.selectReminders(snap, now, enabled = true, connected = false).isEmpty())
        assertTrue(QuickSurfaceState.selectReminders(null, now, enabled = true).isEmpty())

        // Status filtering and exact 15-min boundary: startsAt - 15m == now must be excluded, > now included
        val customUpcoming = buildList {
            // Excluded statuses
            add(Upcoming("ex-1", "Done", "care", now.plusSeconds(3600), null, "completed"))
            add(Upcoming("ex-2", "Rejected", "care", now.plusSeconds(3600), null, "rejected"))
            add(Upcoming("ex-3", "Cancelled UK", "care", now.plusSeconds(3600), null, "cancelled"))
            add(Upcoming("ex-4", "Canceled US", "care", now.plusSeconds(3600), null, "canceled"))
            // Exact boundary: startsAt = now + 15m -> startsAt - 15m == now (excluded)
            add(Upcoming("boundary", "Boundary", "care", now.plusSeconds(15 * 60L), null, "approved"))
            // 25 valid future items (1 second after boundary onwards)
            for (i in 1..25) {
                val starts = now.plusSeconds(15 * 60L + i * 60L)
                val status = if (i % 2 == 0) "approved" else "pending_validation"
                add(Upcoming("ok-$i", "Task $i", "care", starts, starts.plusSeconds(900), status))
            }
        }
        val manySnap = snap.copy(upcoming = customUpcoming)
        val selected = QuickSurfaceState.selectReminders(manySnap, now, enabled = true)
        assertEquals(20, selected.size)
        assertEquals("ok-1", selected.first().id)
        assertEquals(now.plusSeconds(60L), selected.first().at)
        assertEquals("ok-20", selected.last().id)
        assertEquals(now.plusSeconds(20 * 60L), selected.last().at)
    }

    @Test
    fun `pickNext orders Running, NextUpcoming, NoTasks, and NotConnected`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        // 0. Not connected or null snapshot
        assertEquals(WearNextState.NotConnected, QuickSurfaceState.pickNext(null, now))
        assertEquals(WearNextState.NotConnected, QuickSurfaceState.pickNext(snap, now, connected = false))

        // 1. Running ("701") takes top priority
        val s1 = QuickSurfaceState.pickNext(snap, now)
        assertTrue(s1 is WearNextState.Running)
        assertEquals("701", (s1 as WearNextState.Running).running.id)

        // 2. Without running -> NextUpcoming ("504" at 18:00Z; skips 503 whose startsAt 15:45 <= 16:00)
        val noRunning = snap.copy(running = null)
        val s2 = QuickSurfaceState.pickNext(noRunning, now)
        assertTrue(s2 is WearNextState.NextUpcoming)
        assertEquals("504", (s2 as WearNextState.NextUpcoming).upcoming.id)

        // 3. Late night (nothing running or future upcoming) -> NoTasks
        val lateNight = Instant.parse("2026-11-05T22:00:00Z")
        assertEquals(WearNextState.NoTasks, QuickSurfaceState.pickNext(noRunning, lateNight))

        // Timeline instants only include future startsAt values
        val instants = QuickSurfaceState.nextTimelineInstants(noRunning, now)
        assertEquals(
            listOf(
                Instant.parse("2026-11-05T18:00:00Z"),
            ),
            instants,
        )
    }

    @Test
    fun `chipExpiryInstant and chipExpiryDelayMillis schedule expiry at actionAt plus 30s plus 1s`() {
        val t0 = Instant.parse("2026-11-05T16:00:00Z")
        val action = LastAction(
            kind = LastAction.Kind.logged,
            taskId = "11",
            clientRef = "ref-11",
            at = t0,
        )

        val expectedExpiry = Instant.parse("2026-11-05T16:00:31Z")
        assertEquals(expectedExpiry, QuickSurfaceState.chipExpiryInstant(t0))
        assertEquals(expectedExpiry, QuickSurfaceState.chipExpiryInstant(action))

        assertEquals(31_000L, QuickSurfaceState.chipExpiryDelayMillis(t0, now = t0))
        assertEquals(16_000L, QuickSurfaceState.chipExpiryDelayMillis(t0, now = t0.plusSeconds(15)))
        assertEquals(0L, QuickSurfaceState.chipExpiryDelayMillis(t0, now = t0.plusSeconds(40)))

        // At exact expiry (t0 + 31s), SnapshotStore.lastAction is null
        SnapshotStore.recordAction(testFilesDir, action)
        assertNotNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(30)))
        assertNull(SnapshotStore.lastAction(testFilesDir, QuickSurfaceState.chipExpiryInstant(action)))
    }

    @Test
    fun `smallLayoutRowCount uses the 160x180 tall bucket and returns 3 when idle or 1 when running`() {
        // Small bucket (110x110)
        assertFalse(QuickSurfaceState.isSmallTallBucket(110, 110))
        assertEquals(1, QuickSurfaceState.smallLayoutRowCount(110, 110, hasRunning = false))
        assertEquals(0, QuickSurfaceState.smallLayoutRowCount(110, 110, hasRunning = true))
        assertEquals(1, QuickSurfaceState.smallLayoutRowCount(isTallBucket = false, hasRunning = false))
        assertEquals(0, QuickSurfaceState.smallLayoutRowCount(isTallBucket = false, hasRunning = true))

        // Tall bucket (160x180) and Pixel 2x2 size (179x210)
        assertTrue(QuickSurfaceState.isSmallTallBucket(160, 180))
        assertTrue(QuickSurfaceState.isSmallTallBucket(179, 210))
        assertEquals(3, QuickSurfaceState.smallLayoutRowCount(160, 180, hasRunning = false))
        assertEquals(1, QuickSurfaceState.smallLayoutRowCount(160, 180, hasRunning = true))
        assertEquals(3, QuickSurfaceState.smallLayoutRowCount(isTallBucket = true, hasRunning = false))
        assertEquals(1, QuickSurfaceState.smallLayoutRowCount(isTallBucket = true, hasRunning = true))
    }

    @Test
    fun `SnapshotStore version increments on save, recordAction, clearLastAction and clear`() {
        val raw = loadFixture("quick_snapshot.json")
        val v0 = SnapshotStore.version.value

        assertTrue(SnapshotStore.save(testFilesDir, raw))
        val v1 = SnapshotStore.version.value
        assertTrue(v1 > v0)

        // Invalid save does not bump version
        assertFalse(SnapshotStore.save(testFilesDir, "{invalid}"))
        assertEquals(v1, SnapshotStore.version.value)

        SnapshotStore.recordAction(
            testFilesDir,
            LastAction(kind = LastAction.Kind.started, taskId = "11"),
        )
        val v2 = SnapshotStore.version.value
        assertTrue(v2 > v1)

        SnapshotStore.clearLastAction(testFilesDir)
        val v3 = SnapshotStore.version.value
        assertTrue(v3 > v2)

        SnapshotStore.clear(testFilesDir)
        val v4 = SnapshotStore.version.value
        assertTrue(v4 > v3)
    }
}
