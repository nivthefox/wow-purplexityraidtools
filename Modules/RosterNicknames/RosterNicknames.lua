local PRT = PurplexityRaidTools
local RosterNicknames = {}
PRT.RosterNicknames = RosterNicknames
PRT.RosterNicknameAdapters = PRT.RosterNicknameAdapters or {}

PRT.defaults.rosterNicknames = {
    enabled = false,
}

local initializedAdapters = {}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

function RosterNicknames:RegisterAdapter(name, adapter)
    PRT.RosterNicknameAdapters[name] = adapter
    if self.initialized then
        self:InitializeAdapter(name, adapter)
    end
end

function RosterNicknames:InitializeAdapter(name, adapter)
    if initializedAdapters[name] or type(adapter.Initialize) ~= "function" then
        return
    end

    local ok, registered = pcall(adapter.Initialize, adapter)
    if ok and registered then
        initializedAdapters[name] = true
        if type(adapter.Refresh) == "function" then
            pcall(adapter.Refresh, adapter)
        end
    end
end

function RosterNicknames:IsEnabled()
    local settings = PRT:GetSetting("rosterNicknames")
    return self.rosterIsValid ~= false and settings and settings.enabled == true
end

function RosterNicknames:SetEnabled(enabled)
    if InCombat() then
        return false, "Roster Nicknames cannot be changed during combat."
    end

    local profile = PRT.Profiles:GetCurrent()
    profile.rosterNicknames = profile.rosterNicknames or {}
    profile.rosterNicknames.enabled = enabled and true or false
    self:RefreshAll()
    return true
end

function RosterNicknames:ResolveIdentity(identity)
    if not self:IsEnabled() then
        return nil
    end
    return PRT.Roster:ResolveNickname(identity)
end

function RosterNicknames:ResolveUnit(unit)
    if not self:IsEnabled() or type(UnitIsPlayer) ~= "function" then
        return nil
    end

    local isPlayer = UnitIsPlayer(unit)
    if IsSecret(isPlayer) or not isPlayer then
        return nil
    end

    local name, realm = UnitFullName(unit)
    if IsSecret(name) or IsSecret(realm) or type(name) ~= "string" or name == "" then
        return nil
    end
    if realm == nil or realm == "" then
        realm = GetNormalizedRealmName()
    end
    if IsSecret(realm) or type(realm) ~= "string" or realm == "" then
        return nil
    end
    return PRT.Roster:ResolveNickname(name .. "-" .. realm)
end

function RosterNicknames:RefreshAll()
    for _, adapter in pairs(PRT.RosterNicknameAdapters) do
        if type(adapter.Refresh) == "function" then
            pcall(adapter.Refresh, adapter)
        end
    end
end

function RosterNicknames:Initialize()
    self.initialized = true
    local valid, err = PRT.Roster:NormalizeStoredEntries()
    self.rosterIsValid = valid
    if not valid then
        print("|cFFFF0000PurplexityRaidTools:|r Roster Nicknames disabled: " .. tostring(err))
    end

    for name, adapter in pairs(PRT.RosterNicknameAdapters) do
        self:InitializeAdapter(name, adapter)
    end

    PRT.Roster:Listen(function()
        self:RefreshAll()
    end)
    self.eventFrame:RegisterEvent("ADDON_LOADED")
    self.eventFrame:SetScript("OnEvent", function()
        for name, adapter in pairs(PRT.RosterNicknameAdapters) do
            self:InitializeAdapter(name, adapter)
        end
    end)
end

PRT:RegisterApplyCallback("rosterNicknames", function()
    RosterNicknames:RefreshAll()
end)

PRT:RegisterModule("rosterNicknames", RosterNicknames)
