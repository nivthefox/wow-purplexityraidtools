local PRT = PurplexityRaidTools
local ReadyScreen = {}
PRT.ReadyScreen = ReadyScreen
PRT:RegisterModule("readyScreen", ReadyScreen)

PRT.defaults.readyScreen = {
    enabled = true,
    autoDismiss = false,
}

function ReadyScreen.GetDisplayedState(isOffline, isDead, responseState)
    return nil
end

function ReadyScreen.FinalizeResponse(responseState)
    return nil
end

function ReadyScreen.SortRoster(members)
    return nil
end

function ReadyScreen.ClassifyVersion(memberVersion, rlVersion)
    return nil
end

function ReadyScreen:IsActivatable()
    return IsInRaid()
end

function ReadyScreen:Initialize()
end
