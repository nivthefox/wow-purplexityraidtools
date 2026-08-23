local EncounterPhases = PurplexityRaidTools.EncounterPhases

local function IdentifySszorakPhase()
end

local function IdentifyCoiledAltarPhase()
end

local function IdentifyGolemsOfUlatekPhase()
end

local function IdentifyNekzaliPhase()
end

local function IdentifyUlatekPhase()
end

local function IdentifyLostExplorersPhase()
end

EncounterPhases:RegisterDraft(3420, IdentifySszorakPhase)
EncounterPhases:RegisterDraft(3429, IdentifyCoiledAltarPhase)
EncounterPhases:RegisterDraft(3445, IdentifyGolemsOfUlatekPhase)
EncounterPhases:RegisterDraft(3470, IdentifyNekzaliPhase)
EncounterPhases:RegisterDraft(3492, IdentifyUlatekPhase)
EncounterPhases:RegisterDraft(3497, IdentifyLostExplorersPhase)
