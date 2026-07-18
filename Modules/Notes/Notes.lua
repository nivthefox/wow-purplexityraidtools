-- Notes: timed boss note reminders. Owns storage/selection, module registration,
-- defaults, and lifecycle.
local PRT = PurplexityRaidTools
local Notes = {}
PRT.Notes = Notes
PRT:RegisterModule("notes", Notes)

-- ============================================================================
-- FROZEN DATA CONTRACT (rev 2, spec 21a81ca) — do not change without Niv
--
-- A note is ONE encounter's plan. NotesParser:Parse(text) returns:
--   note, nil  on success:
--     { encounterID(number or nil),  -- nil = inert note (no metadata line)
--       name, difficulty,            -- "Normal"|"Heroic"|"Mythic"|nil (nil = any)
--       reminders = { [phaseKey(string)] = array sorted by time },
--       lines = ordered { type = "reminder"|"freeform", ... } }  -- note-frame order
--   nil, errMessage  on invalid input (more than one EncounterID: line):
--     errMessage = "A note may only contain one encounter. Use a separate note per encounter."
--   Content before the metadata line (or in an inert note) is kept as freeform.
--   Timed lines before the metadata line are freeform, not reminders.
--   Reminder = { time, tag, text, spellID, phase(number), phaseKey(string),
--                duration, displayType, tts, ttsTimer, countdown, sound,
--                bossSpell, colors, relevant(bool, set by tag matcher) }
--   phaseKey is tostring(phase) ("2.5") to avoid float table-key identity.
--   duration and ttsTimer are clamped to time at parse (spec 9.2.1).
--
-- NotesTags:MarkRelevance(note, ctx) — takes the single note, not a dict.
--
-- Note applies to a live encounter iff note.encounterID == liveEncounterID
-- (numeric) AND (note.difficulty == nil OR note.difficulty == liveDifficultyString).
--
-- Timer callbacks (NotesTimer, unchanged):
--   onPopupShow(reminder, remaining)
--   onAudio(reminder)
--   onCountdown(reminder, number)
--   onPopupExpire(reminder)
--   onCancelPhase(reminders)
-- ============================================================================

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.notes = {
    enabled = true,
    -- activeNote is intentionally omitted: nil keys do not exist, and a nil
    -- default would be resurrected as a real key in every profile by
    -- MergeDefaults. "No active note" is simply the absence of this key.
    savedNotes = {},  -- NEVER seed a sample note here: MergeDefaults would
                      -- deep-copy it into every profile permanently.
    display = {
        showOnlyMine = true,
        hideExpired = true,
        hideMode = "Immediately",  -- "Immediately" | "Fade" | "Never"
        countdownColor = { r = 0, g = 1, b = 0, a = 1 },
        fontFace = "Friz Quadrata TT",
        fontSize = 12,
        fontOutline = "NONE",
        backgroundColor = { r = 0, g = 0, b = 0, a = 1 },
        backgroundOpacity = 0.7,
    },
    popups = {
        enabled = true,
        scale = 1,
        growDirection = "Down",
        ttsEnabled = true,
        soundsEnabled = true,
    },
    locked = true,
    contentTypes = {
        openWorld = false,
        dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
        raid = { lfr = true, normal = true, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    },
    positions = {},
}

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local function GetNotesStore()
    local profile = PRT.Profiles:GetCurrent()
    if not profile.notes then
        profile.notes = {}
    end
    if not profile.notes.savedNotes then
        profile.notes.savedNotes = {}
    end
    return profile.notes
end

-- Single-encounter validation is delegated to NotesParser:Parse. When the parser
-- is absent (headless harness only; TOC order guarantees it in-game) the note is
-- saved without validation rather than erroring.
function Notes:SaveNote(name, text)
    if not name then return false end
    if PRT.NotesParser then
        local _, err = PRT.NotesParser:Parse(text or "")
        if err then
            return false, err
        end
    end
    local store = GetNotesStore()
    store.savedNotes[name] = { text = text }
    return true
end

function Notes:DeleteNote(name)
    local store = GetNotesStore()
    if not store.savedNotes[name] then return false end
    store.savedNotes[name] = nil
    if store.activeNote == name then
        store.activeNote = nil
    end
    return true
end

function Notes:RenameNote(oldName, newName)
    if not oldName or not newName then return false end
    local store = GetNotesStore()
    if not store.savedNotes[oldName] then return false end
    if store.savedNotes[newName] then return false end
    store.savedNotes[newName] = store.savedNotes[oldName]
    store.savedNotes[oldName] = nil
    if store.activeNote == oldName then
        store.activeNote = newName
    end
    return true
end

function Notes:ActivateNote(name)
    local store = GetNotesStore()
    if name ~= nil and not store.savedNotes[name] then
        return false
    end
    store.activeNote = name
    self:OnActiveNoteChanged()
    return true
end

function Notes:GetActiveNote()
    local store = GetNotesStore()
    local name = store.activeNote
    if not name then return nil end
    return name, store.savedNotes[name]
end

--------------------------------------------------------------------------------
-- Runtime state (encounter session)
--------------------------------------------------------------------------------

local activeNote = nil
local ticker = nil
local encounterPhase = 1
local phaseStart = nil
local bossModHooked = false
local warnedNoBossMod = false
local testRunning = false

-- difficultyID -> capitalized note-vocabulary difficulty string. The lowercase
-- content-type strings from GetCurrentContentType must NEVER be used here.
local DIFFICULTY_ID_TO_NOTE_STRING = {
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR",
}

-- Reject any WoW event/callback argument that is a protected "secret" value
-- (post-Midnight combat data restrictions), mirroring MRT's boss-mod guard.
local function isSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

--------------------------------------------------------------------------------
-- Player context
--------------------------------------------------------------------------------

-- Tanks count as melee here; DPS/healer classification defers to IsMeleeSpec.
local function BuildPlayerCtx()
    local name = UnitName("player")
    local _, _, classID = UnitClass("player")
    local role = UnitGroupRolesAssigned("player")

    local specID
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        specID = GetSpecializationInfo(specIndex)
    end

    local subgroup
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unitName, _, subGroup = GetRaidRosterInfo(i)
            if unitName and name and unitName == name then
                subgroup = subGroup
                break
            end
        end
    else
        subgroup = 1
    end

    local isMelee = role == "TANK" or PRT.NotesTags.IsMeleeSpec(specID)

    return {
        name = name,
        role = role,
        classID = classID,
        specID = specID,
        subgroup = subgroup,
        isMelee = isMelee,
    }
end

function Notes:MarkRelevance(note)
    if not (note and PRT.NotesTags) then
        return
    end
    PRT.NotesTags.MarkRelevance(note, BuildPlayerCtx())
end

-- Content-only: never changes frame visibility. Safe with no active note.
local function RefreshRelevance()
    if activeNote then
        PRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    end
    PRT.NotesFrame:RebuildRoster()
    PRT.NotesFrame:SetNote(activeNote)
end

--------------------------------------------------------------------------------
-- Encounter applicability
--------------------------------------------------------------------------------

local function NoteApplies(note, encounterID, difficultyString)
    if not note or note.encounterID ~= encounterID then
        return false
    end
    return note.difficulty == nil or note.difficulty == difficultyString
end

--------------------------------------------------------------------------------
-- Timer callbacks (frozen signatures)
--------------------------------------------------------------------------------

local timerCallbacks = {
    onPopupShow = function(reminder, remaining)
        PRT.NotesPopups:Show(reminder, remaining)
    end,
    onAudio = function(reminder)
        PRT.NotesPopups:PlayAudio(reminder)
    end,
    onCountdown = function(reminder, number)
        PRT.NotesPopups:AnnounceCountdown(number)
    end,
    onPopupExpire = function(reminder)
        PRT.NotesPopups:Expire(reminder)
    end,
    onCancelPhase = function(reminders)
        for _, reminder in ipairs(reminders) do
            PRT.NotesPopups:Dismiss(reminder)
        end
    end,
}

--------------------------------------------------------------------------------
-- Boss-mod phase tracking
--------------------------------------------------------------------------------

local function ApplyPhase(stage)
    if isSecret(stage) then
        return
    end
    stage = tonumber(stage)
    if not stage then
        return
    end
    encounterPhase = stage
    phaseStart = GetTime()
    PRT.NotesTimer:SetPhase(stage, phaseStart)
end

-- Registers exactly once. Callback arg order follows MRT: BigWigs
-- (event, addon, stage); DBM (event, addon, modId, stage, ...). Every arg is
-- guarded against secret values.
local function HookBossMods()
    if bossModHooked then
        return
    end

    local hooked = false

    if type(BigWigsLoader) == "table" and BigWigsLoader.RegisterMessage then
        BigWigsLoader.RegisterMessage(Notes, "BigWigs_SetStage", function(_, addon, stage)
            if isSecret(addon) or isSecret(stage) then
                return
            end
            ApplyPhase(stage)
        end)
        hooked = true
    end

    if type(DBM) == "table" and DBM.RegisterCallback then
        DBM:RegisterCallback("DBM_SetStage", function(_, addon, modId, stage)
            if isSecret(addon) or isSecret(modId) or isSecret(stage) then
                return
            end
            ApplyPhase(stage)
        end)
        hooked = true
    end

    bossModHooked = hooked
end

--------------------------------------------------------------------------------
-- Encounter lifecycle
--------------------------------------------------------------------------------

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function OnEncounterStart(encounterID, difficultyID)
    if isSecret(encounterID) or isSecret(difficultyID) then
        return
    end

    local settings = PRT:GetSetting("notes")
    if not settings or not PRT.IsContentTypeEnabled(settings.contentTypes) then
        return
    end

    encounterID = tonumber(encounterID)
    if not encounterID then
        return
    end

    local difficultyString = DIFFICULTY_ID_TO_NOTE_STRING[tonumber(difficultyID)]
    if not NoteApplies(activeNote, encounterID, difficultyString) then
        return
    end

    if testRunning then
        Notes:TestStop()
    end

    if not (type(BigWigsLoader) == "table" or type(DBM) == "table") then
        if not warnedNoBossMod then
            warnedNoBossMod = true
            print("PRT: No boss mod (BigWigs or DBM) detected. Only phase 1 reminders will fire.")
        end
    end

    encounterPhase = 1
    phaseStart = GetTime()

    PRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    PRT.NotesFrame:SetNote(activeNote)
    PRT.NotesFrame:Show()
    PRT.NotesTimer:Start(activeNote, timerCallbacks, phaseStart)

    StopTicker()
    ticker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        PRT.NotesTimer:Tick(now)
        PRT.NotesFrame:TickUpdate(now, phaseStart, encounterPhase)
    end)
end

local function OnEncounterEnd()
    StopTicker()
    PRT.NotesTimer:Stop()
    PRT.NotesPopups:DismissAll()

    local settings = PRT:GetSetting("notes")
    local hideMode = settings and settings.display and settings.display.hideMode
    PRT.NotesFrame:OnEncounterEnd(hideMode)
end

--------------------------------------------------------------------------------
-- Test mode
--
-- Starts the active note's timer without an encounter event, bypassing
-- encounterID matching and content-type gates. The note frame shows, popups
-- fire, and the ticker runs exactly as in a real encounter. TestStop tears
-- everything down.
--------------------------------------------------------------------------------

function Notes:TestStart()
    if testRunning then
        return false
    end
    if not activeNote then
        return false
    end

    testRunning = true
    encounterPhase = 1
    phaseStart = GetTime()

    PRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    PRT.NotesFrame:SetNote(activeNote)
    PRT.NotesFrame:Show()
    PRT.NotesTimer:Start(activeNote, timerCallbacks, phaseStart)

    local maxTime = 0
    for _, bucket in pairs(activeNote.reminders) do
        for _, reminder in ipairs(bucket) do
            if reminder.time > maxTime then
                maxTime = reminder.time
            end
        end
    end

    StopTicker()
    local self_ = self
    ticker = C_Timer.NewTicker(1, function()
        local now = GetTime()
        PRT.NotesTimer:Tick(now)
        PRT.NotesFrame:TickUpdate(now, phaseStart, encounterPhase)

        if now - phaseStart >= maxTime then
            self_:TestStop()
        end
    end)

    return true
end

function Notes:TestStop()
    if not testRunning then
        return
    end
    testRunning = false

    StopTicker()
    PRT.NotesTimer:Stop()
    PRT.NotesPopups:DismissAll()
    PRT.NotesFrame:OnEncounterEnd("Immediately")

    if self.onTestStopped then
        self.onTestStopped()
    end
end

function Notes:IsTestRunning()
    return testRunning
end

--------------------------------------------------------------------------------
-- Broadcast send seam
--
-- Both entry points re-check the group/privilege gates at call time and HARD-ban
-- sending while in combat, so no code path can broadcast mid-pull. Each returns
-- ok(boolean), reason(string when refused) for the config UI's tooltip.
-- InCombatLockdown is guarded for headless safety, mirroring isSecret.
--------------------------------------------------------------------------------

local SEND_MSG_TYPE = "note"
local CLEAR_MSG_TYPE = "clear"
local REASON_NO_PRIVILEGE = "Requires raid leader or assistant."
local REASON_COMBAT = "Cannot send during combat."
local REASON_NO_NOTE = "No note selected."

local function InCombat()
    return InCombatLockdown ~= nil and InCombatLockdown()
end

-- Solo sending is legal: it is a send-to-self (activate + show locally, no
-- wire). In a group the sender's own client activates via the RAID channel's
-- self-echo through the receive path. Combat is a hard ban either way.
local function BroadcastGate()
    if IsInGroup() and not PRT.Comms:IsSenderPrivileged(UnitName("player")) then
        return false, REASON_NO_PRIVILEGE
    end
    if InCombat() then
        return false, REASON_COMBAT
    end
    return true
end

function Notes:BroadcastNote(name)
    local ok, reason = BroadcastGate()
    if not ok then
        return false, reason
    end
    local note = name and GetNotesStore().savedNotes[name]
    if not note then
        return false, REASON_NO_NOTE
    end
    if not IsInGroup() then
        self:ActivateNote(name)
        PRT.NotesFrame:Show()
        return true
    end
    PRT.Comms:Send(SEND_MSG_TYPE, { name = name, text = note.text }, "RAID")
    return true
end

function Notes:BroadcastClear()
    local ok, reason = BroadcastGate()
    if not ok then
        return false, reason
    end
    if not IsInGroup() then
        self:ActivateNote(nil)
        PRT.NotesFrame:Hide()
        return true
    end
    PRT.Comms:Send(CLEAR_MSG_TYPE, {}, "RAID")
    return true
end

--------------------------------------------------------------------------------
-- Comms receive handlers
--------------------------------------------------------------------------------

local function OnNoteReceived(data, sender)
    if type(data) ~= "table" or not data.name then
        return
    end
    if not PRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    -- A note that fails SaveNote's validation is rejected silently. A compliant
    -- PRT sender can never produce one.
    if not Notes:SaveNote(data.name, data.text) then
        return
    end
    Notes:ActivateNote(data.name)
    print("PRT: Received note: " .. data.name .. " from " .. sender)
    PRT.NotesFrame:Show()
end

local function OnClearReceived(_, sender)
    if not PRT.Comms:IsSenderPrivileged(sender) then
        return
    end
    Notes:ActivateNote(nil)
    PRT.NotesFrame:Hide()
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

local function OnEvent(_, event, arg1, arg2, arg3)
    if event == "ENCOUNTER_START" then
        HookBossMods()
        OnEncounterStart(arg1, arg3)
    elseif event == "ENCOUNTER_END" then
        OnEncounterEnd()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        RefreshRelevance()
    elseif event == "ADDON_LOADED" then
        HookBossMods()
    end
end

-- Reparse and remark relevance. The sibling modules are absent under the
-- headless harness, so parsing is skipped there.
function Notes:OnActiveNoteChanged()
    if not (PRT.NotesParser and PRT.NotesTags) then
        return
    end
    local _, stored = self:GetActiveNote()
    if not stored then
        activeNote = nil
        PRT.NotesFrame:SetNote(nil)
        return
    end
    -- Stored notes are pre-validated by SaveNote, so err is theoretical; treat
    -- it as no note.
    local parsed, err = PRT.NotesParser:Parse(stored.text or "")
    if err then
        activeNote = nil
        PRT.NotesFrame:SetNote(nil)
        return
    end
    activeNote = parsed
    PRT.NotesTags.MarkRelevance(activeNote, BuildPlayerCtx())
    PRT.NotesFrame:SetNote(activeNote)
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function Notes:Initialize()
    PRT.NotesFrame:Init()
    PRT.NotesPopups:Init()
end

function Notes:OnEnable()
    self.eventFrame:RegisterEvent("ENCOUNTER_START")
    self.eventFrame:RegisterEvent("ENCOUNTER_END")
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    PRT.Comms:RegisterHandler("note", OnNoteReceived)
    PRT.Comms:RegisterHandler("clear", OnClearReceived)

    HookBossMods()
    self:OnActiveNoteChanged()
    PRT.NotesFrame:RebuildRoster()
end

function Notes:OnDisable()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)

    testRunning = false
    StopTicker()
    PRT.NotesTimer:Stop()
    PRT.NotesPopups:DismissAll()
    PRT.NotesFrame:Hide()
end
