local PRT = PurplexityRaidTools
local Adapter = {}

function Adapter:Initialize()
    if self.registered then
        return true
    end

    local api = NivUI_Nicknames
    if type(api) ~= "table" or type(api.RegisterResolver) ~= "function" then
        return false
    end

    self.resolver = self.resolver or function(identity)
        return PRT.RosterNicknames:ResolveIdentity(identity)
    end
    if not api:RegisterResolver(self.resolver) then
        return false
    end
    self.api = api
    self.registered = true
    return true
end

function Adapter:Refresh()
    local api = self.api or NivUI_Nicknames
    if type(api) == "table" and type(api.RefreshAll) == "function" then
        api:RefreshAll()
    end
end

PRT.RosterNicknames:RegisterAdapter("NivUI", Adapter)
