local PRT = PurplexityRaidTools
local Adapter = {}

local function IsEllesmereUILoaded()
    if type(C_AddOns) ~= "table" or type(C_AddOns.IsAddOnLoaded) ~= "function" then
        return false
    end
    return C_AddOns.IsAddOnLoaded("EllesmereUIRaidFrames")
        or C_AddOns.IsAddOnLoaded("EllesmereUIUnitFrames")
end

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function IsNickname(value, unit)
    if type(value) ~= "string" or value == "" or IsSecret(value) then
        return false
    end
    if type(UnitName) ~= "function" then
        return true
    end

    local name = UnitName(unit)
    if type(name) ~= "string" or IsSecret(name) then
        return true
    end
    return value ~= name
end

function Adapter:Initialize()
    if self.registered then
        return true
    end
    if not IsEllesmereUILoaded() then
        return false
    end

    local api = EasyNicknameAPI
    if type(api) ~= "table" then
        api = {}
        _G.EasyNicknameAPI = api
    end

    self.previous = type(api.GetNicknameForUnit) == "function" and api.GetNicknameForUnit or nil
    self.resolver = self.resolver or function(unit)
        local previousResult
        if self.previous then
            local ok, result = pcall(self.previous, unit)
            if ok then
                previousResult = result
                if IsNickname(result, unit) then
                    return result
                end
            end
        end

        return PRT.RosterNicknames:ResolveUnit(unit) or previousResult
    end

    api.GetNicknameForUnit = self.resolver
    self.api = api
    self.registered = true
    return true
end

function Adapter:Refresh()
    if type(_G._EUF_RefreshUnitNames) == "function" then
        _G._EUF_RefreshUnitNames()
    end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then
        return
    end
    if type(_G._ERF_RefreshAll) == "function" then
        _G._ERF_RefreshAll()
    end
end

PRT.RosterNicknames:RegisterAdapter("EllesmereUI", Adapter)
