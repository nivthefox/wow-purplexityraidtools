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

EncounterPhases:Register(3379, {
    events = {},
    GetPhases = GetNymrissaPhases,
    Begin = BeginNymrissaPhase,
    Observe = IdentifyNymrissaPhase,
})
