-- tests/test_combat_timer.lua
-- Exercises CombatTimerCore, the pure combat-duration state machine.
--
-- CombatTimerCore is a PURE state machine: it never calls GetTime(), C_Timer,
-- or any WoW API. Time is injected on every entry point. Mode is injected via
-- a getMode function passed at construction.
--
-- API:
--   CombatTimerCore.new(getMode)    -- getMode() returns "encounter" or "combat"
--   timer:OnEncounterStart(now)     -- fires on ENCOUNTER_START
--   timer:OnEncounterEnd(now)       -- fires on ENCOUNTER_END
--   timer:OnRegenDisabled(now)      -- fires on PLAYER_REGEN_DISABLED
--   timer:OnRegenEnabled(now)       -- fires on PLAYER_REGEN_ENABLED
--   timer:Tick(now)                 -- update elapsed while running
--   timer:Dismiss()                 -- close button clicked (Frozen -> Hidden)
--   timer:Disable()                 -- module disabled mid-run
--   timer:GetState()                -- "hidden" | "running" | "frozen"
--   timer:GetElapsed()              -- elapsed seconds (number)
--   CombatTimerCore.FormatTime(s)   -- pure formatter -> "M:SS" or "H:MM:SS"

dofile("Modules/CombatTimer.lua")

local CombatTimerCore = PRT.CombatTimerCore

local function timerWithMode(initialMode)
    local mode = initialMode or "encounter"
    local function getMode() return mode end
    local function setMode(m) mode = m end
    local timer = CombatTimerCore.new(getMode)
    return timer, setMode
end

local tests = {}

-- ==========================================================================
-- State transitions
-- ==========================================================================

tests["fresh timer state is hidden with elapsed 0"] = function()
    local timer = timerWithMode("encounter")
    assertEquals(timer:GetState(), "hidden")
    assertEquals(timer:GetElapsed(), 0)
end

tests["hidden + encounter start -> running with elapsed 0"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(100)
    assertEquals(timer:GetState(), "running")
    assertEquals(timer:GetElapsed(), 0)
end

tests["running + encounter end -> frozen, elapsed stops"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(100)
    timer:Tick(110)
    assertEquals(timer:GetElapsed(), 10)

    timer:OnEncounterEnd(115)
    assertEquals(timer:GetState(), "frozen")
    assertEquals(timer:GetElapsed(), 15)

    timer:Tick(200)
    assertEquals(timer:GetElapsed(), 15)
end

tests["frozen + encounter start -> running with elapsed reset to 0"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:Tick(30)
    timer:OnEncounterEnd(30)
    assertEquals(timer:GetState(), "frozen")
    assertEquals(timer:GetElapsed(), 30)

    timer:OnEncounterStart(100)
    assertEquals(timer:GetState(), "running")
    assertEquals(timer:GetElapsed(), 0)
end

tests["frozen + dismiss -> hidden"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:OnEncounterEnd(10)
    assertEquals(timer:GetState(), "frozen")

    timer:Dismiss()
    assertEquals(timer:GetState(), "hidden")
end

tests["hidden via dismiss + encounter start -> running with elapsed 0"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:OnEncounterEnd(10)
    timer:Dismiss()
    assertEquals(timer:GetState(), "hidden")

    timer:OnEncounterStart(500)
    assertEquals(timer:GetState(), "running")
    assertEquals(timer:GetElapsed(), 0)
end

-- ==========================================================================
-- All-combat mode state transitions
-- ==========================================================================

tests["hidden + regen disabled -> running in combat mode"] = function()
    local timer = timerWithMode("combat")
    timer:OnRegenDisabled(50)
    assertEquals(timer:GetState(), "running")
    assertEquals(timer:GetElapsed(), 0)
end

tests["running + regen enabled -> frozen in combat mode"] = function()
    local timer = timerWithMode("combat")
    timer:OnRegenDisabled(0)
    timer:Tick(20)
    timer:OnRegenEnabled(25)
    assertEquals(timer:GetState(), "frozen")
    assertEquals(timer:GetElapsed(), 25)
end

tests["frozen + regen disabled -> running with elapsed reset in combat mode"] = function()
    local timer = timerWithMode("combat")
    timer:OnRegenDisabled(0)
    timer:Tick(10)
    timer:OnRegenEnabled(10)
    assertEquals(timer:GetState(), "frozen")
    assertEquals(timer:GetElapsed(), 10)

    timer:OnRegenDisabled(12)
    assertEquals(timer:GetState(), "running")
    assertEquals(timer:GetElapsed(), 0)
end

-- ==========================================================================
-- Event filtering
-- ==========================================================================

tests["encounter mode ignores regen disabled"] = function()
    local timer = timerWithMode("encounter")
    timer:OnRegenDisabled(0)
    assertEquals(timer:GetState(), "hidden")
end

tests["encounter mode ignores regen enabled"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:OnRegenEnabled(10)
    assertEquals(timer:GetState(), "running")
end

tests["combat mode ignores encounter start"] = function()
    local timer = timerWithMode("combat")
    timer:OnEncounterStart(0)
    assertEquals(timer:GetState(), "hidden")
end

tests["combat mode ignores encounter end"] = function()
    local timer = timerWithMode("combat")
    timer:OnRegenDisabled(0)
    timer:OnEncounterEnd(10)
    assertEquals(timer:GetState(), "running")
end

-- ==========================================================================
-- Time formatting
-- ==========================================================================

tests["format 0 seconds -> 0:00"] = function()
    assertEquals(CombatTimerCore.FormatTime(0), "0:00")
end

tests["format 62 seconds -> 1:02"] = function()
    assertEquals(CombatTimerCore.FormatTime(62), "1:02")
end

tests["format 3599 seconds -> 59:59"] = function()
    assertEquals(CombatTimerCore.FormatTime(3599), "59:59")
end

tests["format 3600 seconds -> 1:00:00"] = function()
    assertEquals(CombatTimerCore.FormatTime(3600), "1:00:00")
end

tests["format 3661 seconds -> 1:01:01"] = function()
    assertEquals(CombatTimerCore.FormatTime(3661), "1:01:01")
end

tests["format fractional seconds floors to whole seconds"] = function()
    assertEquals(CombatTimerCore.FormatTime(62.7), "1:02")
    assertEquals(CombatTimerCore.FormatTime(0.9), "0:00")
    assertEquals(CombatTimerCore.FormatTime(3599.99), "59:59")
end

-- ==========================================================================
-- Tick behavior
-- ==========================================================================

tests["tick updates elapsed while running"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(100)
    timer:Tick(105)
    assertEquals(timer:GetElapsed(), 5)
    timer:Tick(142)
    assertEquals(timer:GetElapsed(), 42)
end

tests["tick is a no-op when hidden"] = function()
    local timer = timerWithMode("encounter")
    timer:Tick(999)
    assertEquals(timer:GetState(), "hidden")
    assertEquals(timer:GetElapsed(), 0)
end

tests["tick is a no-op when frozen"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:OnEncounterEnd(30)
    local frozenElapsed = timer:GetElapsed()

    timer:Tick(999)
    assertEquals(timer:GetState(), "frozen")
    assertEquals(timer:GetElapsed(), frozenElapsed)
end

-- ==========================================================================
-- Mode change mid-combat
-- ==========================================================================

tests["mode change mid-combat: encounter end still freezes"] = function()
    local timer, setMode = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:Tick(10)

    setMode("combat")

    timer:OnEncounterEnd(20)
    assertEquals(timer:GetState(), "frozen")
    assertEquals(timer:GetElapsed(), 20)
end

tests["mode change mid-combat: regen enabled does not freeze"] = function()
    local timer, setMode = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:Tick(10)

    setMode("combat")

    timer:OnRegenEnabled(20)
    assertEquals(timer:GetState(), "running")
end

tests["after mode change while running, next start uses new mode"] = function()
    local timer, setMode = timerWithMode("encounter")
    timer:OnEncounterStart(0)

    setMode("combat")

    timer:OnEncounterEnd(10)
    assertEquals(timer:GetState(), "frozen")

    timer:OnEncounterStart(100)
    assertEquals(timer:GetState(), "frozen")

    timer:OnRegenDisabled(100)
    assertEquals(timer:GetState(), "running")
end

-- ==========================================================================
-- Module lifecycle
-- ==========================================================================

tests["disable while running resets to hidden"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:Tick(10)
    assertEquals(timer:GetState(), "running")

    timer:Disable()
    assertEquals(timer:GetState(), "hidden")
    assertEquals(timer:GetElapsed(), 0)
end

tests["re-enable after disable mid-combat starts fresh"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:Tick(30)
    timer:Disable()

    assertEquals(timer:GetState(), "hidden")
    assertEquals(timer:GetElapsed(), 0)

    timer:OnEncounterStart(500)
    assertEquals(timer:GetState(), "running")
    assertEquals(timer:GetElapsed(), 0)
end

tests["disable while frozen resets to hidden"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:OnEncounterEnd(30)
    assertEquals(timer:GetState(), "frozen")

    timer:Disable()
    assertEquals(timer:GetState(), "hidden")
    assertEquals(timer:GetElapsed(), 0)
end

-- ==========================================================================
-- Dismiss edge cases
-- ==========================================================================

tests["dismiss from hidden is a no-op"] = function()
    local timer = timerWithMode("encounter")
    timer:Dismiss()
    assertEquals(timer:GetState(), "hidden")
end

tests["dismiss from running is a no-op"] = function()
    local timer = timerWithMode("encounter")
    timer:OnEncounterStart(0)
    timer:Dismiss()
    assertEquals(timer:GetState(), "running")
end

return tests
