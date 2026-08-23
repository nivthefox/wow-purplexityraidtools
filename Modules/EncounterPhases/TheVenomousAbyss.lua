local EncounterPhases = PurplexityRaidTools.EncounterPhases

local function IdentifySszorakPhase()
end

local function IdentifyCoiledAltarPhase()
end

local ENTOMBED_SENTINELS_PHASES = {
    { id = 1, name = "Entombed Sentinels" },
}
local SENTINELS_FIRST_STASIS_TIME = 46
local SENTINELS_STASIS_DURATION = 28
local SENTINELS_REPEAT_ACTIVE_DURATION = 91
local SENTINELS_CYCLE_DURATION = SENTINELS_STASIS_DURATION + SENTINELS_REPEAT_ACTIVE_DURATION

local function GetEntombedSentinelsPhases()
    return ENTOMBED_SENTINELS_PHASES
end

local function BeginEntombedSentinelsPhase()
    return {}
end

local function IdentifyEntombedSentinelsPhase()
end

local function GetEntombedSentinelsPhaseOffset(phaseIndex, phase)
    if phaseIndex == 1 then
        if phase.phaseID == 1 and phase.isIntermission == false then
            return 0
        end
        return
    end

    if phaseIndex % 2 == 0 then
        if phase.phaseID ~= 2 or phase.isIntermission ~= true then
            return
        end
        local completedCycles = phaseIndex / 2 - 1
        return SENTINELS_FIRST_STASIS_TIME + completedCycles * SENTINELS_CYCLE_DURATION
    end

    if phase.phaseID ~= 1 or phase.isIntermission ~= false then
        return
    end
    local completedCycles = (phaseIndex - 3) / 2
    return SENTINELS_FIRST_STASIS_TIME
        + SENTINELS_STASIS_DURATION
        + completedCycles * SENTINELS_CYCLE_DURATION
end

local function ProjectEntombedSentinelsWCL(_, phaseIndex, phase, occurrence)
    local offset = GetEntombedSentinelsPhaseOffset(phaseIndex, phase)
    if not offset then
        return
    end
    return {
        phase = 1,
        time = offset + occurrence.time,
    }
end

local NEKZALI_PHASES = {
    { id = 1, name = "Stage One: Soulcoiler Initiation" },
    { id = 2, name = "Intermission: Ritual of Awakening" },
    { id = 3, name = "Stage Two: Uncoiling" },
}

local function GetNekzaliPhases()
    return NEKZALI_PHASES
end

local function BeginNekzaliPhase(_, _, now)
    return {
        phase = 1,
        now = now,
        ritualCastStartedAt = nil,
        ritualChannelReady = false,
        lastChannelStartedAt = nil,
    }
end

local function IdentifyNekzaliPhase(state, event, unit)
    if unit ~= "boss1" or state.phase == 3 then
        return
    end

    local now = state.now()
    if event == "UNIT_SPELLCAST_START" then
        if state.phase == 1 and not state.ritualChannelReady then
            state.ritualCastStartedAt = now
        end
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if state.phase ~= 1 or state.ritualChannelReady or not state.ritualCastStartedAt then
            return
        end
        local castDuration = now - state.ritualCastStartedAt
        state.ritualCastStartedAt = nil
        state.ritualChannelReady = castDuration >= 0 and castDuration < 2
        return
    end

    if event ~= "UNIT_SPELLCAST_CHANNEL_START" then
        return
    end

    if state.phase == 1 then
        if not state.ritualChannelReady then
            return
        end
        state.phase = 2
        state.ritualChannelReady = false
        state.lastChannelStartedAt = now
        return 2
    end

    if now == state.lastChannelStartedAt then
        return
    end
    state.phase = 3
    state.lastChannelStartedAt = now
    return 3
end

local function ProjectNekzaliWCL(_, phaseIndex, _, occurrence)
    return {
        phase = phaseIndex,
        time = occurrence.time,
    }
end

local function IdentifyUlatekPhase()
end

local function IdentifyLostExplorersPhase()
end

EncounterPhases:RegisterDraft(3420, IdentifySszorakPhase)
EncounterPhases:RegisterDraft(3429, IdentifyCoiledAltarPhase)
EncounterPhases:Register(3445, {
    events = {},
    GetPhases = GetEntombedSentinelsPhases,
    Begin = BeginEntombedSentinelsPhase,
    Observe = IdentifyEntombedSentinelsPhase,
    ProjectWCL = ProjectEntombedSentinelsWCL,
})
EncounterPhases:Register(3470, {
    events = {
        "UNIT_SPELLCAST_START",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_CHANNEL_START",
    },
    GetPhases = GetNekzaliPhases,
    Begin = BeginNekzaliPhase,
    Observe = IdentifyNekzaliPhase,
    ProjectWCL = ProjectNekzaliWCL,
})
EncounterPhases:RegisterDraft(3492, IdentifyUlatekPhase)
EncounterPhases:RegisterDraft(3497, IdentifyLostExplorersPhase)
