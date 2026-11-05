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
    fun `startedTask returns approved task where startsAt le now and now lt endsAt`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))

        val now = Instant.parse("2026-11-05T16:00:00Z")
        val started = snap.startedTask(now)
        assertNotNull(started)
        assertEquals("503", started?.id)
        assertEquals("School pickup", started?.title)

        // At exact endsAt, it is no longer started
        val atEnd = Instant.parse("2026-11-05T16:15:00.123Z")
        assertNull(snap.startedTask(atEnd))
    }

    @Test
    fun `awaitingConfirmation respects status approved, endsAt le now and 2h window, ignoring completed`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))

        // At 16:00:00Z:
        // - 501 (14:30..15:00) has status="completed" -> must NOT show
        // - 502 (14:30..15:30) has status="approved", endsAt <= 16:00 and startsAt >= 14:00 -> matches
        val now = Instant.parse("2026-11-05T16:00:00Z")
        val awaiting = snap.awaitingConfirmation(now)
        assertNotNull(awaiting)
        assertEquals("502", awaiting?.id)
        assertEquals("Finished nap time", awaiting?.title)

        // If only a completed or pending_validation task ended in the last 2 hours, returns null
        val completedOnly = snap.copy(
            upcoming = listOf(
                Upcoming(
                    id = "501",
                    title = "Completed morning walk",
                    type = "care",
                    startsAt = Instant.parse("2026-11-05T14:30:00Z"),
                    endsAt = Instant.parse("2026-11-05T15:00:00Z"),
                    status = "completed",
                ),
                Upcoming(
                    id = "505",
                    title = "Pending validation task",
                    type = "care",
                    startsAt = Instant.parse("2026-11-05T14:45:00Z"),
                    endsAt = Instant.parse("2026-11-05T15:15:00Z"),
                    status = "pending_validation",
                ),
            )
        )
        assertNull(completedOnly.awaitingConfirmation(now))

        // More than 2 hours after startsAt (14:30 + 2h01m = 16:31), 502 expires from awaitingConfirmation
        val afterTwoHours = Instant.parse("2026-11-05T16:31:00Z")
        val only502 = snap.copy(upcoming = listOf(snap.upcoming[1]))
        assertNull(only502.awaitingConfirmation(afterTwoHours))
    }

    @Test
    fun `nextUpcoming returns first task with startsAt gt now`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))

        val now = Instant.parse("2026-11-05T16:00:00Z")
        val next = snap.nextUpcoming(now)
        assertNotNull(next)
        assertEquals("504", next?.id)
        assertEquals("Dinner prep", next?.title)

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

        // Stopped or cancelled actions cannot be undone even within 30s
        val stoppedAction = LastAction(
            kind = LastAction.Kind.stopped,
            activityId = "900",
            clientRef = "ref-abc-12345678",
            at = t0,
        )
        SnapshotStore.recordAction(testFilesDir, stoppedAction)
        assertNotNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(5)))
        assertFalse(SnapshotStore.canUndo(testFilesDir, t0.plusSeconds(5)))

        val cancelledAction = LastAction(
            kind = LastAction.Kind.cancelled,
            activityId = "900",
            clientRef = "ref-abc-12345678",
            at = t0,
        )
        SnapshotStore.recordAction(testFilesDir, cancelledAction)
        assertEquals(LastAction.Kind.cancelled, SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(5))?.kind)
        assertFalse(SnapshotStore.canUndo(testFilesDir, t0.plusSeconds(5)))

        SnapshotStore.clearLastAction(testFilesDir)
        assertNull(SnapshotStore.lastAction(testFilesDir, t0.plusSeconds(5)))
    }

    @Test
    fun `QuickActionResult parses wrapped activity, flat completion, undo and cancel responses`() {
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

        val cancelRes = QuickActionResult.fromJson(JSONObject("""{"cancelled": true}"""))
        assertTrue(cancelRes.cancelled)

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
                expectedKeys.add(L10n.resourceName(iter.next()))
            }
            assertTrue(
                "Missing Localizable.xcstrings keys in strings.xml: ${expectedKeys - enMap.keys}",
                enMap.keys.containsAll(expectedKeys),
            )
            val extraKeys = enMap.keys - expectedKeys
            assertTrue(
                "Unexpected extra keys in strings.xml: $extraKeys",
                extraKeys.all { it.startsWith("android_") },
            )
        }
    }

    @Test
    fun `pickBanner prioritizes running, then started, then confirm, then none`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        // Fixture has running ("701"), started ("503"), and awaitingConfirmation ("502")
        val banner1 = QuickSurfaceState.pickBanner(snap, now)
        assertTrue(banner1 is QuickBannerState.Running)
        assertEquals("701", (banner1 as QuickBannerState.Running).running.id)

        // Without running -> Started ("503")
        val noRunning = snap.copy(running = null)
        val banner2 = QuickSurfaceState.pickBanner(noRunning, now)
        assertTrue(banner2 is QuickBannerState.Started)
        assertEquals("503", (banner2 as QuickBannerState.Started).started.id)

        // At 16:20:00Z (after 503's endsAt 16:15:00.123Z), nothing started -> Confirm ("502")
        val afterStarted = Instant.parse("2026-11-05T16:20:00Z")
        val banner3 = QuickSurfaceState.pickBanner(noRunning, afterStarted)
        assertTrue(banner3 is QuickBannerState.Confirm)
        assertEquals("502", (banner3 as QuickBannerState.Confirm).awaiting.id)

        // Without running, started or awaiting -> None
        val lateNight = Instant.parse("2026-11-05T22:00:00Z")
        val banner4 = QuickSurfaceState.pickBanner(noRunning, lateNight)
        assertEquals(QuickBannerState.None, banner4)
        assertEquals(QuickBannerState.None, QuickSurfaceState.pickBanner(null, now))
    }

    @Test
    fun `pickNotification state machine selects state and actions and only confirms matching shownStartedActivityId`() {
        val raw = loadFixture("quick_snapshot.json")
        val snap = QuickSnapshot.fromJson(JSONObject(raw))
        val now = Instant.parse("2026-11-05T16:00:00Z")

        // 1. Running task -> Running notification with STOP action
        val runningState = QuickSurfaceState.pickNotification(snap, now, shownStartedActivityId = null)
        assertTrue(runningState is QuickNotificationState.Running)
        val r = runningState as QuickNotificationState.Running
        assertEquals("701", r.activityId)
        assertTrue(r.ongoing)
        assertEquals(listOf(QuickNotificationAction(QuickNotificationActionKind.STOP, "701")), r.actions)

        // 2. Started task -> Started notification with FINISH action
        val noRunning = snap.copy(running = null)
        val startedState = QuickSurfaceState.pickNotification(noRunning, now, shownStartedActivityId = null)
        assertTrue(startedState is QuickNotificationState.Started)
        val s = startedState as QuickNotificationState.Started
        assertEquals("503", s.activityId)
        assertTrue(s.ongoing)
        assertEquals(listOf(QuickNotificationAction(QuickNotificationActionKind.FINISH, "503")), s.actions)

        // 3. Awaiting confirmation when shownStartedActivityId matches -> Confirm with FINISH and CANCEL, not ongoing
        val after503Ends = Instant.parse("2026-11-05T16:20:00Z")
        val only503 = noRunning.copy(upcoming = listOf(snap.upcoming[2])) // 503 is index 2
        val confirmMatch = QuickSurfaceState.pickNotification(
            only503,
            after503Ends,
            shownStartedActivityId = "503",
        )
        assertTrue(confirmMatch is QuickNotificationState.Confirm)
        val c = confirmMatch as QuickNotificationState.Confirm
        assertEquals("503", c.activityId)
        assertFalse(c.ongoing)
        assertEquals(
            listOf(
                QuickNotificationAction(QuickNotificationActionKind.FINISH, "503"),
                QuickNotificationAction(QuickNotificationActionKind.CANCEL, "503"),
            ),
            c.actions,
        )

        // 4. Awaiting confirmation when shownStartedActivityId does NOT match or is null -> None
        assertEquals(
            QuickNotificationState.None,
            QuickSurfaceState.pickNotification(only503, after503Ends, shownStartedActivityId = null),
        )
        assertEquals(
            QuickNotificationState.None,
            QuickSurfaceState.pickNotification(only503, after503Ends, shownStartedActivityId = "other-id"),
        )

        // 5. Nothing active -> None
        val lateNight = Instant.parse("2026-11-05T22:00:00Z")
        assertEquals(
            QuickNotificationState.None,
            QuickSurfaceState.pickNotification(noRunning, lateNight, shownStartedActivityId = "503"),
        )
    }
}
