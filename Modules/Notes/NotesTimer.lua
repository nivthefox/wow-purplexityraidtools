-- NotesTimer: reminder timing engine and callbacks. A pure state machine; it
-- never calls GetTime(), C_Timer, or any WoW API. Time is injected on every entry
-- point. remaining is phase-relative:
--   remaining = reminder.time - (now - phaseStart)
--
-- Frozen callback signatures (see Notes.lua DATA CONTRACT):
--   onPopupShow(reminder, remaining)
--   onAudio(reminder)
--   onCountdown(reminder, number)
--   onPopupExpire(reminder)
--   onCancelPhase(reminders)
local PRT = PurplexityRaidTools
local NotesTimer = {}
PRT.NotesTimer = NotesTimer

--------------------------------------------------------------------------------
-- Internal state
--------------------------------------------------------------------------------

-- Per-reminder tracking keyed by the reminder table. lastRemaining seeds to
-- reminder.time so the first tick's countdown crossing is measured from the
-- phase's nominal lead, not from +infinity.
local function stateFor(self, reminder)
    local s = self.state[reminder]
    if not s then
        s = {
            shown        = false,
            expired      = false,
            audioFired   = false,
            lastRemaining = reminder.time,
        }
        self.state[reminder] = s
    end
    return s
end

local function currentReminders(self)
    if not self.section or not self.section.reminders then
        return nil
    end
    return self.section.reminders[self.phaseKey]
end

-- Announce every whole-second countdown number crossed by this tick, descending.
-- Fires onCountdown(reminder, N) once per integer N satisfying
--   remaining < N <= lastRemaining  AND  N <= countdown  AND  N >= 1.
local function fireCountdowns(self, reminder, s, remaining)
    local countdown = reminder.countdown
    if not countdown then
        return
    end
    local upper = math.floor(s.lastRemaining)
    if upper > countdown then
        upper = countdown
    end
    for n = upper, 1, -1 do
        if n < s.lastRemaining and n >= remaining then
            self.callbacks.onCountdown(reminder, n)
        end
    end
end

local function evaluate(self, reminder, now)
    local s = stateFor(self, reminder)
    if s.expired then
        return
    end

    local remaining = reminder.time - (now - self.phaseStart)

    -- First seen already at or past its event: the popup window was missed, so
    -- fire nothing and retire. Happens when SetPhase starts a phase into an
    -- already-elapsed schedule, or a first Tick lands past the event.
    if not s.shown and remaining <= 0 then
        s.expired = true
        return
    end

    -- Crossings measure against the previous tick's remaining, so resolve them
    -- before overwriting lastRemaining below.
    fireCountdowns(self, reminder, s, remaining)

    if not s.shown and remaining <= reminder.duration then
        s.shown = true
        self.callbacks.onPopupShow(reminder, remaining)
    end

    if not s.audioFired and reminder.ttsTimer ~= nil and remaining <= reminder.ttsTimer then
        s.audioFired = true
        self.callbacks.onAudio(reminder)
    end

    -- A single tick may both show and expire (jump from before-threshold to
    -- past-event), so this is not an else of the popup branch.
    if s.shown and not s.expired and remaining <= 0 then
        s.expired = true
        self.callbacks.onPopupExpire(reminder)
    end

    s.lastRemaining = remaining
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

-- Resets all tracking so a fresh Start after Stop re-fires every reminder.
function NotesTimer:Start(section, callbacks, now)
    self.section    = section
    self.callbacks  = callbacks
    self.phase      = 1
    self.phaseKey   = "1"
    self.phaseStart = now
    self.state      = {}
    self.running    = true
end

function NotesTimer:Tick(now)
    if not self.running then
        return
    end
    local reminders = currentReminders(self)
    if not reminders then
        return
    end
    for _, reminder in ipairs(reminders) do
        if reminder.relevant then
            evaluate(self, reminder, now)
        end
    end
end

-- Same phase is a strict no-op (dedupe; phaseStart unchanged). A new phase
-- reports every earlier-phase relevant reminder that is unfired OR
-- shown-but-unexpired via onCancelPhase, then restarts timing at `now`.
function NotesTimer:SetPhase(phase, now)
    if not self.running then
        return
    end

    local newKey = tostring(phase)
    if newKey == self.phaseKey then
        return
    end

    local cancelled = {}
    local prior = currentReminders(self)
    if prior then
        for _, reminder in ipairs(prior) do
            if reminder.relevant then
                local s = self.state[reminder]
                if not s then
                    cancelled[#cancelled + 1] = reminder
                elseif not s.expired then
                    cancelled[#cancelled + 1] = reminder
                end
            end
        end
    end
    self.callbacks.onCancelPhase(cancelled)

    self.phase      = phase
    self.phaseKey   = newKey
    self.phaseStart = now
end

function NotesTimer:Stop()
    self.running    = false
    self.section    = nil
    self.callbacks  = nil
    self.phase      = nil
    self.phaseKey   = nil
    self.phaseStart = nil
    self.state      = nil
end
