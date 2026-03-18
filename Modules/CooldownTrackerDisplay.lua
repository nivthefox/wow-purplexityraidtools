-- CooldownTrackerDisplay: Bar frames, layout, animation, and config tab
local PRT = PurplexityRaidTools
local Display = {}
PRT.CooldownTrackerDisplay = Display

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local STATE_AVAILABLE = PRT.CooldownTracker.STATE_AVAILABLE
local STATE_ACTIVE = PRT.CooldownTracker.STATE_ACTIVE
local STATE_ON_COOLDOWN = PRT.CooldownTracker.STATE_ON_COOLDOWN

local BAR_COLORS = {
    [STATE_AVAILABLE]  = { r = 0.2, g = 0.8, b = 0.2 },
    [STATE_ACTIVE]     = { r = 0.9, g = 0.7, b = 0.0 },
    [STATE_ON_COOLDOWN] = { r = 0.7, g = 0.2, b = 0.2 },
}

local CATEGORY_ORDER = { "defensive", "movement", "external" }
local CATEGORY_LABELS = {
    defensive = "Defensive Cooldowns",
    movement = "Movement Cooldowns",
    external = "External Cooldowns",
}

local HEADER_HEIGHT = 18
local HEADER_SPACING = 4
local BAR_SPACING = 1
local FRAME_PADDING = 6

-- Class colors for player name text
local CLASS_COLORS = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
    MONK        = { r = 0.00, g = 1.00, b = 0.60 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
}

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local anchorFrame = nil
local barFrames = {}           -- pool of bar frames keyed by cooldown key
local headerFrames = {}        -- pool of header FontStrings keyed by category
local updateTicker = nil

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function GetSettings()
    return PRT:GetSetting("cooldownTracker")
end

local function GetCooldownKey(playerName, spellId)
    return playerName .. ":" .. spellId
end

local function IsCategoryEnabled(category)
    local settings = GetSettings()
    if not settings or not settings.categories then
        return true
    end
    return settings.categories[category] ~= false
end

local function FormatTime(seconds)
    if seconds <= 0 then
        return "0"
    elseif seconds < 60 then
        return string.format("%.1f", seconds)
    else
        local minutes = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%d:%02d", minutes, secs)
    end
end

--------------------------------------------------------------------------------
-- State-Based Sorting
--------------------------------------------------------------------------------

local STATE_SORT_ORDER = {
    [STATE_ACTIVE] = 1,
    [STATE_AVAILABLE] = 2,
    [STATE_ON_COOLDOWN] = 3,
}

local function SortEntries(a, b)
    local orderA = STATE_SORT_ORDER[a.state] or 99
    local orderB = STATE_SORT_ORDER[b.state] or 99
    if orderA ~= orderB then
        return orderA < orderB
    end

    -- Within On Cooldown, sort by remaining time ascending
    if a.state == STATE_ON_COOLDOWN and b.state == STATE_ON_COOLDOWN then
        local remA = (a.expirationTime or 0) - GetTime()
        local remB = (b.expirationTime or 0) - GetTime()
        return remA < remB
    end

    -- Alphabetical fallback
    local nameA = (a.spellData.name or "") .. (a.playerName or "")
    local nameB = (b.spellData.name or "") .. (b.playerName or "")
    return nameA < nameB
end

--------------------------------------------------------------------------------
-- Anchor Frame
--------------------------------------------------------------------------------

local function CreateAnchorFrame()
    local frame = CreateFrame("Frame", "PRT_CooldownTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(250, 100)
    frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.6)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide()

    -- Movable behavior
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        local settings = GetSettings()
        if settings and settings.lockFrame then
            return
        end
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        -- Save position
        local point, _, relPoint, x, y = self:GetPoint(1)
        local profile = PRT.Profiles:GetCurrent()
        if not profile.cooldownTracker then
            profile.cooldownTracker = {}
        end
        profile.cooldownTracker.framePosition = {
            point = point,
            relPoint = relPoint,
            x = x,
            y = y,
        }
    end)

    return frame
end

local function RestoreFramePosition()
    if not anchorFrame then
        return
    end
    local settings = GetSettings()
    if settings and settings.framePosition then
        local pos = settings.framePosition
        anchorFrame:ClearAllPoints()
        anchorFrame:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 300, pos.y or 0)
    end
end

--------------------------------------------------------------------------------
-- Bar Frame Creation
--------------------------------------------------------------------------------

local function CreateBarFrame(parent)
    local settings = GetSettings()
    local barWidth = (settings and settings.barWidth) or 250
    local barHeight = (settings and settings.barHeight) or 20

    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(barWidth, barHeight)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar.bg:SetVertexColor(0.15, 0.15, 0.15, 0.8)

    -- Icon
    bar.icon = bar:CreateTexture(nil, "OVERLAY")
    bar.icon:SetSize(barHeight, barHeight)
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Name label
    bar.nameText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.nameText:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
    bar.nameText:SetPoint("RIGHT", bar, "RIGHT", -45, 0)
    bar.nameText:SetJustifyH("LEFT")

    -- Status text
    bar.statusText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.statusText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    bar.statusText:SetJustifyH("RIGHT")

    return bar
end

--------------------------------------------------------------------------------
-- Bar Update
--------------------------------------------------------------------------------

local function UpdateBar(bar, entry)
    local spellData = entry.spellData
    local color = BAR_COLORS[entry.state]

    -- Color
    bar:SetStatusBarColor(color.r, color.g, color.b)

    -- Icon
    local iconId = select(3, GetSpellInfo(spellData.spellId))
    if iconId then
        bar.icon:SetTexture(iconId)
    end

    -- Name + player (class colored)
    local classColor = CLASS_COLORS[entry.classToken] or { r = 1, g = 1, b = 1 }
    local coloredName = string.format("|cff%02x%02x%02x%s|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        entry.playerName or "Unknown")
    bar.nameText:SetText(spellData.name .. " (" .. coloredName .. ")")

    -- Bar fill and status text based on state
    local now = GetTime()

    if entry.state == STATE_AVAILABLE then
        bar:SetValue(1)
        bar.statusText:SetText("Available")

    elseif entry.state == STATE_ACTIVE then
        local remaining = (entry.expirationTime or now) - now
        if remaining < 0 then
            remaining = 0
        end
        local duration = entry.buffDuration or 1
        if duration > 0 then
            bar:SetValue(remaining / duration)
        else
            bar:SetValue(0)
        end
        bar.statusText:SetText(FormatTime(remaining))

    elseif entry.state == STATE_ON_COOLDOWN then
        local remaining = (entry.expirationTime or now) - now
        if remaining < 0 then
            remaining = 0
        end
        local cooldownTotal = entry.spellData.cooldown - (entry.buffDuration or 0)
        if cooldownTotal > 0 then
            local elapsed = cooldownTotal - remaining
            bar:SetValue(elapsed / cooldownTotal)
        else
            bar:SetValue(1)
        end
        bar.statusText:SetText(FormatTime(remaining))
    end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function UpdateLayout()
    if not anchorFrame then
        return
    end

    local settings = GetSettings()
    local barWidth = (settings and settings.barWidth) or 250
    local barHeight = (settings and settings.barHeight) or 20
    local cooldowns = PRT.CooldownTracker:GetTrackedCooldowns()

    -- Group entries by category
    local byCategory = {}
    for _, category in ipairs(CATEGORY_ORDER) do
        byCategory[category] = {}
    end

    for _, entry in pairs(cooldowns) do
        local cat = entry.spellData.category
        if byCategory[cat] and IsCategoryEnabled(cat) then
            table.insert(byCategory[cat], entry)
        end
    end

    -- Sort each category
    for _, entries in pairs(byCategory) do
        table.sort(entries, SortEntries)
    end

    -- Hide all existing bar frames first
    for _, bar in pairs(barFrames) do
        bar:Hide()
    end
    for _, header in pairs(headerFrames) do
        header:Hide()
    end

    local yOffset = -FRAME_PADDING
    local hasContent = false

    for _, category in ipairs(CATEGORY_ORDER) do
        local entries = byCategory[category]
        if #entries > 0 then
            hasContent = true

            -- Category header
            if not headerFrames[category] then
                local header = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                header:SetJustifyH("LEFT")
                headerFrames[category] = header
            end
            local header = headerFrames[category]
            header:SetText(CATEGORY_LABELS[category])
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", FRAME_PADDING, yOffset)
            header:SetPoint("RIGHT", anchorFrame, "RIGHT", -FRAME_PADDING, 0)
            header:Show()

            yOffset = yOffset - HEADER_HEIGHT - HEADER_SPACING

            -- Bars
            for _, entry in ipairs(entries) do
                local key = GetCooldownKey(entry.playerName, entry.spellData.spellId)
                local bar = barFrames[key]
                if not bar then
                    bar = CreateBarFrame(anchorFrame)
                    barFrames[key] = bar
                end

                bar:SetSize(barWidth - (FRAME_PADDING * 2), barHeight)
                bar.icon:SetSize(barHeight, barHeight)
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", FRAME_PADDING, yOffset)
                UpdateBar(bar, entry)
                bar:Show()

                yOffset = yOffset - barHeight - BAR_SPACING
            end

            yOffset = yOffset - HEADER_SPACING
        end
    end

    -- Remove orphaned bar frames
    local validKeys = {}
    for _, entry in pairs(cooldowns) do
        validKeys[GetCooldownKey(entry.playerName, entry.spellData.spellId)] = true
    end
    for key, bar in pairs(barFrames) do
        if not validKeys[key] then
            bar:Hide()
            bar:SetParent(nil)
            barFrames[key] = nil
        end
    end

    -- Resize anchor frame
    local totalHeight = math.abs(yOffset) + FRAME_PADDING
    if hasContent then
        anchorFrame:SetWidth(barWidth)
        anchorFrame:SetHeight(totalHeight)
    else
        anchorFrame:SetHeight(1)
    end
end

--------------------------------------------------------------------------------
-- Update Ticker (smooth bar animation)
--------------------------------------------------------------------------------

local function HasAnimatingBars()
    local cooldowns = PRT.CooldownTracker:GetTrackedCooldowns()
    for _, entry in pairs(cooldowns) do
        if entry.state == STATE_ACTIVE or entry.state == STATE_ON_COOLDOWN then
            return true
        end
    end
    return false
end

local function OnUpdateTick()
    if not anchorFrame or not anchorFrame:IsShown() then
        return
    end

    local cooldowns = PRT.CooldownTracker:GetTrackedCooldowns()
    for _, entry in pairs(cooldowns) do
        local bar = barFrames[GetCooldownKey(entry.playerName, entry.spellData.spellId)]
        if bar and bar:IsShown() then
            UpdateBar(bar, entry)
        end
    end

    -- Stop ticker if nothing is animating
    if not HasAnimatingBars() then
        if updateTicker then
            updateTicker:Cancel()
            updateTicker = nil
        end
    end
end

local function EnsureUpdateTicker()
    if not updateTicker and HasAnimatingBars() then
        updateTicker = C_Timer.NewTicker(0.1, OnUpdateTick)
    end
end

--------------------------------------------------------------------------------
-- Visibility Management
--------------------------------------------------------------------------------

local function UpdateVisibility()
    if not anchorFrame then
        return
    end

    local tracker = PRT.CooldownTracker
    if not tracker:IsEnabled() then
        anchorFrame:Hide()
        return
    end

    local settings = GetSettings()
    if settings and settings.showOnlyInCombat and not InCombatLockdown() then
        anchorFrame:Hide()
        return
    end

    anchorFrame:Show()
end

--------------------------------------------------------------------------------
-- Public API (called by CooldownTracker module)
--------------------------------------------------------------------------------

function Display:OnStateChanged()
    if not anchorFrame then
        return
    end
    UpdateLayout()
    UpdateVisibility()
    EnsureUpdateTicker()
end

function Display:OnModuleEnabled()
    if not anchorFrame then
        anchorFrame = CreateAnchorFrame()
        RestoreFramePosition()
    end
    UpdateLayout()
    UpdateVisibility()
    EnsureUpdateTicker()
end

function Display:OnModuleDisabled()
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end

    for _, bar in pairs(barFrames) do
        bar:Hide()
    end
    for _, header in pairs(headerFrames) do
        header:Hide()
    end

    if anchorFrame then
        anchorFrame:Hide()
    end
end

function Display:ApplySettings()
    RestoreFramePosition()
    UpdateLayout()
    UpdateVisibility()
end

-- Register apply callback so config changes take effect
PRT:RegisterApplyCallback("cooldownTrackerDisplay", function()
    Display:ApplySettings()
end)

-- Listen for combat state changes to support showOnlyInCombat
local combatVisFrame = CreateFrame("Frame")
combatVisFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatVisFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatVisFrame:SetScript("OnEvent", function()
    UpdateVisibility()
end)

--------------------------------------------------------------------------------
-- Config Tab
--------------------------------------------------------------------------------

PRT:RegisterTab("Cooldowns", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", 8, -60)
    container:SetPoint("BOTTOMRIGHT", -8, 8)
    container:Hide()

    local yOffset = 0
    local ROW_HEIGHT = 24

    local function GetProfile()
        return PRT.Profiles:GetCurrent()
    end

    local function EnsureSettingsTable()
        local profile = GetProfile()
        if not profile.cooldownTracker then
            profile.cooldownTracker = {}
            for k, v in pairs(PRT.defaults.cooldownTracker) do
                if type(v) == "table" then
                    profile.cooldownTracker[k] = {}
                    for k2, v2 in pairs(v) do
                        profile.cooldownTracker[k][k2] = v2
                    end
                else
                    profile.cooldownTracker[k] = v
                end
            end
        end
        return profile.cooldownTracker
    end

    local function ApplyAll()
        PRT:ApplySettings("cooldownTracker")
        PRT:ApplySettings("cooldownTrackerDisplay")
    end

    -- General Section
    local generalHeader = PRT.Components.GetHeader(container, "General")
    generalHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local enabledCheckbox = PRT.Components.GetCheckbox(container, "Enable Cooldown Tracker", function(value)
        EnsureSettingsTable().enabled = value
        ApplyAll()
    end)
    enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    enabledCheckbox:SetValue(GetSettings().enabled)
    yOffset = yOffset - ROW_HEIGHT

    local showOnlyInCombatCheckbox = PRT.Components.GetCheckbox(container, "Show Only in Combat", function(value)
        EnsureSettingsTable().showOnlyInCombat = value
        ApplyAll()
    end)
    showOnlyInCombatCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    showOnlyInCombatCheckbox:SetValue(GetSettings().showOnlyInCombat)
    yOffset = yOffset - ROW_HEIGHT

    local lockFrameCheckbox = PRT.Components.GetCheckbox(container, "Lock Frame Position", function(value)
        EnsureSettingsTable().lockFrame = value
    end)
    lockFrameCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    lockFrameCheckbox:SetValue(GetSettings().lockFrame)
    yOffset = yOffset - ROW_HEIGHT

    -- Categories Section
    yOffset = yOffset - 10
    local catHeader = PRT.Components.GetHeader(container, "Categories")
    catHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local defensiveCheckbox = PRT.Components.GetCheckbox(container, "Track Defensive Cooldowns", function(value)
        EnsureSettingsTable().categories.defensive = value
        ApplyAll()
    end)
    defensiveCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    defensiveCheckbox:SetValue(GetSettings().categories.defensive)
    yOffset = yOffset - ROW_HEIGHT

    local movementCheckbox = PRT.Components.GetCheckbox(container, "Track Movement Cooldowns", function(value)
        EnsureSettingsTable().categories.movement = value
        ApplyAll()
    end)
    movementCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    movementCheckbox:SetValue(GetSettings().categories.movement)
    yOffset = yOffset - ROW_HEIGHT

    local externalCheckbox = PRT.Components.GetCheckbox(container, "Track External Cooldowns", function(value)
        EnsureSettingsTable().categories.external = value
        ApplyAll()
    end)
    externalCheckbox:SetPoint("TOPLEFT", 0, yOffset)
    externalCheckbox:SetValue(GetSettings().categories.external)
    yOffset = yOffset - ROW_HEIGHT

    -- Appearance Section
    yOffset = yOffset - 10
    local appearanceHeader = PRT.Components.GetHeader(container, "Appearance")
    appearanceHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local barHeightSlider = PRT.Components.GetSliderWithInput(container, "Bar Height", 12, 40, 1, false, function(value)
        EnsureSettingsTable().barHeight = value
        ApplyAll()
    end)
    barHeightSlider:SetPoint("TOPLEFT", 0, yOffset)
    barHeightSlider:SetValue(GetSettings().barHeight)
    yOffset = yOffset - ROW_HEIGHT

    local barWidthSlider = PRT.Components.GetSliderWithInput(container, "Bar Width", 150, 500, 10, false, function(value)
        EnsureSettingsTable().barWidth = value
        ApplyAll()
    end)
    barWidthSlider:SetPoint("TOPLEFT", 0, yOffset)
    barWidthSlider:SetValue(GetSettings().barWidth)
    yOffset = yOffset - ROW_HEIGHT

    return container
end)
