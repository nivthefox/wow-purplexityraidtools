local EncounterPhases = PurplexityRaidTools.EncounterPhases

local NYMRISSA_PHASES = {
    { id = 1, name = "Nymrissa Wavecaller" },
}

local function GetNymrissaPhases()
    return NYMRISSA_PHASES
end

local function BeginNymrissaPhase()
    return {}
end

local function IdentifyNymrissaPhase()
end

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

local TWIN_FANGS_PHASES = {
    { id = 1, name = "The Twin Fangs" },
}

local function GetTwinFangsPhases()
    return TWIN_FANGS_PHASES
end

local function BeginTwinFangsPhase()
    return {}
end

local function IdentifyTwinFangsPhase()
end

local COILED_ALTAR_PHASES = {
    { id = 1, name = "Stage One: Serpent's Bargain" },
    { id = 2, name = "Stage Two: Usurper's Reprisal" },
    { id = 3, name = "Intermission: The Claimed Vessel" },
    { id = 4, name = "Stage Three: Coiled Union" },
}

local function GetCoiledAltarPhases()
    return COILED_ALTAR_PHASES
end

local function BeginCoiledAltarPhase()
    return {
        phase = 1,
        axegrinderCount = 1,
        coiledAltarCount = 1,
        timelineEvents = {},
    }
end

local function RoundTimelineDuration(duration)
    return math.floor(duration + 0.5)
end

local function RememberCoiledAltarTimelineEvent(state, eventInfo)
    if type(eventInfo) ~= "table"
        or eventInfo.source ~= 0
        or type(eventInfo.id) ~= "number"
        or type(eventInfo.duration) ~= "number"
    then
        return
    end

    local duration = RoundTimelineDuration(eventInfo.duration)
    if state.phase == 1 then
        if duration == 12 then
            state.axegrinderCount = state.axegrinderCount + 1
        elseif duration == 85 then
            state.coiledAltarCount = state.coiledAltarCount + 1
            state.timelineEvents[eventInfo.id] = {
                nextPhase = 2,
                cycle = state.coiledAltarCount,
            }
        end
    elseif state.phase == 2 and duration == 70 then
        state.timelineEvents[eventInfo.id] = { nextPhase = 3 }
    end
end

local function CanceledCoiledAltarTimelineEvent(state, eventID)
    if not C_EncounterTimeline or type(C_EncounterTimeline.GetEventState) ~= "function" then
        return
    end
    if C_EncounterTimeline.GetEventState(eventID) ~= 3 then
        return
    end

    local timelineEvent = state.timelineEvents[eventID]
    state.timelineEvents[eventID] = nil
    if not timelineEvent or timelineEvent.nextPhase <= state.phase then
        return
    end
    if timelineEvent.nextPhase == 2 and state.axegrinderCount > timelineEvent.cycle then
        return
    end

    state.phase = timelineEvent.nextPhase
    return timelineEvent.nextPhase
end

local function IdentifyCoiledAltarPhase(state, event, value)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        RememberCoiledAltarTimelineEvent(state, value)
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        state.timelineEvents[value] = nil
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        return CanceledCoiledAltarTimelineEvent(state, value)
    end
    if event ~= "UNIT_SPELLCAST_CHANNEL_STOP" or value ~= "boss2" or state.phase ~= 3 then
        return
    end

    state.phase = 4
    return 4
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

local ULATEK_PHASES = {
    { id = 1, name = "Stage One: Fury of the Serpent Mother" },
    { id = 2, name = "Stage Two: Children of the Doomscale" },
    { id = 3, name = "Intermission: The Shattering" },
    { id = 4, name = "Stage Three: Ula'tek's Ascension" },
}

local function GetUlatekPhases()
    return ULATEK_PHASES
end

local function BeginUlatekPhase()
    return {
        phase = 1,
        checkStage = false,
        rageEvents = {},
    }
end

local function RememberUlatekTimelineEvent(state, eventInfo)
    if type(eventInfo) ~= "table"
        or eventInfo.source ~= 0
        or type(eventInfo.id) ~= "number"
        or type(eventInfo.duration) ~= "number"
    then
        return
    end

    local duration = RoundTimelineDuration(eventInfo.duration)
    if state.phase == 1 then
        if state.checkStage and duration == 118 then
            state.phase = 2
            return 2
        end
        if duration == 129 or duration == 130 then
            state.rageEvents[eventInfo.id] = true
        end
        return
    end
    if state.phase == 2 and duration == 10 then
        state.phase = 3
        return 3
    end
    if state.phase == 3 and (duration == 230 or duration == 235) then
        state.phase = 4
        return 4
    end
end

local function ChangedUlatekTimelineEvent(state, eventID)
    if not state.rageEvents[eventID]
        or not C_EncounterTimeline
        or type(C_EncounterTimeline.GetEventState) ~= "function"
    then
        return
    end

    local eventState = C_EncounterTimeline.GetEventState(eventID)
    if eventState == 3 then
        state.rageEvents[eventID] = nil
        return
    end
    if eventState ~= 2 then
        return
    end

    state.rageEvents[eventID] = nil
    state.checkStage = true
end

local function TargetabilityChangedUlatekPhase(state, unit)
    if state.phase ~= 1
        or not state.checkStage
        or unit ~= "boss1"
        or type(UnitCanAttack) ~= "function"
        or UnitCanAttack("player", unit)
    then
        return
    end

    state.phase = 2
    state.checkStage = false
    return 2
end

local function IdentifyUlatekPhase(state, event, value)
    if event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        return RememberUlatekTimelineEvent(state, value)
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_REMOVED" then
        state.rageEvents[value] = nil
        return
    end
    if event == "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED" then
        return ChangedUlatekTimelineEvent(state, value)
    end
    if event == "UNIT_TARGETABLE_CHANGED" then
        return TargetabilityChangedUlatekPhase(state, value)
    end
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

EncounterPhases:Register(3379, {
    events = {},
    GetPhases = GetNymrissaPhases,
    Begin = BeginNymrissaPhase,
    Observe = IdentifyNymrissaPhase,
})
EncounterPhases:Register(3420, {
    events = {},
    GetPhases = GetSszorakPhases,
    Begin = BeginSszorakPhase,
    Observe = IdentifySszorakPhase,
})
EncounterPhases:Register(3421, {
    events = {},
    GetPhases = GetTwinFangsPhases,
    Begin = BeginTwinFangsPhase,
    Observe = IdentifyTwinFangsPhase,
})
EncounterPhases:Register(3429, {
    events = {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        { event = "UNIT_SPELLCAST_CHANNEL_STOP", unit = "boss2" },
    },
    GetPhases = GetCoiledAltarPhases,
    Begin = BeginCoiledAltarPhase,
    Observe = IdentifyCoiledAltarPhase,
})
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
EncounterPhases:Register(3492, {
    events = {
        "ENCOUNTER_TIMELINE_EVENT_ADDED",
        "ENCOUNTER_TIMELINE_EVENT_REMOVED",
        "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
        { event = "UNIT_TARGETABLE_CHANGED", unit = "boss1" },
    },
    GetPhases = GetUlatekPhases,
    Begin = BeginUlatekPhase,
    Observe = IdentifyUlatekPhase,
})
EncounterPhases:Register(3497, {
    events = {},
    GetPhases = GetLostExplorersPhases,
    Begin = BeginLostExplorersPhase,
    Observe = IdentifyLostExplorersPhase,
})
