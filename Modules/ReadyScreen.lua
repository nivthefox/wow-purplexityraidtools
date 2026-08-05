local PRT = PurplexityRaidTools
local ReadyScreen = {}
PRT.ReadyScreen = ReadyScreen
PRT:RegisterModule("readyScreen", ReadyScreen)

PRT.defaults.readyScreen = {
    enabled = true,
    autoDismiss = false,
    position = nil,
}

local mode = "hidden"
local responses = {}
local autoDismissTimer = nil
local readyCheckActive = false
local auraRefreshPending = false

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

function ReadyScreen:GetMode()
    return mode
end

function ReadyScreen:GetResponses()
    return responses
end

function ReadyScreen:IsReadyCheckActive()
    return readyCheckActive
end

function ReadyScreen:ShowAudit()
    if readyCheckActive then
        return
    end
    if not IsInRaid() then
        return
    end
    local settings = PRT:GetSetting("readyScreen")
    if not settings or not settings.enabled then
        return
    end

    mode = "audit"
    if PRT.ReadyScreenFrame then
        PRT.ReadyScreenFrame:Show("audit")
    end
end

function ReadyScreen:ShowReadyCheck()
    if mode ~= "hidden" then
        ReadyScreen:Close()
    end

    if autoDismissTimer then
        autoDismissTimer:Cancel()
        autoDismissTimer = nil
    end

    responses = {}
    for guid in pairs(PRT.GroupInspect.members) do
        responses[guid] = "pending"
    end

    mode = "readycheck"
    readyCheckActive = true

    if PRT.ReadyScreenFrame then
        PRT.ReadyScreenFrame:Show("readycheck")
    end
end

function ReadyScreen:Close()
    if autoDismissTimer then
        autoDismissTimer:Cancel()
        autoDismissTimer = nil
    end
    if PRT.ReadyScreenFrame then
        PRT.ReadyScreenFrame:Hide()
    end
    mode = "hidden"
end

function ReadyScreen:OnReadyCheckConfirm(unit, isReady)
    local guid = UnitGUID(unit)
    if not guid then
        return
    end
    if not responses[guid] then
        return
    end

    responses[guid] = isReady and "ready" or "notready"

    if PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
        PRT.ReadyScreenFrame:Refresh()
    end
end

function ReadyScreen:OnReadyCheckFinished()
    readyCheckActive = false

    for guid, state in pairs(responses) do
        responses[guid] = ReadyScreen.FinalizeResponse(state)
    end

    if mode == "hidden" then
        return
    end

    mode = "completed"

    if PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
        PRT.ReadyScreenFrame:Refresh()
    end

    local settings = PRT:GetSetting("readyScreen")
    if settings and settings.autoDismiss then
        autoDismissTimer = C_Timer.NewTimer(5, function()
            autoDismissTimer = nil
            ReadyScreen:Close()
        end)
    end
end

function ReadyScreen:IsActivatable()
    return IsInRaid()
end

function ReadyScreen:Initialize()
    PRT.GroupInspect:Listen(function()
        if mode ~= "hidden" and PRT.ReadyScreenFrame then
            PRT.ReadyScreenFrame:Refresh()
        end
    end)
end

function ReadyScreen:OnEnable()
    self.eventFrame:RegisterEvent("READY_CHECK")
    self.eventFrame:RegisterEvent("READY_CHECK_CONFIRM")
    self.eventFrame:RegisterEvent("READY_CHECK_FINISHED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("UNIT_AURA")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "READY_CHECK" then
            local settings = PRT:GetSetting("readyScreen")
            if settings and settings.enabled then
                ReadyScreen:ShowReadyCheck()
            end
        elseif event == "READY_CHECK_CONFIRM" then
            if mode == "readycheck" then
                ReadyScreen:OnReadyCheckConfirm(...)
            end
        elseif event == "READY_CHECK_FINISHED" then
            if readyCheckActive then
                ReadyScreen:OnReadyCheckFinished()
            end
        elseif event == "UNIT_AURA" then
            if mode ~= "hidden" and not auraRefreshPending then
                auraRefreshPending = true
                C_Timer.After(0.1, function()
                    auraRefreshPending = false
                    if mode ~= "hidden" and PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
                        PRT.ReadyScreenFrame:Refresh()
                    end
                end)
            end
        elseif event == "PLAYER_REGEN_DISABLED" then
            if mode ~= "hidden" then
                ReadyScreen:Close()
            end
        end
    end)
end

function ReadyScreen:OnDisable()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)
    readyCheckActive = false
    if mode ~= "hidden" then
        ReadyScreen:Close()
    end
end
