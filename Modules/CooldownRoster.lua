local PRT = PurplexityRaidTools
local CooldownRoster = {}
PRT.CooldownRoster = CooldownRoster
PRT:RegisterModule("cooldownRoster", CooldownRoster)

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

local FLAG_TO_CATEGORY = {
    RAID_COOLDOWN       = "defensive",
    EXTERNAL_DEFENSIVE  = "external",
    RAID_MOVEMENT       = "movement",
}

local BATTLE_RES_SPELL_ID = 20484

local rosterCooldowns = {}  -- computed array of {spellId, name, category, playerName, playerClass}
local categoryFrames = {}

local CATEGORY_INFO = {
    defensive = { label = "Defensives", order = 1 },
    external  = { label = "Externals",  order = 2 },
    movement  = { label = "Movement",   order = 3 },
}

local function OrderedCategoryKeys()
    local keys = {}
    for key in pairs(CATEGORY_INFO) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b)
        return CATEGORY_INFO[a].order < CATEGORY_INFO[b].order
    end)
    return keys
end

local function BattleResBarOnUpdate(bar)
    local brc = PRT.BattleResCounter
    if not brc then return end

    local brCharges, brInEncounter = brc:GetChargeState()
    if not brInEncounter then
        bar.spellText:SetText("Battle Res")
        bar.countdownText:Hide()
        return
    end

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

local function AddMemberCooldowns(member)
    if not member.specId then
        return
    end

    local specData = PRT.SpellData[member.specId]
    if not specData or not specData.abilities then
        return
    end

    for spellId, ability in pairs(specData.abilities) do
        local category = GetAbilityCategory(ability)
        -- With talent data, only show abilities in the player's talent set.
        -- Before talents load, fall back to showing everything for the spec.
        local known = not member.talents or member.talents[spellId]
        if category and known then
            table.insert(rosterCooldowns, {
                spellId = spellId,
                name = ability.name,
                category = category,
                playerName = member.name,
                playerClass = member.class,
            })
        end
    end
end

function CooldownRoster:RebuildRoster()
    rosterCooldowns = {}

    for _, member in pairs(PRT.GroupInspect.members) do
        AddMemberCooldowns(member)
    end

    if PRT.BattleResCounter and PRT.BattleResCounter.active then
        local brSettings = PRT:GetSetting("battleResCounter")
        if brSettings and brSettings.rosterRowEnabled then
            table.insert(rosterCooldowns, {
                spellId = BATTLE_RES_SPELL_ID,
                name = "Battle Res",
                category = "external",
                isBattleRes = true,
                sortBottom = true,
            })
        end
    end

    table.sort(rosterCooldowns, function(a, b)
        local orderA = CATEGORY_INFO[a.category] and CATEGORY_INFO[a.category].order or 99
        local orderB = CATEGORY_INFO[b.category] and CATEGORY_INFO[b.category].order or 99
        if orderA ~= orderB then return orderA < orderB end
        if a.sortBottom ~= b.sortBottom then return not a.sortBottom end
        if a.name ~= b.name then return a.name < b.name end
        return (a.playerName or "") < (b.playerName or "")
    end)
end

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

    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 2, 0)
    bar.icon = icon

    local spellText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spellText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    spellText:SetJustifyH("LEFT")
    bar.spellText = spellText

    -- Right-aligned; used by the battle res row's recharge timer.
    local countdownText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countdownText:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    countdownText:SetJustifyH("RIGHT")
    countdownText:Hide()
    bar.countdownText = countdownText

    local playerText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerText:SetPoint("LEFT", spellText, "RIGHT", 4, 0)
    playerText:SetPoint("RIGHT", countdownText, "LEFT", -4, 0)
    playerText:SetJustifyH("LEFT")
    bar.playerText = playerText

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

local function GatherCategoryEntries(categoryKey, categoryEnabled)
    local entries = {}
    if not categoryEnabled then
        return entries
    end
    for _, entry in ipairs(rosterCooldowns) do
        if entry.category == categoryKey then
            table.insert(entries, entry)
        end
    end
    return entries
end

local function ConfigureBar(bar, entry)
    bar.spellId = entry.spellId
    bar.icon:SetTexture(C_Spell.GetSpellTexture(entry.spellId))
    bar.spellText:SetText(entry.name)

    if entry.isBattleRes then
        bar.playerText:SetText("")
        bar:SetScript("OnUpdate", BattleResBarOnUpdate)
        return
    end

    local classColor = RAID_CLASS_COLORS[entry.playerClass]
    if classColor then
        bar.playerText:SetText(classColor:WrapTextInColorCode(entry.playerName))
    else
        bar.playerText:SetText(entry.playerName)
    end
    bar.countdownText:Hide()
    bar:SetScript("OnUpdate", nil)
end

local function ShowCategoryFrame(frame, entries)
    while #frame.bars < #entries do
        table.insert(frame.bars, CreateBar(frame))
    end

    for i, entry in ipairs(entries) do
        local bar = frame.bars[i]
        ConfigureBar(bar, entry)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", frame, "TOPLEFT", BACKDROP_PADDING, -(HEADER_HEIGHT + BACKDROP_PADDING + (i - 1) * (BAR_HEIGHT + BAR_SPACING)))
        bar:Show()
    end

    for i = #entries + 1, #frame.bars do
        frame.bars[i]:Hide()
    end

    frame:SetHeight(HEADER_HEIGHT + #entries * (BAR_HEIGHT + BAR_SPACING) + BACKDROP_PADDING * 2)
    UpdateBarWidths(frame)
    frame:Show()
end

function CooldownRoster:UpdateDisplay()
    local settings = PRT:GetSetting("cooldownRoster")
    local unlocked = settings and not settings.lockFrames

    for categoryKey, frame in pairs(categoryFrames) do
        local categoryEnabled = settings and settings.categories and settings.categories[categoryKey]
        local entries = GatherCategoryEntries(categoryKey, categoryEnabled)

        if not unlocked and (#entries == 0 or not self:ShouldDisplay()) then
            frame:Hide()
        else
            ShowCategoryFrame(frame, entries)
        end
    end
end

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

local function OnEvent(_, event)
    if event == "GROUP_ROSTER_UPDATE"
        or event == "ZONE_CHANGED_NEW_AREA"
        or event == "PLAYER_ENTERING_WORLD" then
        CooldownRoster:UpdateVisibility()
    end
end

PRT:RegisterTab("Cooldown Roster", function(parent)
    local function GetSettings()
        return PRT:GetSetting("cooldownRoster")
    end

    local function GetContentValue(settings, path)
        local value = settings
        for _, key in ipairs(path) do
            value = value[key]
        end
        return value
    end

    local function SetContentValue(settings, path, value)
        local node = settings
        for i = 1, #path - 1 do
            node = node[path[i]]
        end
        node[path[#path]] = value
    end

    local ROW_HEIGHT = 24

    return PRT.Components.GetSubTabGroup(parent, {
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

                yOffset = yOffset - 10
                local catHeader = PRT.Components.GetHeader(scrollChild, "Categories")
                catHeader:SetPoint("TOPLEFT", 0, yOffset)
                yOffset = yOffset - 28

                local categoryCheckboxes = {}

                for _, key in ipairs(OrderedCategoryKeys()) do
                    local checkbox = PRT.Components.GetCheckbox(scrollChild, CATEGORY_INFO[key].label, function(value)
                        local s = GetSettings()
                        if not s.categories then s.categories = {} end
                        s.categories[key] = value
                        PRT:ApplySettings("cooldownRoster")
                    end)
                    checkbox:SetPoint("TOPLEFT", 0, yOffset)
                    checkbox:SetValue(GetSettings().categories[key])
                    table.insert(categoryCheckboxes, { widget = checkbox, key = key })
                    yOffset = yOffset - ROW_HEIGHT
                end

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
                        SetContentValue(GetSettings(), info.path, value)
                        PRT:ApplySettings("cooldownRoster")
                    end)
                    checkbox:SetPoint("TOPLEFT", 0, yOffset)
                    contentCheckboxes[i].widget = checkbox
                    checkbox:SetValue(GetContentValue(GetSettings(), info.path))

                    yOffset = yOffset - ROW_HEIGHT
                end

                panel:SetScript("OnShow", function()
                    local settings = GetSettings()
                    enabledCheckbox:SetValue(settings.enabled)
                    lockCheckbox:SetValue(settings.lockFrames)

                    for _, cat in ipairs(categoryCheckboxes) do
                        cat.widget:SetValue(settings.categories[cat.key])
                    end

                    for _, info in ipairs(contentCheckboxes) do
                        info.widget:SetValue(GetContentValue(settings, info.path))
                    end
                end)
            end,
        },
    })
end)

PRT:RegisterApplyCallback("cooldownRoster", function()
    CooldownRoster:UpdateVisibility()
end)

function CooldownRoster:Initialize()
    -- Clean up stale CooldownPrototype data left behind by removed versions.
    local profile = PRT.Profiles:GetCurrent()
    profile.cooldownPrototype = nil

    for _, categoryKey in ipairs(OrderedCategoryKeys()) do
        categoryFrames[categoryKey] = CreateCategoryFrame(categoryKey)
        self:RestoreFramePosition(categoryKey)
        SetupDragging(categoryFrames[categoryKey], categoryKey)
    end

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
end

function CooldownRoster:OnDisable()
    self.eventFrame:UnregisterAllEvents()
    self.eventFrame:SetScript("OnEvent", nil)
    for _, frame in pairs(categoryFrames) do
        frame:Hide()
    end
end
