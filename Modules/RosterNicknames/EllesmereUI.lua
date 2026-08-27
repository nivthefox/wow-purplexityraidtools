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
        self:Maintain()
        return true
    end
    if not IsEllesmereUILoaded() then
        return false
    end

    self.legacyResolver = self.legacyResolver or function(unit)
        local previousResult
        if self.previousLegacy then
            local ok, result = pcall(self.previousLegacy, unit)
            if ok then
                previousResult = result
                if IsNickname(result, unit) then
                    return result
                end
            end
        end

        return PRT.RosterNicknames:ResolveUnit(unit) or previousResult
    end
    self.surfaceResolver = self.surfaceResolver or function(unit, surface)
        local previousResult, previousHandled
        if self.previousSurface then
            local ok, result, handled = pcall(self.previousSurface, unit, surface)
            if ok then
                previousResult = result
                previousHandled = handled
                if handled == true then
                    return result, handled
                end
            end
        end

        local nickname = PRT.RosterNicknames:ResolveUnit(unit)
        if nickname then
            return nickname, true
        end
        return previousResult, previousHandled
    end
    self.registered = true
    self:Maintain()
    return true
end

function Adapter:Maintain(loadedAddon)
    if not self.registered then
        return false
    end
    if loadedAddon and loadedAddon ~= "MethodInternal" then
        return true
    end

    local api = EasyNicknameAPI
    if type(api) ~= "table" then
        api = {}
        _G.EasyNicknameAPI = api
    end

    if self.api ~= api then
        self.api = api
        self.previousLegacy = nil
        self.previousSurface = nil
    end

    if api.GetNicknameForUnit ~= self.legacyResolver then
        self.previousLegacy = type(api.GetNicknameForUnit) == "function" and api.GetNicknameForUnit or nil
        api.GetNicknameForUnit = self.legacyResolver
    end
    if api.GetNicknameForUnitForSurface ~= self.surfaceResolver then
        self.previousSurface = type(api.GetNicknameForUnitForSurface) == "function"
            and api.GetNicknameForUnitForSurface or nil
        api.GetNicknameForUnitForSurface = self.surfaceResolver
    end
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
