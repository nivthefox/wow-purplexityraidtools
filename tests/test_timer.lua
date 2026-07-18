-- tests/test_timer.lua
-- Exercises NotesTimer, the pure reminder-timing state machine (spec 6, 9).
--
-- NotesTimer is a PURE state machine: it never calls GetTime(), C_Timer, or any
-- WoW API. Time is injected on every entry point:
--   NotesTimer:Start(section, callbacks, now)  -- begin phase 1 at `now`
--   NotesTimer:Tick(now)                       -- evaluate pending reminders
--   NotesTimer:SetPhase(phase, now)            -- phase transition (same-phase = no-op)
--   NotesTimer:Stop()                          -- cancel everything
--
-- FROZEN callback signatures (see Notes.lua DATA CONTRACT):
--   onPopupShow(reminder, remaining)
--   onAudio(reminder)
--   onCountdown(reminder, number)
--   onPopupExpire(reminder)
--   onCancelPhase(reminders)
--
-- Behavioral reference: NorthernSkyRaidTools/Reminders.lua. Copy behavior only.
--
-- ============================================================================
-- BEHAVIORAL DECISIONS LOCKED IN BY THIS SUITE (see final report for rationale):
--
-- 1. remaining = reminder.time - (now - phaseStart). Phase times are relative
--    to the phase's start `now`, NOT to encounter start (spec 6.1 / 6.4).
--
-- 2. Popup fires ONCE when `remaining <= duration`; re-ticking past the
--    threshold does not re-fire. `remaining` passed is the value at the tick
--    that first crossed the threshold.
--
-- 3. Audio fires ONCE when `remaining <= ttsTimer` (spec 6.4 / 9.2.1). A
--    reminder with ttsTimer == nil has no audio timer and never fires onAudio.
--    A reminder with ttsTimer == 0 fires onAudio when remaining <= 0 (at the
--    event), per the literal `remaining <= ttsTimer` rule.
--
-- 4. Countdown CROSSING: the timer tracks lastRemaining per reminder. On each
--    tick, for every integer N with `remaining < N <= lastRemaining` AND
--    `N <= countdown` AND `N >= 1`, fire onCountdown(reminder, N) exactly once,
--    in descending order. A single tick that jumps past several integers
--    announces all of them. Numbers are never announced twice, and nothing is
--    announced once the event has passed (N >= 1 guard).
--
-- 5. onPopupExpire fires ONCE when a shown popup's remaining reaches <= 0.
--
-- 6. SetPhase to a NEW phase fires onCancelPhase(reminders) with EVERY
--    earlier-phase reminder that is either unfired (popup never shown) OR shown
--    but not yet expired. Already-expired reminders are NOT included. (The
--    frozen contract has a single teardown callback; spec 6.3 says "cancel
--    unfired reminders AND dismiss their popups" — both sets flow through
--    onCancelPhase. Flagged in report.)
--
-- 7. Same-phase SetPhase is a NO-OP: no cancellation, no re-fire, phaseStart
--    unchanged (BigWigs/DBM dedupe, spec 6.3 step 2).
--
-- 8. Fractional phases: SetPhase(2.5, now) selects reminders under phaseKey
--    "2.5"; that phase's timing restarts at `now`.
--
-- 9. Relevance: the timer processes ONLY reminders with relevant == true
--    (spec 6.4 step 2: "for each unfired reminder whose tag matches the local
--    player"). relevant == false reminders never fire any callback and are
--    never included in onCancelPhase. (Flagged: tension with the task's
--    "frame/popup layer filters" note; §6.4 is followed as authoritative.)
--
-- 10. Stop() clears all state; a later Tick fires nothing. A fresh Start after
--     Stop resets fired/shown flags so reminders fire again.
-- ============================================================================

dofile("Modules/Notes/Notes.lua")
dofile("Modules/Notes/NotesTimer.lua")

local PRT = PurplexityRaidTools
local NotesTimer = PRT.NotesTimer

--------------------------------------------------------------------------------
-- Fixtures & helpers
--------------------------------------------------------------------------------

-- Build a reminder table matching the FROZEN DATA CONTRACT. Only the fields the
-- timer engine consumes are populated; everything else is defaulted sensibly.
-- Callers override via the `opts` table.
local function makeReminder(opts)
    opts = opts or {}
    local phase = opts.phase or 1
    local r = {
        time        = opts.time,
        tag         = opts.tag or "everyone",
        text        = opts.text or "do the thing",
        spellID     = opts.spellID,
        phase       = phase,
        phaseKey    = opts.phaseKey or tostring(phase),
        duration    = opts.duration or 5,
        displayType = opts.displayType or "Text",
        tts         = opts.tts,
        ttsTimer    = opts.ttsTimer,   -- nil = no audio timer
        countdown   = opts.countdown,  -- nil = no countdown
        sound       = opts.sound,
        bossSpell   = opts.bossSpell,
        colors      = opts.colors,
        -- relevant defaults to true; pass relevant = false to opt out.
        relevant    = (opts.relevant == nil) and true or opts.relevant,
    }
    -- A stable tag for identity assertions in recorders.
    r.id = opts.id
    return r
end

-- Build a section shell: { reminders = { [phaseKey] = { sorted array } } }.
-- Accepts a flat list of reminders and buckets them by phaseKey, sorted by time.
local function makeSection(reminders)
    local byPhase = {}
    for _, r in ipairs(reminders) do
        local key = r.phaseKey
        byPhase[key] = byPhase[key] or {}
        table.insert(byPhase[key], r)
    end
    for _, bucket in pairs(byPhase) do
        table.sort(bucket, function(a, b) return a.time < b.time end)
    end
    return {
        encounterID = 1000,
        name        = "Test Boss",
        difficulty  = "Mythic",
        reminders   = byPhase,
        lines       = {},
    }
end

-- Recorder: captures every callback invocation into ordered arrays.
local function makeRecorder()
    local rec = {
        popupShow   = {},  -- { {reminder=, remaining=}, ... }
        audio       = {},  -- { reminder, ... }
        countdown   = {},  -- { {reminder=, number=}, ... }
        popupExpire = {},  -- { reminder, ... }
        cancelPhase = {},  -- { reminders(array), ... } one entry per call
    }
    rec.callbacks = {
        onPopupShow = function(reminder, remaining)
            table.insert(rec.popupShow, { reminder = reminder, remaining = remaining })
        end,
        onAudio = function(reminder)
            table.insert(rec.audio, reminder)
        end,
        onCountdown = function(reminder, number)
            table.insert(rec.countdown, { reminder = reminder, number = number })
        end,
        onPopupExpire = function(reminder)
            table.insert(rec.popupExpire, reminder)
        end,
        onCancelPhase = function(reminders)
            table.insert(rec.cancelPhase, reminders)
        end,
    }
    return rec
end

-- Collect just the numbers announced via onCountdown, in call order.
local function countdownNumbers(rec)
    local nums = {}
    for _, entry in ipairs(rec.countdown) do
        nums[#nums + 1] = entry.number
    end
    return nums
end

local tests = {}

--------------------------------------------------------------------------------
-- Popup: single fire, correct remaining
--------------------------------------------------------------------------------

tests["popup fires when remaining <= duration"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(20)   -- remaining 10 > 5, no popup
    assertEquals(#rec.popupShow, 0)

    NotesTimer:Tick(26)   -- remaining 4 <= 5, popup
    assertEquals(#rec.popupShow, 1)
    assertEquals(rec.popupShow[1].reminder, r)
end

tests["popup passes correct remaining at crossing tick"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- remaining 3
    assertEquals(#rec.popupShow, 1)
    assertNear(rec.popupShow[1].remaining, 3, 1e-9)
end

tests["popup fires exactly once across multiple ticks past threshold"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(26)
    NotesTimer:Tick(27)
    NotesTimer:Tick(28)
    assertEquals(#rec.popupShow, 1)
end

tests["popup fires when a tick lands exactly on the threshold"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(25)   -- remaining exactly 5, <= duration
    assertEquals(#rec.popupShow, 1)
    assertNear(rec.popupShow[1].remaining, 5, 1e-9)
end

--------------------------------------------------------------------------------
-- Popup expiry
--------------------------------------------------------------------------------

tests["popup expire fires once when remaining reaches zero"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- show
    assertEquals(#rec.popupExpire, 0)
    NotesTimer:Tick(30)   -- remaining 0 -> expire
    assertEquals(#rec.popupExpire, 1)
    assertEquals(rec.popupExpire[1], r)
    NotesTimer:Tick(31)   -- past event, no re-fire
    assertEquals(#rec.popupExpire, 1)
end

tests["popup expire fires when a tick jumps from shown to past-event"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(26)   -- show (remaining 4)
    NotesTimer:Tick(35)   -- remaining -5 -> expire
    assertEquals(#rec.popupShow, 1)
    assertEquals(#rec.popupExpire, 1)
end

--------------------------------------------------------------------------------
-- Audio
--------------------------------------------------------------------------------

tests["audio fires once when remaining <= ttsTimer"] = function()
    local r = makeReminder({ time = 30, duration = 5, tts = "true", ttsTimer = 3 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(26)   -- remaining 4 > 3, no audio yet (popup shows though)
    assertEquals(#rec.audio, 0)
    NotesTimer:Tick(28)   -- remaining 2 <= 3, audio
    assertEquals(#rec.audio, 1)
    assertEquals(rec.audio[1], r)
    NotesTimer:Tick(29)   -- no re-fire
    assertEquals(#rec.audio, 1)
end

tests["reminder without ttsTimer never fires audio"] = function()
    local r = makeReminder({ time = 30, duration = 5, ttsTimer = nil })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(26)
    NotesTimer:Tick(30)
    NotesTimer:Tick(31)
    assertEquals(#rec.audio, 0)
end

tests["audio with ttsTimer equal to duration fires at popup time"] = function()
    -- Default TTSTimer == dur: alert coincides with popup appearance.
    local r = makeReminder({ time = 30, duration = 5, tts = "true", ttsTimer = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(25)   -- remaining 5: popup AND audio both cross
    assertEquals(#rec.popupShow, 1)
    assertEquals(#rec.audio, 1)
end

tests["audio with ttsTimer zero fires at the event, not before"] = function()
    local r = makeReminder({ time = 30, duration = 5, tts = "true", ttsTimer = 0 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(29)   -- remaining 1 > 0, no audio
    assertEquals(#rec.audio, 0)
    NotesTimer:Tick(30)   -- remaining 0 <= 0, audio
    assertEquals(#rec.audio, 1)
end

--------------------------------------------------------------------------------
-- Countdown: crossing semantics
--------------------------------------------------------------------------------

tests["countdown announces 3,2,1 on integer-aligned ticks"] = function()
    local r = makeReminder({ time = 30, countdown = 3, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- remaining 3: nothing yet (3 not < 3)
    NotesTimer:Tick(27.5) -- remaining 2.5: crosses 3
    NotesTimer:Tick(28.5) -- remaining 1.5: crosses 2
    NotesTimer:Tick(29.5) -- remaining 0.5: crosses 1
    assertTableEquals(countdownNumbers(rec), { 3, 2, 1 })
end

tests["countdown with decimal event time announces at correct crossings"] = function()
    -- time 90.5, countdown 3 -> announces 3,2,1 as remaining crosses them.
    -- Crossings occur at now-phaseStart = 87.5 (rem 3), 88.5 (rem 2), 89.5 (rem 1).
    local r = makeReminder({ time = 90.5, countdown = 3, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(87.5)  -- remaining 3.0: 3 not < 3, nothing
    assertEquals(#rec.countdown, 0)
    NotesTimer:Tick(88)    -- remaining 2.5: crosses 3
    NotesTimer:Tick(89)    -- remaining 1.5: crosses 2
    NotesTimer:Tick(90)    -- remaining 0.5: crosses 1
    assertTableEquals(countdownNumbers(rec), { 3, 2, 1 })
end

tests["jittered tick jumping past two integers announces both"] = function()
    -- A single tick that crosses two whole seconds announces both, descending.
    local r = makeReminder({ time = 30, countdown = 3, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27.1)  -- remaining 2.9: crosses 3
    assertTableEquals(countdownNumbers(rec), { 3 })
    NotesTimer:Tick(29.05) -- remaining 0.95: jumps past 2 AND 1
    assertTableEquals(countdownNumbers(rec), { 3, 2, 1 })
end

tests["irregular tick intervals never double-announce"] = function()
    -- Ticks at ~0.9s and ~1.13s intervals; every integer announced once only.
    local r = makeReminder({ time = 30, countdown = 3, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27.02)  -- rem 2.98 -> 3
    NotesTimer:Tick(27.92)  -- rem 2.08 -> (nothing new; 2 not yet crossed)
    NotesTimer:Tick(29.05)  -- rem 0.95 -> 2, 1
    NotesTimer:Tick(29.9)   -- rem 0.10 -> nothing
    assertTableEquals(countdownNumbers(rec), { 3, 2, 1 })
end

tests["countdown announces nothing after the event time passes"] = function()
    local r = makeReminder({ time = 30, countdown = 3, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(31)   -- already past event; no announcements (0 excluded)
    assertEquals(#rec.countdown, 0)
end

tests["countdown never announces zero"] = function()
    local r = makeReminder({ time = 30, countdown = 3, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27.5)  -- rem 2.5 -> 3
    NotesTimer:Tick(28.5)  -- rem 1.5 -> 2
    NotesTimer:Tick(29.5)  -- rem 0.5 -> 1
    NotesTimer:Tick(30)    -- rem 0.0 -> nothing (0 not announced)
    NotesTimer:Tick(30.5)  -- rem -0.5 -> nothing
    assertTableEquals(countdownNumbers(rec), { 3, 2, 1 })
end

tests["countdown range caps announcements at the countdown value"] = function()
    -- countdown 3 but a large lead: never announce 4, 5, ...
    local r = makeReminder({ time = 30, countdown = 3, duration = 10 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(15)    -- rem 15
    NotesTimer:Tick(25)    -- rem 5: still above countdown 3, nothing
    assertEquals(#rec.countdown, 0)
    NotesTimer:Tick(29.5)  -- rem 0.5: crosses 3,2,1
    assertTableEquals(countdownNumbers(rec), { 3, 2, 1 })
end

tests["reminder without countdown never announces"] = function()
    local r = makeReminder({ time = 30, countdown = nil, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(28)
    NotesTimer:Tick(29)
    NotesTimer:Tick(30)
    assertEquals(#rec.countdown, 0)
end

--------------------------------------------------------------------------------
-- Multiple reminders, same phase, interleaved thresholds
--------------------------------------------------------------------------------

tests["multiple reminders fire in threshold order with correct counts"] = function()
    local early = makeReminder({ id = "early", time = 10, duration = 3 })
    local late  = makeReminder({ id = "late",  time = 20, duration = 3 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ early, late }), rec.callbacks, 0)

    NotesTimer:Tick(8)    -- early rem 2 <= 3 shows; late rem 12 no
    assertEquals(#rec.popupShow, 1)
    assertEquals(rec.popupShow[1].reminder, early)

    NotesTimer:Tick(10)   -- early expires; late still no
    assertEquals(#rec.popupExpire, 1)
    assertEquals(rec.popupExpire[1], early)

    NotesTimer:Tick(18)   -- late shows (rem 2)
    assertEquals(#rec.popupShow, 2)
    assertEquals(rec.popupShow[2].reminder, late)

    NotesTimer:Tick(20)   -- late expires
    assertEquals(#rec.popupExpire, 2)
    assertEquals(rec.popupExpire[2], late)
end

tests["two reminders crossing in one tick both fire"] = function()
    local a = makeReminder({ id = "a", time = 10, duration = 5 })
    local b = makeReminder({ id = "b", time = 12, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ a, b }), rec.callbacks, 0)

    NotesTimer:Tick(8)    -- a rem 2 <= 5, b rem 4 <= 5: both show
    assertEquals(#rec.popupShow, 2)
end

--------------------------------------------------------------------------------
-- Phase-relative timing
--------------------------------------------------------------------------------

tests["phase 2 reminder times are relative to phase start, not encounter start"] = function()
    local r = makeReminder({ id = "p2", time = 10, duration = 5, phase = 2, phaseKey = "2" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 100)

    -- Still phase 1 at absolute time 200: phase-2 reminder must not fire.
    NotesTimer:Tick(200)
    assertEquals(#rec.popupShow, 0)

    -- Phase 2 begins at absolute time 500.
    NotesTimer:SetPhase(2, 500)
    -- remaining = 10 - (now - 500). At now=505, remaining = 5 -> show.
    NotesTimer:Tick(505)
    assertEquals(#rec.popupShow, 1)
    assertNear(rec.popupShow[1].remaining, 5, 1e-9)
    -- Event at now=510.
    NotesTimer:Tick(510)
    assertEquals(#rec.popupExpire, 1)
end

tests["phase 1 reminder timing is relative to encounter start now"] = function()
    local r = makeReminder({ time = 10, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 100)

    NotesTimer:Tick(107)  -- remaining 3 (relative to start 100) -> show
    assertEquals(#rec.popupShow, 1)
    assertNear(rec.popupShow[1].remaining, 3, 1e-9)
end

--------------------------------------------------------------------------------
-- Fractional phases
--------------------------------------------------------------------------------

tests["fractional phase 2.5 selects phaseKey 2.5 reminders and restarts timing"] = function()
    local inter = makeReminder({ id = "inter", time = 4, duration = 3, phase = 2.5, phaseKey = "2.5" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ inter }), rec.callbacks, 0)

    NotesTimer:Tick(50)   -- phase 1: intermission reminder inert
    assertEquals(#rec.popupShow, 0)

    NotesTimer:SetPhase(2.5, 1000)   -- intermission begins at now=1000
    NotesTimer:Tick(1002)            -- remaining 4 - 2 = 2 <= 3 -> show
    assertEquals(#rec.popupShow, 1)
    assertEquals(rec.popupShow[1].reminder, inter)
    assertNear(rec.popupShow[1].remaining, 2, 1e-9)
end

--------------------------------------------------------------------------------
-- SetPhase: cancellation semantics
--------------------------------------------------------------------------------

tests["SetPhase to new phase cancels unfired earlier-phase reminders"] = function()
    local p1 = makeReminder({ id = "p1", time = 30, duration = 5, phase = 1, phaseKey = "1" })
    local p2 = makeReminder({ id = "p2", time = 10, duration = 5, phase = 2, phaseKey = "2" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ p1, p2 }), rec.callbacks, 0)

    NotesTimer:Tick(5)    -- nothing near threshold yet
    assertEquals(#rec.popupShow, 0)

    NotesTimer:SetPhase(2, 100)
    -- p1 never fired -> reported for cancellation.
    assertEquals(#rec.cancelPhase, 1)
    assertEquals(#rec.cancelPhase[1], 1)
    assertEquals(rec.cancelPhase[1][1], p1)

    -- A phase-1 reminder that never fired must never fire afterward.
    NotesTimer:Tick(120)  -- absolute time well past p1's original window
    assertEquals(#rec.popupShow, 0)
end

tests["SetPhase reports shown-but-unexpired earlier-phase popups for teardown"] = function()
    local p1 = makeReminder({ id = "p1", time = 30, duration = 5, phase = 1, phaseKey = "1" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ p1 }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- p1 popup shown (remaining 3), not yet expired
    assertEquals(#rec.popupShow, 1)
    assertEquals(#rec.popupExpire, 0)

    NotesTimer:SetPhase(2, 28)
    -- p1 was shown but not expired -> flows through onCancelPhase for dismissal.
    assertEquals(#rec.cancelPhase, 1)
    assertEquals(#rec.cancelPhase[1], 1)
    assertEquals(rec.cancelPhase[1][1], p1)
    -- It must NOT also be reported as a natural expiry.
    assertEquals(#rec.popupExpire, 0)
end

tests["SetPhase does not report already-expired earlier-phase reminders"] = function()
    local p1 = makeReminder({ id = "p1", time = 30, duration = 5, phase = 1, phaseKey = "1" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ p1 }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- show
    NotesTimer:Tick(30)   -- expire naturally
    assertEquals(#rec.popupExpire, 1)

    NotesTimer:SetPhase(2, 31)
    -- p1 already ran its course; nothing to cancel.
    assertEquals(#rec.cancelPhase, 1)
    assertEquals(#rec.cancelPhase[1], 0)
end

tests["SetPhase cancels multiple unfired earlier-phase reminders together"] = function()
    local a = makeReminder({ id = "a", time = 40, duration = 5, phase = 1, phaseKey = "1" })
    local b = makeReminder({ id = "b", time = 50, duration = 5, phase = 1, phaseKey = "1" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ a, b }), rec.callbacks, 0)

    NotesTimer:Tick(5)
    NotesTimer:SetPhase(2, 100)
    assertEquals(#rec.cancelPhase, 1)
    assertEquals(#rec.cancelPhase[1], 2)
    -- Both a and b present (order-insensitive membership check).
    local seen = {}
    for _, rem in ipairs(rec.cancelPhase[1]) do seen[rem.id] = true end
    assertTrue(seen["a"])
    assertTrue(seen["b"])
end

--------------------------------------------------------------------------------
-- SetPhase: same-phase no-op
--------------------------------------------------------------------------------

tests["same-phase SetPhase is a no-op (no cancel, no re-fire)"] = function()
    local p1 = makeReminder({ id = "p1", time = 30, duration = 5, phase = 1, phaseKey = "1" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ p1 }), rec.callbacks, 0)

    NotesTimer:Tick(5)
    NotesTimer:SetPhase(1, 50)   -- same phase -> dedup, nothing happens
    assertEquals(#rec.cancelPhase, 0)
    assertEquals(#rec.popupShow, 0)
end

tests["same-phase SetPhase leaves phase timing unchanged"] = function()
    -- If the no-op erroneously reset phaseStart to 50, the reminder would fire
    -- late. Confirm timing still references the original phase start (0).
    local p1 = makeReminder({ id = "p1", time = 30, duration = 5, phase = 1, phaseKey = "1" })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ p1 }), rec.callbacks, 0)

    NotesTimer:SetPhase(1, 50)   -- no-op; must NOT move phaseStart to 50
    NotesTimer:Tick(27)          -- remaining 3 relative to original start 0
    assertEquals(#rec.popupShow, 1)
    assertNear(rec.popupShow[1].remaining, 3, 1e-9)
end

--------------------------------------------------------------------------------
-- Relevance filtering (spec 6.4 step 2)
--------------------------------------------------------------------------------

tests["timer skips reminders with relevant == false"] = function()
    local r = makeReminder({ time = 30, duration = 5, countdown = 3,
                             ttsTimer = 3, tts = "true", relevant = false })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- would fire everything if relevant
    NotesTimer:Tick(28)
    NotesTimer:Tick(30)
    assertEquals(#rec.popupShow, 0)
    assertEquals(#rec.audio, 0)
    assertEquals(#rec.countdown, 0)
    assertEquals(#rec.popupExpire, 0)
end

tests["irrelevant reminders are excluded from onCancelPhase"] = function()
    local relevant   = makeReminder({ id = "rel",   time = 40, duration = 5, phase = 1, phaseKey = "1", relevant = true })
    local irrelevant = makeReminder({ id = "irrel", time = 40, duration = 5, phase = 1, phaseKey = "1", relevant = false })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ relevant, irrelevant }), rec.callbacks, 0)

    NotesTimer:Tick(5)
    NotesTimer:SetPhase(2, 100)
    assertEquals(#rec.cancelPhase, 1)
    -- Only the relevant, unfired reminder is reported.
    assertEquals(#rec.cancelPhase[1], 1)
    assertEquals(rec.cancelPhase[1][1], relevant)
end

--------------------------------------------------------------------------------
-- Stop
--------------------------------------------------------------------------------

tests["Stop then Tick fires nothing"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Stop()
    NotesTimer:Tick(27)   -- would show if still running
    NotesTimer:Tick(30)
    assertEquals(#rec.popupShow, 0)
    assertEquals(#rec.popupExpire, 0)
end

tests["Stop then Start yields fresh state and reminders fire again"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- show once
    assertEquals(#rec.popupShow, 1)

    NotesTimer:Stop()

    -- Fresh start with a new recorder; the same reminder must fire again.
    local rec2 = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec2.callbacks, 0)
    NotesTimer:Tick(27)
    assertEquals(#rec2.popupShow, 1)
    assertEquals(rec2.popupShow[1].reminder, r)
end

tests["Stop mid-encounter prevents pending expiry from firing"] = function()
    local r = makeReminder({ time = 30, duration = 5 })
    local rec = makeRecorder()
    NotesTimer:Start(makeSection({ r }), rec.callbacks, 0)

    NotesTimer:Tick(27)   -- shown
    assertEquals(#rec.popupShow, 1)
    NotesTimer:Stop()
    NotesTimer:Tick(30)   -- would expire if running
    assertEquals(#rec.popupExpire, 0)
end

return tests
