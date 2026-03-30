-- CooldownRoster: Shows available raid cooldowns based on group composition
local PRT = PurplexityRaidTools
local CooldownRoster = {}
PRT.CooldownRoster = CooldownRoster

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

PRT.defaults.cooldownRoster = {
    enabled = true,
    lockFrames = true,
    contentTypes = {
        openWorld = false,
        dungeon = { normal = false, heroic = false, mythic = false, mythicPlus = false },
        raid = { lfr = false, normal = false, heroic = true, mythic = true },
        scenario = { normal = false, heroic = false },
    },
    categories = {
        defensive = true,
        external = true,
        movement = true,
    },
}

--------------------------------------------------------------------------------
-- Spell Data
--------------------------------------------------------------------------------

-- Spec IDs:
-- Restoration Druid: 105
-- Preservation Evoker: 1468
-- Restoration Shaman: 264
-- Mistweaver Monk: 270
-- Holy Paladin: 65
-- Discipline Priest: 256
-- Holy Priest: 257

local SPELL_DATA = {
    -- Defensive
    { spellId = 740,    name = "Tranquility",             category = "defensive", class = "DRUID",        specId = 105  },
    { spellId = 359816, name = "Dream Flight",            category = "defensive", class = "EVOKER",       specId = 1468 },
    { spellId = 363534, name = "Rewind",                  category = "defensive", class = "EVOKER",       specId = 1468 },
    { spellId = 108280, name = "Healing Tide Totem",      category = "defensive", class = "SHAMAN",       specId = 264  },
    { spellId = 98008,  name = "Spirit Link Totem",       category = "defensive", class = "SHAMAN",       specId = 264  },
    { spellId = 115310, name = "Revival / Restoral",      category = "defensive", class = "MONK",         specId = 270  },
    { spellId = 31821,  name = "Aura Mastery",            category = "defensive", class = "PALADIN",      specId = 65   },
    { spellId = 62618,  name = "PW:B / Luminous Barrier", category = "defensive", class = "PRIEST",       specId = 256  },
    { spellId = 64843,  name = "Divine Hymn",             category = "defensive", class = "PRIEST",       specId = 257  },
    { spellId = 97462,  name = "Rallying Cry",            category = "defensive", class = "WARRIOR",      specId = nil  },
    { spellId = 51052,  name = "Anti-Magic Zone",         category = "defensive", class = "DEATHKNIGHT",  specId = nil  },
    { spellId = 196718, name = "Darkness",                category = "defensive", class = "DEMONHUNTER",  specId = nil  },

    -- External
    { spellId = 357170, name = "Time Dilation",           category = "external",  class = "EVOKER",       specId = 1468 },
    { spellId = 33206,  name = "Pain Suppression",        category = "external",  class = "PRIEST",       specId = 256  },
    { spellId = 102342, name = "Ironbark",                category = "external",  class = "DRUID",        specId = 105  },
    { spellId = 6940,   name = "Blessing of Sacrifice",   category = "external",  class = "PALADIN",      specId = nil  },
    { spellId = 47788,  name = "Guardian Spirit",         category = "external",  class = "PRIEST",       specId = 257  },

    -- Movement
    { spellId = 106898, name = "Stampeding Roar",         category = "movement",  class = "DRUID",        specId = nil  },
    { spellId = 192077, name = "Wind Rush Totem",         category = "movement",  class = "SHAMAN",       specId = nil  },
    { spellId = 374968, name = "Time Spiral",             category = "movement",  class = "EVOKER",       specId = nil  },
}

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local specCache = {}        -- GUID -> specId
local inspectQueue = {}     -- array of {unit, guid}
local inspectPending = nil  -- unit currently being inspected
local inCombat = false
local rosterCooldowns = {}  -- computed array of {spellId, name, category, playerName, playerClass}
local inspectTicker = nil
local eventFrame = nil

-- Display frames
local categoryFrames = {}   -- keyed by category name

--------------------------------------------------------------------------------
-- Category Display Names
--------------------------------------------------------------------------------

local CATEGORY_INFO = {
    defensive = { label = "Defensives", order = 1 },
    external  = { label = "Externals",  order = 2 },
    movement  = { label = "Movement",   order = 3 },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function GetGroupUnitIterator()
    if IsInRaid() then
        local count = GetNumGroupMembers()
        local i = 0
        return function()
            i = i + 1
            if i <= count then
                return "raid" .. i
            end
        end
    elseif IsInGroup() then
        local count = GetNumGroupMembers() - 1
        local i = 0
        local sentPlayer = false
        return function()
            i = i + 1
            if i <= count then
                return "party" .. i
            elseif not sentPlayer then
                sentPlayer = true
                return "player"
            end
        end
    else
        return function() return nil end
    end
end

local function GetPlayerSpecId()
    local specIndex = GetSpecialization()
    if not specIndex then
        return nil
    end
    local specId = GetSpecializationInfo(specIndex)
    return specId
end

--------------------------------------------------------------------------------
-- Inspection Queue
--------------------------------------------------------------------------------

local function ProcessNextInspect()
    if inCombat or inspectPending then
        return
    end

    while #inspectQueue > 0 do
        local entry = table.remove(inspectQueue, 1)
        local unit, guid = entry.unit, entry.guid

        -- Verify the unit still exists and matches the GUID we queued
        if UnitExists(unit) and UnitGUID(unit) == guid and not specCache[guid] then
            inspectPending = unit
            NotifyInspect(unit)
            -- Timeout: if INSPECT_READY doesn't fire in 2s, clear pending
            C_Timer.After(2, function()
                if inspectPending == unit then
                    inspectPending = nil
                end
            end)
            return
        end
    end
end

local function StartInspectTicker()
    if inspectTicker then
        return
    end
    inspectTicker = C_Timer.NewTicker(0.5, ProcessNextInspect)
end

local function StopInspectTicker()
    if inspectTicker then
        inspectTicker:Cancel()
        inspectTicker = nil
    end
end

local function OnInspectReady(unit)
    if not inspectPending then
        return
    end

    local guid = UnitGUID(inspectPending)
    if not guid then
        inspectPending = nil
        return
    end

    local specId = GetInspectSpecialization(inspectPending)
    if specId and specId > 0 then
        specCache[guid] = specId
    end
    -- If specId is 0 or nil, the player will get re-queued on next roster scan

    inspectPending = nil
    CooldownRoster:RebuildRoster()
    CooldownRoster:UpdateDisplay()
end

--------------------------------------------------------------------------------
-- Roster Scanning
--------------------------------------------------------------------------------

function CooldownRoster:ScanRoster()
    local activeGUIDs = {}
    inspectQueue = {}

    for unit in GetGroupUnitIterator() do
        local guid = UnitGUID(unit)
        if guid then
            activeGUIDs[guid] = true

            if UnitIsUnit(unit, "player") then
                local specId = GetPlayerSpecId()
                if specId then
                    specCache[guid] = specId
                end
            elseif not specCache[guid] then
                table.insert(inspectQueue, { unit = unit, guid = guid })
            end
        end
    end

    -- Remove stale GUIDs (players who left)
    for guid in pairs(specCache) do
        if not activeGUIDs[guid] then
            specCache[guid] = nil
        end
    end
end

function CooldownRoster:RebuildRoster()
    rosterCooldowns = {}

    for unit in GetGroupUnitIterator() do
        local guid = UnitGUID(unit)
        if guid then
            local _, classToken = UnitClass(unit)
            local playerName = UnitName(unit)
            local cachedSpec = specCache[guid]

            for _, spell in ipairs(SPELL_DATA) do
                if spell.class == classToken then
                    if spell.specId == nil or spell.specId == cachedSpec then
                        table.insert(rosterCooldowns, {
                            spellId = spell.spellId,
                            name = spell.name,
                            category = spell.category,
                            playerName = playerName,
                            playerClass = classToken,
                        })
                    end
                end
            end
        end
    end

    -- Sort: category order, then spell name, then player name
    table.sort(rosterCooldowns, function(a, b)
        local orderA = CATEGORY_INFO[a.category] and CATEGORY_INFO[a.category].order or 99
        local orderB = CATEGORY_INFO[b.category] and CATEGORY_INFO[b.category].order or 99
        if orderA ~= orderB then return orderA < orderB end
        if a.name ~= b.name then return a.name < b.name end
        return a.playerName < b.playerName
    end)
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local BAR_HEIGHT = 20
local BAR_WIDTH = 200
local ICON_SIZE = 18
local BAR_SPACING = 2
local HEADER_HEIGHT = 20
local BACKDROP_PADDING = 4

local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(BAR_WIDTH, BAR_HEIGHT)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 2, 0)
    bar.icon = icon

    local spellText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    spellText:SetWidth(90)
    spellText:SetJustifyH("LEFT")
    bar.spellText = spellText

    local playerText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerText:SetPoint("LEFT", spellText, "RIGHT", 4, 0)
    playerText:SetJustifyH("LEFT")
    bar.playerText = playerText

    return bar
end

local function CreateCategoryFrame(categoryKey)
    local info = CATEGORY_INFO[categoryKey]
    local frameName = "PRT_CooldownRoster_" .. categoryKey
    local frame = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
    frame:SetSize(BAR_WIDTH + BACKDROP_PADDING * 2, HEADER_HEIGHT + BACKDROP_PADDING * 2)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.7)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", BACKDROP_PADDING, -BACKDROP_PADDING)
    header:SetText(info.label)
    frame.header = header

    frame.bars = {}
    frame.categoryKey = categoryKey

    return frame
end

local function SetupDragging(frame, categoryKey)
    local settings = PRT:GetSetting("cooldownRoster")
    local locked = settings and settings.lockFrames

    frame:SetMovable(not locked)
    frame:EnableMouse(not locked)

    if locked then
        frame:RegisterForDrag()
    else
        frame:RegisterForDrag("LeftButton")
    end

    frame:SetScript("OnDragStart", function(self)
        if not self:IsMovable() then return end
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CooldownRoster:SaveFramePosition(categoryKey)
    end)
end

function CooldownRoster:SaveFramePosition(categoryKey)
    local frame = categoryFrames[categoryKey]
    if not frame then return end

    local profile = PRT.Profiles:GetCurrent()
    if not profile.cooldownRoster then
        profile.cooldownRoster = {}
    end
    if not profile.cooldownRoster.positions then
        profile.cooldownRoster.positions = {}
    end

    local point, _, _, x, y = frame:GetPoint()
    profile.cooldownRoster.positions[categoryKey] = {
        point = point,
        x = x,
        y = y,
    }
end

function CooldownRoster:RestoreFramePosition(categoryKey)
    local frame = categoryFrames[categoryKey]
    if not frame then return end

    local settings = PRT:GetSetting("cooldownRoster")
    local positions = settings and settings.positions

    frame:ClearAllPoints()

    if positions and positions[categoryKey] then
        local pos = positions[categoryKey]
        frame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
    else
        -- Default positions: stacked vertically on right side
        local defaults = {
            defensive = { "RIGHT", -200, 100 },
            external  = { "RIGHT", -200, 0 },
            movement  = { "RIGHT", -200, -100 },
        }
        local def = defaults[categoryKey]
        frame:SetPoint(def[1], UIParent, def[1], def[2], def[3])
    end
end

function CooldownRoster:UpdateDragging()
    for categoryKey, frame in pairs(categoryFrames) do
        SetupDragging(frame, categoryKey)
    end
end

function CooldownRoster:UpdateDisplay()
    local settings = PRT:GetSetting("cooldownRoster")

    for categoryKey, frame in pairs(categoryFrames) do
        local categoryEnabled = settings and settings.categories and settings.categories[categoryKey]

        -- Gather entries for this category
        local entries = {}
        if categoryEnabled then
            for _, entry in ipairs(rosterCooldowns) do
                if entry.category == categoryKey then
                    table.insert(entries, entry)
                end
            end
        end

        if #entries == 0 or not self:ShouldDisplay() then
            frame:Hide()
        else
            -- Ensure we have enough bars
            while #frame.bars < #entries do
                table.insert(frame.bars, CreateBar(frame))
            end

            -- Configure and show bars
            for i, entry in ipairs(entries) do
                local bar = frame.bars[i]
                bar.icon:SetTexture(C_Spell.GetSpellTexture(entry.spellId))
                bar.spellText:SetText(entry.name)

                local classColor = RAID_CLASS_COLORS[entry.playerClass]
                if classColor then
                    bar.playerText:SetText(classColor:WrapTextInColorCode(entry.playerName))
                else
                    bar.playerText:SetText(entry.playerName)
                end

                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", frame, "TOPLEFT", BACKDROP_PADDING, -(HEADER_HEIGHT + BACKDROP_PADDING + (i - 1) * (BAR_HEIGHT + BAR_SPACING)))
                bar:Show()
            end

            -- Hide excess bars
            for i = #entries + 1, #frame.bars do
                frame.bars[i]:Hide()
            end

            -- Resize frame to fit content
            local contentHeight = HEADER_HEIGHT + #entries * (BAR_HEIGHT + BAR_SPACING) + BACKDROP_PADDING * 2
            frame:SetSize(BAR_WIDTH + BACKDROP_PADDING * 2, contentHeight)
            frame:Show()
        end
    end
end

--------------------------------------------------------------------------------
-- Visibility Logic
--------------------------------------------------------------------------------

function CooldownRoster:ShouldDisplay()
    local settings = PRT:GetSetting("cooldownRoster")
    if not settings or not settings.enabled then
        return false
    end

    if not IsInGroup() and not IsInRaid() then
        return false
    end

    return PRT.IsContentTypeEnabled(settings.contentTypes)
end

function CooldownRoster:UpdateVisibility()
    if not self:ShouldDisplay() then
        for _, frame in pairs(categoryFrames) do
            frame:Hide()
        end
        return
    end

    self:UpdateDisplay()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local function OnEvent(_, event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        CooldownRoster:ScanRoster()
        CooldownRoster:RebuildRoster()
        CooldownRoster:UpdateVisibility()

    elseif event == "INSPECT_READY" then
        OnInspectReady(...)

    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false

    elseif event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        CooldownRoster:UpdateVisibility()
    end
end

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Cooldown Roster", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 8, -60)
    container:SetPoint("BOTTOMRIGHT", -8, 8)
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(container:GetWidth() - 40)
    scrollChild:SetHeight(600)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0
    local ROW_HEIGHT = 24

    local function GetSettings()
        return PRT:GetSetting("cooldownRoster")
    end

    local function EnsureSettingsTable()
        local profile = PRT.Profiles:GetCurrent()
        if not profile.cooldownRoster then
            profile.cooldownRoster = {}
            for k, v in pairs(PRT.defaults.cooldownRoster) do
                if type(v) == "table" then
                    profile.cooldownRoster[k] = {}
                    for k2, v2 in pairs(v) do
                        if type(v2) == "table" then
                            profile.cooldownRoster[k][k2] = {}
                            for k3, v3 in pairs(v2) do
                                profile.cooldownRoster[k][k2][k3] = v3
                            end
                        else
                            profile.cooldownRoster[k][k2] = v2
                        end
                    end
                else
                    profile.cooldownRoster[k] = v
                end
            end
        end
        return profile.cooldownRoster
    end

    -- General Section
    local generalHeader = PRT.Components.GetHeader(scrollChild, "General")
    generalHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enable Cooldown Roster", function(value)
        EnsureSettingsTable().enabled = value
        PRT:ApplySettings("cooldownRoster")
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local lockCheckbox = PRT.Components.GetCheckbox(scrollChild, "Lock frame positions", function(value)
        EnsureSettingsTable().lockFrames = value
        CooldownRoster:UpdateDragging()
    end)
    lockCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    lockCheckbox:SetValue(GetSettings().lockFrames)
    yOffset = yOffset - ROW_HEIGHT

    -- Categories Section
    yOffset = yOffset - 10
    local catHeader = PRT.Components.GetHeader(scrollChild, "Categories")
    catHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local categoryCheckboxes = {}

    local catDefs = {
        { label = "Defensives", key = "defensive" },
        { label = "Externals",  key = "external" },
        { label = "Movement",   key = "movement" },
    }

    for _, def in ipairs(catDefs) do
        local checkbox = PRT.Components.GetCheckbox(scrollChild, def.label, function(value)
            local s = EnsureSettingsTable()
            if not s.categories then s.categories = {} end
            s.categories[def.key] = value
            PRT:ApplySettings("cooldownRoster")
        end)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)
        checkbox:SetValue(GetSettings().categories[def.key])
        table.insert(categoryCheckboxes, { widget = checkbox, key = def.key })
        yOffset = yOffset - ROW_HEIGHT
    end

    -- Content Types Section
    yOffset = yOffset - 10
    local contentHeader = PRT.Components.GetHeader(scrollChild, "Show In")
    contentHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local contentCheckboxes = {
        { label = "Open World",        path = {"contentTypes", "openWorld"} },
        { label = "Dungeon (Normal)",  path = {"contentTypes", "dungeon", "normal"} },
        { label = "Dungeon (Heroic)",  path = {"contentTypes", "dungeon", "heroic"} },
        { label = "Dungeon (Mythic)",  path = {"contentTypes", "dungeon", "mythic"} },
        { label = "Dungeon (Mythic+)", path = {"contentTypes", "dungeon", "mythicPlus"} },
        { label = "Raid (LFR)",        path = {"contentTypes", "raid", "lfr"} },
        { label = "Raid (Normal)",     path = {"contentTypes", "raid", "normal"} },
        { label = "Raid (Heroic)",     path = {"contentTypes", "raid", "heroic"} },
        { label = "Raid (Mythic)",     path = {"contentTypes", "raid", "mythic"} },
        { label = "Scenario (Normal)", path = {"contentTypes", "scenario", "normal"} },
        { label = "Scenario (Heroic)", path = {"contentTypes", "scenario", "heroic"} },
    }

    for i, info in ipairs(contentCheckboxes) do
        local checkbox = PRT.Components.GetCheckbox(scrollChild, info.label, function(value)
            local settings = EnsureSettingsTable()
            if #info.path == 2 then
                settings[info.path[1]][info.path[2]] = value
            else
                settings[info.path[1]][info.path[2]][info.path[3]] = value
            end
            PRT:ApplySettings("cooldownRoster")
        end)
        checkbox:SetPoint("TOPLEFT", 0, yOffset)
        contentCheckboxes[i].widget = checkbox

        local settings = GetSettings()
        local currentValue
        if #info.path == 2 then
            currentValue = settings[info.path[1]][info.path[2]]
        else
            currentValue = settings[info.path[1]][info.path[2]][info.path[3]]
        end
        checkbox:SetValue(currentValue)

        yOffset = yOffset - ROW_HEIGHT
    end

    -- Refresh all widget values from saved settings on show
    container:SetScript("OnShow", function()
        local settings = GetSettings()
        enabledCheckbox:SetValue(settings.enabled)
        lockCheckbox:SetValue(settings.lockFrames)

        for _, cat in ipairs(categoryCheckboxes) do
            cat.widget:SetValue(settings.categories[cat.key])
        end

        for _, info in ipairs(contentCheckboxes) do
            local currentValue
            if #info.path == 2 then
                currentValue = settings[info.path[1]][info.path[2]]
            else
                currentValue = settings[info.path[1]][info.path[2]][info.path[3]]
            end
            info.widget:SetValue(currentValue)
        end
    end)

    return container
end)

--------------------------------------------------------------------------------
-- Apply Callback
--------------------------------------------------------------------------------

PRT:RegisterApplyCallback("cooldownRoster", function()
    CooldownRoster:UpdateVisibility()
end)

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function CooldownRoster:Initialize()
    -- Clean up stale CooldownPrototype data
    local profile = PRT.Profiles:GetCurrent()
    profile.cooldownPrototype = nil

    -- Create category frames
    for _, categoryKey in ipairs({"defensive", "external", "movement"}) do
        categoryFrames[categoryKey] = CreateCategoryFrame(categoryKey)
        self:RestoreFramePosition(categoryKey)
        SetupDragging(categoryFrames[categoryKey], categoryKey)
    end

    -- Register events
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("INSPECT_READY")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", OnEvent)

    -- Start the inspection ticker
    StartInspectTicker()

    -- Initial scan if already in a group
    if IsInGroup() or IsInRaid() then
        self:ScanRoster()
        self:RebuildRoster()
        self:UpdateVisibility()
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == "PurplexityRaidTools" then
        CooldownRoster:Initialize()
        initFrame:UnregisterEvent("ADDON_LOADED")
    end
end)
