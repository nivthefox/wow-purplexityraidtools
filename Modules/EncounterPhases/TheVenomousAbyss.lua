local EncounterPhases = PurplexityRaidTools.EncounterPhases

local SSZORAK_PHASES = {
    { id = 1, name = "Sszorak" },
}

local function GetSszorakPhases()
    return SSZORAK_PHASES
end

local function BeginSszorakPhase()
    return {}
end

local function IdentifySszorakPhase()
end

local function IdentifyCoiledAltarPhase()
end

local ENTOMBED_SENTINELS_PHASES = {
    { id = 1, name = "Entombed Sentinels" },
}

local function GetEntombedSentinelsPhases()
    return ENTOMBED_SENTINELS_PHASES
end

local function BeginEntombedSentinelsPhase()
    return {}
end

local function IdentifyEntombedSentinelsPhase()
end

local VASHNIK_PHASES = {
    { id = 1, name = "Vashnik the Malignant" },
}

local function GetVashnikPhases()
    return VASHNIK_PHASES
end

local function BeginVashnikPhase()
    return {}
end

local function IdentifyVashnikPhase()
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

local function IdentifyUlatekPhase()
end

local LOST_EXPLORERS_PHASES = {
    { id = 1, name = "The Lost Explorers" },
}

local function GetLostExplorersPhases()
    return LOST_EXPLORERS_PHASES
end

local function BeginLostExplorersPhase()
    return {}
end

local function IdentifyLostExplorersPhase()
end

EncounterPhases:Register(3420, {
    events = {},
    GetPhases = GetSszorakPhases,
    Begin = BeginSszorakPhase,
    Observe = IdentifySszorakPhase,
})
EncounterPhases:RegisterDraft(3429, IdentifyCoiledAltarPhase)
EncounterPhases:Register(3445, {
    events = {},
    GetPhases = GetEntombedSentinelsPhases,
    Begin = BeginEntombedSentinelsPhase,
    Observe = IdentifyEntombedSentinelsPhase,
})
EncounterPhases:Register(3455, {
    events = {},
    GetPhases = GetVashnikPhases,
    Begin = BeginVashnikPhase,
    Observe = IdentifyVashnikPhase,
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
})
EncounterPhases:RegisterDraft(3492, IdentifyUlatekPhase)
EncounterPhases:Register(3497, {
    events = {},
    GetPhases = GetLostExplorersPhases,
    Begin = BeginLostExplorersPhase,
    Observe = IdentifyLostExplorersPhase,
})
