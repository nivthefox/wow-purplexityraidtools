local PRT = PurplexityRaidTools
local Adapter = {}

local function GetDandersFrames()
    return type(DandersFrames) == "table" and DandersFrames or nil
end

function Adapter:Initialize()
    if self.registered then
        return true
    end

    local api = GetDandersFrames()
    if not api or type(api.GetUnitName) ~= "function" then
        return false
    end

    self.previous = api.GetUnitName
    self.resolver = self.resolver or function(dandersFrames, unit)
        local nickname = PRT.RosterNicknames:ResolveUnit(unit)
        if nickname then
            return nickname
        end
        return self.previous(dandersFrames, unit)
    end

    api.GetUnitName = self.resolver
    self.api = api
    self.registered = true
    return true
end

function Adapter:Refresh()
    local api = self.api or GetDandersFrames()
    local nicknames = api and api.Nicknames
    if nicknames and type(nicknames.RefreshAllFrames) == "function" then
        nicknames:RefreshAllFrames()
    end
end

PRT.RosterNicknames:RegisterAdapter("DandersFrames", Adapter)
