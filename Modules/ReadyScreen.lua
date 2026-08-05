local PRT = PurplexityRaidTools
local ReadyScreen = {}
PRT.ReadyScreen = ReadyScreen
PRT:RegisterModule("readyScreen", ReadyScreen)

PRT.defaults.readyScreen = {
    enabled = true,
    autoDismiss = false,
}

function ReadyScreen.GetDisplayedState(isOffline, isDead, responseState)
    if isOffline then
        return "offline"
    end
    if isDead then
        return "dead"
    end
    return responseState
end

function ReadyScreen.FinalizeResponse(responseState)
    if responseState == "pending" then
        return "notready"
    end
    return responseState
end

function ReadyScreen.SortRoster(members)
    table.sort(members, function(a, b)
        if a.name == nil then return false end
        if b.name == nil then return true end
        return a.name < b.name
    end)
    return members
end

function ReadyScreen.ClassifyVersion(memberVersion, rlVersion)
    if memberVersion == nil then
        return "missing"
    end
    if rlVersion == nil then
        return "current"
    end
    if memberVersion < rlVersion then
        return "outdated"
    end
    return "current"
end

function ReadyScreen:IsActivatable()
    return IsInRaid()
end

function ReadyScreen:Initialize()
end
