-- CooldownRoster: Shows available raid cooldowns based on group composition
local PRT = PurplexityRaidTools
local CooldownRoster = {}
PRT.CooldownRoster = CooldownRoster
PRT:RegisterModule("cooldownRoster", CooldownRoster)

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
    usageTracking = {
        enabled = true,
        barTexture = "Interface\\TargetingFrame\\UI-StatusBar",
        barTextureName = nil,  -- LSM name; nil = default
    },
}

--------------------------------------------------------------------------------
-- Flag-to-Category Mapping
--------------------------------------------------------------------------------

local FLAG_TO_CATEGORY = {
    RAID_COOLDOWN       = "defensive",
    EXTERNAL_DEFENSIVE  = "external",
    RAID_MOVEMENT       = "movement",
}

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local rosterCooldowns = {}  -- computed array of {spellId, name, category, playerName, playerClass}

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

--- Return a bright, saturated tint of the player's class color (for active bars).
local function GetActiveColor(classToken)
    local c = RAID_CLASS_COLORS[classToken]
    if not c then return 0.5, 0.8, 0.5 end
    return math.min(c.r * 1.3, 1), math.min(c.g * 1.3, 1), math.min(c.b * 1.3, 1)
end

--- Return a desaturated, darkened version of the player's class color (for cooldown bars).
local function GetCooldownColor(classToken)
    local c = RAID_CLASS_COLORS[classToken]
    if not c then return 0.3, 0.3, 0.3 end
    local gray = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
    local t = 0.5
    return (c.r * (1 - t) + gray * t) * 0.6,
           (c.g * (1 - t) + gray * t) * 0.6,
           (c.b * (1 - t) + gray * t) * 0.6
end

--- OnUpdate handler for bars with trackable abilities. Runs every frame to
--- pick up state changes from the tracker (which has no callback mechanism).
local function BarOnUpdate(bar)
    local state, remaining, total = PRT.CooldownTracker:GetState(bar.guid, bar.spellId)

    if state == "ready" then
        if bar.trackerState ~= "ready" then
            bar.statusBar:Hide()
            bar.countdownText:Hide()
            bar.trackerState = "ready"
            bar.lastCountdown = nil
        end
        return
    end

    -- Active or cooldown: show the bar
    if total > 0 then
        bar.statusBar:SetValue(remaining / total)
    else
        bar.statusBar:SetValue(0)
    end

    local shown = math.ceil(remaining)
    if shown ~= bar.lastCountdown then
        bar.countdownText:SetText(shown)
        bar.lastCountdown = shown
    end

    -- Update color and visibility on state transitions
    if state ~= bar.trackerState then
        bar.trackerState = state
        if state == "active" then
            bar.statusBar:SetStatusBarColor(GetActiveColor(bar.playerClass))
        else
            bar.statusBar:SetStatusBarColor(GetCooldownColor(bar.playerClass))
        end
        bar.statusBar:Show()
        bar.countdownText:Show()
    end
end

--- OnUpdate handler for the battle res summary bar. Reads charge state from
--- BattleResCounter rather than CooldownTracker.
local function BattleResBarOnUpdate(bar)
    local brc = PRT.BattleResCounter
    if not brc then return end
    local brCharges, brInEncounter = brc:GetChargeState()
    if brInEncounter then
        local label = "Battle Res "
        if brCharges == 0 then
            label = label .. "|cffff0000(0)|r"
        else
            label = label .. "(" .. brCharges .. ")"
        end
        bar.spellText:SetText(label)
        local timer = brc:GetTimerText()
        if timer ~= "" then
            bar.countdownText:SetText(timer)
            bar.countdownText:Show()
        else
            bar.countdownText:Hide()
        end
    else
        bar.spellText:SetText("Battle Res")
        bar.countdownText:Hide()
    end
end

--- Return the display category for an ability based on its flags, or nil if it
--- does not belong in any CooldownRoster category.
local function GetAbilityCategory(ability)
    if not ability.flags then
        return nil
    end
    for i = 1, #ability.flags do
        local cat = FLAG_TO_CATEGORY[ability.flags[i]]
        if cat then
            return cat
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Roster Building
--------------------------------------------------------------------------------

function CooldownRoster:RebuildRoster()
    rosterCooldowns = {}

    for guid, member in pairs(PRT.GroupInspect.members) do
        local specId = member.specId
        if specId then
            local specData = PRT.SpellData[specId]
            if specData and specData.abilities then
                for spellId, ability in pairs(specData.abilities) do
                    local category = GetAbilityCategory(ability)
                    if category then
                        -- When talent data is available, only show the ability
                        -- if its spellId appears in the player's talent set.
                        -- If talents haven't loaded yet, fall back to showing
                        -- everything for the spec.
                        local show = true
                        if member.talents then
                            show = member.talents[spellId] or false
                        end

                        if show then
                            table.insert(rosterCooldowns, {
                                spellId = spellId,
                                name = ability.name,
                                category = category,
                                playerName = member.name,
                                playerClass = member.class,
                                guid = guid,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Inject battle res row if BattleResCounter is active and roster row enabled
    if PRT.BattleResCounter and PRT.BattleResCounter.active then
        local brSettings = PRT:GetSetting("battleResCounter")
        if brSettings and brSettings.rosterRowEnabled then
            table.insert(rosterCooldowns, {
                spellId = 20484,
                name = "Battle Res",
                category = "external",
                isBattleRes = true,
                sortBottom = true,
            })
        end
    end

    -- Sort: category order, then sortBottom last, then spell name, then player name
    table.sort(rosterCooldowns, function(a, b)
        local orderA = CATEGORY_INFO[a.category] and CATEGORY_INFO[a.category].order or 99
        local orderB = CATEGORY_INFO[b.category] and CATEGORY_INFO[b.category].order or 99
        if orderA ~= orderB then return orderA < orderB end
        if a.sortBottom ~= b.sortBottom then return not a.sortBottom end
        if a.name ~= b.name then return a.name < b.name end
        return (a.playerName or "") < (b.playerName or "")
    end)

    -- Build a talent map compatible with CooldownTracker:OnRosterChanged
    local talents = {}
    for guid, member in pairs(PRT.GroupInspect.members) do
        if member.talents then
            talents[guid] = member.talents
        end
    end

    -- Notify the tracker so it knows which abilities to watch for
    PRT.CooldownTracker:OnRosterChanged(rosterCooldowns, talents)
end

--------------------------------------------------------------------------------
-- Display
--------------------------------------------------------------------------------

local BAR_HEIGHT = 20
local BAR_WIDTH = 200
local MIN_BAR_WIDTH = 120
local ICON_SIZE = 18
local BAR_SPACING = 2
local HEADER_HEIGHT = 20
local BACKDROP_PADDING = 4

local function CreateBar(parent)
    local bar = CreateFrame("Frame", nil, parent)
    local barWidth = parent:GetWidth() - BACKDROP_PADDING * 2
    bar:SetSize(barWidth, BAR_HEIGHT)

    -- Status bar for active/cooldown display (behind everything)
    local statusBar = CreateFrame("StatusBar", nil, bar)
    statusBar:SetAllPoints()
    local settings = PRT:GetSetting("cooldownRoster")
    local texturePath = settings and settings.usageTracking and settings.usageTracking.barTexture
        or "Interface\\TargetingFrame\\UI-StatusBar"
    statusBar:SetStatusBarTexture(texturePath)
    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetValue(0)
    statusBar:SetFrameLevel(bar:GetFrameLevel())
    statusBar:Hide()
    bar.statusBar = statusBar

    -- Dark background behind the status bar
    local statusBg = statusBar:CreateTexture(nil, "BACKGROUND")
    statusBg:SetAllPoints()
    statusBg:SetColorTexture(0, 0, 0, 0.4)

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 2, 0)
    bar.icon = icon

    local spellText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    spellText:SetJustifyH("LEFT")
    bar.spellText = spellText

    -- Countdown text (right side, visible during active/cooldown)
    local countdownText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countdownText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    countdownText:SetJustifyH("RIGHT")
    countdownText:Hide()
    bar.countdownText = countdownText

    -- Player text sits between spell and countdown
    local playerText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerText:SetPoint("LEFT", spellText, "RIGHT", 4, 0)
    playerText:SetPoint("RIGHT", countdownText, "LEFT", -4, 0)
    playerText:SetJustifyH("LEFT")
    bar.playerText = playerText

    bar.trackerState = nil
    bar.lastCountdown = nil
    bar.guid = nil
    bar.playerClass = nil

    bar:EnableMouse(true)
    bar:SetScript("OnEnter", function(self)
        if self.spellId then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetSpellByID(self.spellId)
            GameTooltip:Show()
        end
    end)
    bar:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

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

    -- Resize handle on the right edge
    local resizeHandle = CreateFrame("Frame", nil, frame)
    resizeHandle:SetWidth(6)
    resizeHandle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    resizeHandle:EnableMouse(true)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 1)

    local handleTex = resizeHandle:CreateTexture(nil, "OVERLAY")
    handleTex:SetAllPoints()
    handleTex:SetColorTexture(1, 1, 1, 0.3)
    resizeHandle.texture = handleTex

    resizeHandle:SetScript("OnEnter", function(self)
        self.texture:SetColorTexture(1, 1, 1, 0.6)
    end)
    resizeHandle:SetScript("OnLeave", function(self)
        self.texture:SetColorTexture(1, 1, 1, 0.3)
    end)

    resizeHandle:Hide()
    frame.resizeHandle = resizeHandle

    frame.bars = {}
    frame.categoryKey = categoryKey

    return frame
end

local function UpdateBarWidths(frame)
    local barWidth = frame:GetWidth() - BACKDROP_PADDING * 2
    local textAreaWidth = barWidth - ICON_SIZE - 10
    local spellTextWidth = math.floor(textAreaWidth * 0.65)
    for _, bar in ipairs(frame.bars) do
        bar:SetWidth(barWidth)
        bar.spellText:SetWidth(spellTextWidth)
    end
end

local function SetupDragging(frame, categoryKey)
    local settings = PRT:GetSetting("cooldownRoster")
    local locked = settings and settings.lockFrames
    local unlocked = not locked

    frame:SetMovable(unlocked)
    frame:SetResizable(unlocked)
    frame:SetResizeBounds(MIN_BAR_WIDTH + BACKDROP_PADDING * 2, BAR_HEIGHT + BACKDROP_PADDING * 2)
    frame:EnableMouse(unlocked)

    if unlocked then
        frame:RegisterForDrag("LeftButton")
        frame.resizeHandle:Show()
    else
        frame:RegisterForDrag()
        frame.resizeHandle:Hide()
    end

    frame:SetScript("OnDragStart", function(self)
        if not self:IsMovable() then return end
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        CooldownRoster:SaveFramePosition(categoryKey)
    end)

    frame.resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not frame:IsResizable() then return end
        frame:StartSizing("RIGHT")
    end)

    frame.resizeHandle:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        UpdateBarWidths(frame)
        CooldownRoster:SaveFramePosition(categoryKey)
    end)

    frame:SetScript("OnSizeChanged", function(self)
        -- Clamp to minimum width
        local minWidth = MIN_BAR_WIDTH + BACKDROP_PADDING * 2
        if self:GetWidth() < minWidth then
            self:SetWidth(minWidth)
        end
        UpdateBarWidths(self)
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

    -- Normalize to TOPLEFT so frames always grow downward on resize
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = frame:GetLeft() * scale
    local y = (frame:GetTop() - UIParent:GetTop()) * scale

    profile.cooldownRoster.positions[categoryKey] = {
        point = "TOPLEFT",
        x = x,
        y = y,
        width = frame:GetWidth() - BACKDROP_PADDING * 2,
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
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
        local savedWidth = pos.width or BAR_WIDTH
        frame:SetWidth(savedWidth + BACKDROP_PADDING * 2)
    else
        -- Default positions: stacked vertically on right side, anchored TOPLEFT
        local defaults = {
            defensive = { -410, -200 },
            external  = { -410, -350 },
            movement  = { -410, -500 },
        }
        local def = defaults[categoryKey]
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", def[1], def[2])
    end
end

function CooldownRoster:UpdateDragging()
    for categoryKey, frame in pairs(categoryFrames) do
        SetupDragging(frame, categoryKey)
    end
    self:UpdateVisibility()
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

        local unlocked = settings and not settings.lockFrames
        if not unlocked and (#entries == 0 or not self:ShouldDisplay()) then
            frame:Hide()
        else
            -- Ensure we have enough bars
            while #frame.bars < #entries do
                table.insert(frame.bars, CreateBar(frame))
            end

            -- Configure and show bars
            for i, entry in ipairs(entries) do
                local bar = frame.bars[i]
                bar.spellId = entry.spellId
                bar.guid = entry.guid
                bar.playerClass = entry.playerClass
                bar.icon:SetTexture(C_Spell.GetSpellTexture(entry.spellId))
                bar.spellText:SetText(entry.name)

                if entry.isBattleRes then
                    -- Battle res summary row: no player, custom OnUpdate
                    bar.playerText:SetText("")
                    bar.statusBar:Hide()
                    bar.trackerState = nil
                    bar.lastCountdown = nil
                    bar:SetScript("OnUpdate", BattleResBarOnUpdate)
                else
                    local classColor = RAID_CLASS_COLORS[entry.playerClass]
                    if classColor then
                        bar.playerText:SetText(classColor:WrapTextInColorCode(entry.playerName))
                    else
                        bar.playerText:SetText(entry.playerName)
                    end

                    -- For trackable abilities with usage tracking enabled, always
                    -- attach OnUpdate so we pick up state changes from the tracker
                    -- in real time. BarOnUpdate handles show/hide based on state.
                    local trackingEnabled = settings and settings.usageTracking
                        and settings.usageTracking.enabled
                    if trackingEnabled and PRT.CooldownTracker:IsTrackable(entry.spellId) then
                        bar.trackerState = nil  -- force a visual refresh on next OnUpdate
                        bar:SetScript("OnUpdate", BarOnUpdate)
                    else
                        bar.statusBar:Hide()
                        bar.countdownText:Hide()
                        bar.trackerState = nil
                        bar.lastCountdown = nil
                        bar:SetScript("OnUpdate", nil)
                    end
                end

                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", frame, "TOPLEFT", BACKDROP_PADDING, -(HEADER_HEIGHT + BACKDROP_PADDING + (i - 1) * (BAR_HEIGHT + BAR_SPACING)))
                bar:Show()
            end

            -- Hide excess bars
            for i = #entries + 1, #frame.bars do
                frame.bars[i]:Hide()
            end

            -- Resize frame height to fit content, preserving current width
            local contentHeight = HEADER_HEIGHT + #entries * (BAR_HEIGHT + BAR_SPACING) + BACKDROP_PADDING * 2
            frame:SetHeight(contentHeight)
            UpdateBarWidths(frame)
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
    local settings = PRT:GetSetting("cooldownRoster")
    local unlocked = settings and not settings.lockFrames

    if not unlocked and not self:ShouldDisplay() then
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

local function OnEvent(_, event)
    if event == "GROUP_ROSTER_UPDATE"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_ENTERING_WORLD" then
        CooldownRoster:UpdateVisibility()
    end
end

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Cooldown Roster", function(parent)
    local function GetSettings()
        return PRT:GetSetting("cooldownRoster")
    end

    local ROW_HEIGHT = 24

    return PRT.Components.GetSubTabGroup(parent, {
        -----------------------------------------------------------------
        -- General sub-tab
        -----------------------------------------------------------------
        {
            name = "General",
            setup = function(panel)
                local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
                scrollFrame:SetPoint("TOPLEFT", 0, 0)
                scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

                local scrollChild = CreateFrame("Frame", nil, scrollFrame)
                scrollChild:SetWidth(panel:GetWidth() - 40)
                scrollChild:SetHeight(600)
                scrollFrame:SetScrollChild(scrollChild)

                local yOffset = 0

                -- General Section
                local generalHeader = PRT.Components.GetHeader(scrollChild, "General")
                generalHeader:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - 28

                local enabledCheckbox = PRT.Components.GetCheckbox(scrollChild, "Enabled", function(value)
                    GetSettings().enabled = value
                    PRT:ApplySettings("cooldownRoster")
                end)
                enabledCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                enabledCheckbox:SetValue(GetSettings().enabled)
                yOffset = yOffset - ROW_HEIGHT

                local lockCheckbox = PRT.Components.GetCheckbox(scrollChild, "Locked", function(value)
                    GetSettings().lockFrames = value
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
                        local s = GetSettings()
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
                        local settings = GetSettings()
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

                -- Refresh all widget values on show
                panel:SetScript("OnShow", function()
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
            end,
        },

        -----------------------------------------------------------------
        -- Usage Tracking sub-tab
        -----------------------------------------------------------------
        {
            name = "Usage Tracking",
            setup = function(panel)
                local yOffset = 0

                local header = PRT.Components.GetHeader(panel, "Usage Tracking")
                header:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - 28

                local trackingCheckbox = PRT.Components.GetCheckbox(panel, "Enabled", function(value)
                    local s = GetSettings()
                    if not s.usageTracking then s.usageTracking = {} end
                    s.usageTracking.enabled = value
                    PRT:ApplySettings("cooldownRoster")
                end)
                trackingCheckbox:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - ROW_HEIGHT

                -- Bar Texture dropdown (via LibSharedMedia)
                yOffset = yOffset - 10
                local textureHeader = PRT.Components.GetHeader(panel, "Bar Texture")
                textureHeader:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - 28

                local function ListTextures()
                    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                    if not LSM then
                        return {{ name = "Default", value = "Interface\\TargetingFrame\\UI-StatusBar" }}
                    end
                    local names = LSM:List("statusbar")
                    local items = {}
                    for _, name in ipairs(names) do
                        items[#items + 1] = { name = name, value = name }
                    end
                    return items
                end

                local function GetCurrentTextureName()
                    local s = GetSettings()
                    local tracking = s and s.usageTracking
                    return tracking and tracking.barTextureName or nil
                end

                local textureDropdown = PRT.Components.GetBasicDropdown(
                    panel,
                    "Texture",
                    ListTextures,
                    function(value)
                        local current = GetCurrentTextureName()
                        return current == value
                    end,
                    function(value)
                        local s = GetSettings()
                        if not s.usageTracking then s.usageTracking = {} end
                        -- Store the LSM name; resolve to path at render time
                        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
                        if LSM then
                            s.usageTracking.barTexture = LSM:Fetch("statusbar", value) or value
                            s.usageTracking.barTextureName = value
                        else
                            s.usageTracking.barTexture = value
                        end
                        PRT:ApplySettings("cooldownRoster")
                    end
                )
                textureDropdown:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - ROW_HEIGHT

                -- Refresh on show
                panel:SetScript("OnShow", function()
                    local s = GetSettings()
                    local tracking = s and s.usageTracking
                    trackingCheckbox:SetValue(tracking and tracking.enabled or false)
                    textureDropdown:SetValue()
                end)
            end,
        },
    })
end)

--------------------------------------------------------------------------------
-- Apply Callback
--------------------------------------------------------------------------------

--- Update all existing bar textures from settings.
local function RefreshBarTextures()
    local settings = PRT:GetSetting("cooldownRoster")
    local texturePath = settings and settings.usageTracking and settings.usageTracking.barTexture
        or "Interface\\TargetingFrame\\UI-StatusBar"
    for _, frame in pairs(categoryFrames) do
        for _, bar in ipairs(frame.bars) do
            if bar.statusBar then
                bar.statusBar:SetStatusBarTexture(texturePath)
            end
        end
    end
end

PRT:RegisterApplyCallback("cooldownRoster", function()
    -- Re-evaluate tracker enabled state
    local settings = PRT:GetSetting("cooldownRoster")
    if settings and settings.usageTracking and settings.usageTracking.enabled then
        if CooldownRoster.active then
            PRT.CooldownTracker:Enable()
        end
    else
        PRT.CooldownTracker:Disable()
    end

    RefreshBarTextures()
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

    -- Listen for GroupInspect data changes
    PRT.GroupInspect:Listen(function()
        if CooldownRoster.active then
            CooldownRoster:RebuildRoster()
            CooldownRoster:UpdateDisplay()
        end
    end)
end

function CooldownRoster:IsActivatable()
    return IsInGroup() or IsInRaid()
end

function CooldownRoster:OnEnable()
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    self:RebuildRoster()
    self:UpdateVisibility()

    local settings = PRT:GetSetting("cooldownRoster")
    if settings and settings.usageTracking and settings.usageTracking.enabled then
        PRT.CooldownTracker:Enable()
    end
end

function CooldownRoster:OnDisable()
    PRT.CooldownTracker:Disable()

    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)
    for _, frame in pairs(categoryFrames) do
        frame:Hide()
    end
end
