local PRT = PurplexityRaidTools
local ReadyScreen = {}
PRT.ReadyScreen = ReadyScreen
PRT:RegisterModule("readyScreen", ReadyScreen)

PRT.defaults.readyScreen = {
    enabled = true,
    autoDismiss = false,
    position = nil,
}

local PERSONAL_BUFFS = {
    { key = "wellFed", name = "Well Fed", texture = 136000 },
    { key = "weaponEnhancement", name = "Weapon Enhancement", texture = 463543 },
    { key = "flask", name = "Flask", texture = 967549 },
    { key = "augmentRune", name = "Augment Rune", texture = 840006 },
    { key = "vantusRune", name = "Vantus Rune", texture = 1058937 },
    { key = "durability", name = "Durability", texture = 132281, display = "percent", width = 36 },
}

local FLASK_SPELL_IDS = {
    [307166] = true,
    [307185] = true,
    [307187] = true,
    [370652] = true,
    [370662] = true,
    [371172] = true,
    [371186] = true,
    [371204] = true,
    [371339] = true,
    [371354] = true,
    [371386] = true,
    [373257] = true,
    [374000] = true,
    [431971] = true,
    [431972] = true,
    [431973] = true,
    [431974] = true,
    [432021] = true,
    [432473] = true,
    [1235057] = true,
    [1235108] = true,
    [1235110] = true,
    [1235111] = true,
    [1236763] = true,
    [1236767] = true,
    [1239355] = true,
    [1239755] = true,
}

local AUGMENT_RUNE_SPELL_IDS = {
    [224001] = true,
    [270058] = true,
    [317065] = true,
    [347901] = true,
    [367405] = true,
    [393438] = true,
    [453250] = true,
    [1234969] = true,
    [1242347] = true,
    [1264426] = true,
}

local VANTUS_REFERENCE_SPELL_ID = 237825
local STATUS_QUERY_MSG_TYPE = "readyStatusQuery"
local STATUS_RESPONSE_MSG_TYPE = "readyStatusResponse"
local DURABILITY_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
local reportedStatuses = {}
local statusSubscribers = {}
local vantusPrefix

local mode = "hidden"
local responses = {}
local autoDismissTimer = nil
local readyCheckActive = false
local auraRefreshPending = false
local readyCheckTicker = nil
local previewRoster
local PREVIEW_SPECS = {
    { class = "WARRIOR", specId = 73, role = "TANK" },
    { class = "PRIEST", specId = 257, role = "HEALER" },
    { class = "MAGE", specId = 63, role = "DAMAGER" },
    { class = "ROGUE", specId = 260, role = "DAMAGER" },
    { class = "DRUID", specId = 102, role = "DAMAGER" },
}

function ReadyScreen:GetPreviewRoster()
    if IsInGroup() then
        previewRoster = nil
        return nil
    end
    if previewRoster then
        return previewRoster
    end

    previewRoster = {}
    local auditStatuses = { "complete", "missing", "unknown" }
    for i = 1, 4 do
        local spec = PREVIEW_SPECS[math.random(#PREVIEW_SPECS)]
        local buffs = {}
        for _, buff in ipairs(PRT.RAID_BUFFS) do
            buffs[buff.name] = math.random(2) == 1
        end
        buffs[PRT.SOULSTONE_BUFF_NAME] = math.random(2) == 1
        for _, buff in ipairs(PERSONAL_BUFFS) do
            buffs[buff.key] = math.random(2) == 1
        end
        local gearAudit = {}
        for _, key in ipairs({ "enchants", "gems" }) do
            local status = auditStatuses[math.random(3)]
            gearAudit[key] = {
                status = status,
                missing = status == "missing" and { { slot = 11, count = 1 } } or {},
                unknown = status == "unknown" and { 11 } or {},
            }
        end
        previewRoster[i] = {
            guid = "PRT-Preview-" .. i,
            name = "Test " .. spec.class .. " " .. i,
            class = spec.class,
            specId = spec.specId,
            role = spec.role,
            previewBuffs = buffs,
            durability = math.random(0, 100),
            itemLevel = math.random(200, 280),
            gearAudit = gearAudit,
        }
    end
    return previewRoster
end

function ReadyScreen.GetPersonalBuffColumns()
    return PERSONAL_BUFFS
end

function ReadyScreen.GetPersonalBuffKey(auraData, localizedVantusPrefix)
    if type(auraData) ~= "table" then
        return nil
    end
    if canaccessvalue and not canaccessvalue(auraData.spellId) then
        return nil
    end
    if auraData.icon == 136000 then
        return "wellFed"
    end
    if FLASK_SPELL_IDS[auraData.spellId] then
        return "flask"
    end
    if AUGMENT_RUNE_SPELL_IDS[auraData.spellId] then
        return "augmentRune"
    end
    if type(auraData.name) ~= "string" or type(localizedVantusPrefix) ~= "string" then
        return nil
    end
    if auraData.name:sub(1, #localizedVantusPrefix) == localizedVantusPrefix then
        return "vantusRune"
    end
    return nil
end

function ReadyScreen.BuildPersonalBuffStatuses(auras, localizedVantusPrefix)
    local statuses = {}
    for _, auraData in ipairs(auras or {}) do
        local key = ReadyScreen.GetPersonalBuffKey(auraData, localizedVantusPrefix)
        if key then
            statuses[key] = auraData.icon or true
        end
    end
    return statuses
end

function ReadyScreen.AnyWeaponEnhanced(hasMainHandEnchant, hasOffHandEnchant)
    return hasMainHandEnchant == true or hasOffHandEnchant == true
end

function ReadyScreen.CalculateDurability(items)
    local totalCurrent = 0
    local totalMaximum = 0
    for _, item in ipairs(items or {}) do
        if item.current and item.maximum then
            totalCurrent = totalCurrent + item.current
            totalMaximum = totalMaximum + item.maximum
        end
    end
    if totalMaximum == 0 then
        return 100
    end
    return totalCurrent / totalMaximum * 100
end

local function GetSpellName(spellId)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellId)
    end
    if GetSpellInfo then
        return GetSpellInfo(spellId)
    end
    return nil
end

local function GetVantusPrefix()
    if vantusPrefix then
        return vantusPrefix
    end

    local referenceName = GetSpellName(VANTUS_REFERENCE_SPELL_ID)
    if not referenceName then
        return "Vantus Rune"
    end

    vantusPrefix = referenceName:match("^(.-)[:%-：]") or referenceName
    return vantusPrefix
end

function ReadyScreen.GetPersonalBuffStatuses(unit)
    local statuses = {}
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return statuses
    end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return statuses
    end

    local localizedVantusPrefix = GetVantusPrefix()
    for index = 1, 60 do
        local auraData = C_UnitAuras.GetAuraDataByIndex(unit, index, "HELPFUL")
        if not auraData then
            break
        end
        if not issecretvalue or not issecretvalue(auraData.spellId) then
            local key = ReadyScreen.GetPersonalBuffKey(auraData, localizedVantusPrefix)
            if key then
                statuses[key] = auraData.icon or true
            end
        end
    end
    return statuses
end

local function ReadLocalDurability()
    if not GetInventoryItemDurability then
        return nil
    end

    local items = {}
    for _, slotId in ipairs(DURABILITY_SLOTS) do
        local current, maximum = GetInventoryItemDurability(slotId)
        table.insert(items, { current = current, maximum = maximum })
    end
    return ReadyScreen.CalculateDurability(items)
end

local function ReadLocalStatus()
    local weaponEnhanced
    if GetWeaponEnchantInfo then
        local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
        weaponEnhanced = ReadyScreen.AnyWeaponEnhanced(hasMainHandEnchant, hasOffHandEnchant)
    end
    return {
        weaponEnhanced = weaponEnhanced,
        durability = ReadLocalDurability(),
    }
end

local function SendStatus(target)
    if not PRT.Comms then
        return
    end
    PRT.Comms:Send(STATUS_RESPONSE_MSG_TYPE, ReadLocalStatus(), "WHISPER", target)
end

local function ResolveGroupMember(sender)
    if type(sender) ~= "string" or sender == "" then
        return nil, nil
    end

    local senderShortName = Ambiguate(sender, "short")
    local matchingGUID
    local matchingName
    local shortNameIsAmbiguous = false
    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        local name = GetUnitName(unit, true)
        if guid and name == sender then
            return guid, name
        end
        if guid and name and Ambiguate(name, "short") == senderShortName then
            if matchingGUID and matchingGUID ~= guid then
                shortNameIsAmbiguous = true
            else
                matchingGUID = guid
                matchingName = name
            end
        end
    end
    if shortNameIsAmbiguous then
        return nil, nil
    end
    return matchingGUID, matchingName
end

local function OnStatusQuery(_, sender)
    local _, target = ResolveGroupMember(sender)
    if not target then
        return
    end
    statusSubscribers[target] = GetTime() + 60
    SendStatus(target)
end

local function OnStatusResponse(data, sender)
    if type(data) ~= "table" or type(data.weaponEnhanced) ~= "boolean"
        or type(data.durability) ~= "number" or data.durability ~= data.durability
        or data.durability < 0 or data.durability > 100 then
        return
    end

    local guid = ResolveGroupMember(sender)
    if not guid then
        return
    end

    reportedStatuses[guid] = {
        weaponEnhanced = data.weaponEnhanced,
        durability = data.durability,
    }
    if PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
        PRT.ReadyScreenFrame:Refresh()
    end
end

local function RequestStatus(unit)
    local guid = UnitGUID(unit)
    if not guid then
        return
    end
    if UnitIsUnit(unit, "player") then
        reportedStatuses[guid] = ReadLocalStatus()
        return
    end

    local target = GetUnitName(unit, true)
    if target then
        PRT.Comms:Send(STATUS_QUERY_MSG_TYPE, {}, "WHISPER", target)
    end
end

function ReadyScreen:RequestStatuses()
    reportedStatuses = {}
    for unit in PRT:IterateGroup() do
        RequestStatus(unit)
    end
end

function ReadyScreen:GetWeaponStatus(guid)
    local status = reportedStatuses[guid]
    return status and status.weaponEnhanced
end

function ReadyScreen:GetDurability(guid)
    local status = reportedStatuses[guid]
    return status and status.durability
end

local function PublishStatusChanges()
    local now = GetTime()
    for target, expiresAt in pairs(statusSubscribers) do
        local guid = ResolveGroupMember(target)
        if expiresAt < now or not guid then
            statusSubscribers[target] = nil
        else
            SendStatus(target)
        end
    end
end

local function RefreshLocalStatus()
    local guid = UnitGUID("player")
    if guid then
        reportedStatuses[guid] = ReadLocalStatus()
    end
    PublishStatusChanges()
    if mode ~= "hidden" and PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
        PRT.ReadyScreenFrame:Refresh()
    end
end

local function IsGroupUnit(unit)
    return unit:match("^raid") or unit:match("^party") or unit == "player"
end

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

function ReadyScreen.IsItemLevelAvailable(itemLevel)
    return type(itemLevel) == "number" and itemLevel == itemLevel
        and itemLevel > 0 and itemLevel < math.huge
end

function ReadyScreen.FormatItemLevel(itemLevel)
    if not ReadyScreen.IsItemLevelAvailable(itemLevel) then
        return "\226\128\148"
    end
    if itemLevel % 1 == 0 then
        return string.format("%d", itemLevel)
    end
    return string.format("%.1f", itemLevel)
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

local function CanShow()
    if readyCheckActive then
        return true
    end
    local settings = PRT:GetSetting("readyScreen")
    if not settings or not settings.enabled then
        return false
    end
    return true
end

function ReadyScreen:ShowReadiness()
    if not CanShow() then
        return
    end

    mode = readyCheckActive and "readycheck" or "audit"
    ReadyScreen:RequestStatuses()
    if PRT.ReadyScreenFrame then
        PRT.ReadyScreenFrame:Show("readiness")
    end
end

function ReadyScreen:ShowAudit()
    self:ShowReadiness()
end

function ReadyScreen:ShowGear()
    if not CanShow() then
        return
    end

    if not readyCheckActive then
        mode = "gear"
    end
    if PRT.ReadyScreenFrame then
        PRT.ReadyScreenFrame:Show("gear")
    end
    PRT.GroupInspect:RequestEquipmentRefresh()
end

function ReadyScreen:ShowReadyCheck(initiator)
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

    if initiator then
        local initiatorGUID = UnitGUID(initiator)
        if initiatorGUID and responses[initiatorGUID] then
            responses[initiatorGUID] = "ready"
        end
    end

    mode = "readycheck"
    readyCheckActive = true
    ReadyScreen:RequestStatuses()

    if PRT.ReadyScreenFrame then
        PRT.ReadyScreenFrame:Show("readiness")
    end

    readyCheckTicker = C_Timer.NewTicker(0.5, function()
        if not readyCheckActive then
            if readyCheckTicker then
                readyCheckTicker:Cancel()
                readyCheckTicker = nil
            end
            return
        end
        if PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
            PRT.ReadyScreenFrame:Refresh()
        end
    end)
end

function ReadyScreen:Close()
    previewRoster = nil
    if autoDismissTimer then
        autoDismissTimer:Cancel()
        autoDismissTimer = nil
    end
    if readyCheckTicker then
        readyCheckTicker:Cancel()
        readyCheckTicker = nil
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
    RequestStatus(unit)

    if PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
        PRT.ReadyScreenFrame:Refresh()
    end
end

function ReadyScreen:OnReadyCheckFinished()
    readyCheckActive = false

    if readyCheckTicker then
        readyCheckTicker:Cancel()
        readyCheckTicker = nil
    end

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
    return true
end

function ReadyScreen:Initialize()
    PRT.Comms:RegisterHandler(STATUS_QUERY_MSG_TYPE, OnStatusQuery)
    PRT.Comms:RegisterHandler(STATUS_RESPONSE_MSG_TYPE, OnStatusResponse)
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
    self.eventFrame:RegisterEvent("UNIT_FLAGS")
    self.eventFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
    self.eventFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    self.eventFrame:SetScript("OnEvent", function(_, event, ...)
        if event == "READY_CHECK" then
            local initiator = ...
            local settings = PRT:GetSetting("readyScreen")
            if settings and settings.enabled then
                ReadyScreen:ShowReadyCheck(initiator)
            end
        elseif event == "READY_CHECK_CONFIRM" then
            if readyCheckActive then
                ReadyScreen:OnReadyCheckConfirm(...)
            end
        elseif event == "READY_CHECK_FINISHED" then
            if readyCheckActive then
                ReadyScreen:OnReadyCheckFinished()
            end
        elseif event == "UNIT_AURA" or event == "UNIT_FLAGS" then
            local unit = ...
            if mode ~= "hidden" and unit and IsGroupUnit(unit) and not auraRefreshPending then
                auraRefreshPending = true
                C_Timer.After(0.1, function()
                    auraRefreshPending = false
                    if mode ~= "hidden" and PRT.ReadyScreenFrame and PRT.ReadyScreenFrame:IsShown() then
                        PRT.ReadyScreenFrame:Refresh()
                    end
                end)
            end
        elseif event == "UNIT_INVENTORY_CHANGED" then
            local unit = ...
            if unit == "player" then
                RefreshLocalStatus()
            end
        elseif event == "UPDATE_INVENTORY_DURABILITY" then
            RefreshLocalStatus()
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
