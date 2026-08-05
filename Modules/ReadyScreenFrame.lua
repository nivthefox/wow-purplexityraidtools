local PRT = PurplexityRaidTools

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 24
local COLUMN_PADDING = 4
local BACKDROP_PADDING = 8

local COL_NAME_WIDTH = 130
local COL_ICON_WIDTH = 24
local COL_VERSION_WIDTH = 50

local ROLE_ATLASES = {
    TANK = "groupfinder-icon-role-large-tank",
    HEALER = "groupfinder-icon-role-large-heal",
    DAMAGER = "groupfinder-icon-role-large-dps",
}

-- Texture paths or verified atlas names. The old table passed the NAMES of
-- Blizzard's READY_CHECK_*_TEXTURE Lua constants to SetAtlas, which threw
-- "invalid atlas" and aborted Refresh before the ready column ever rendered.
local READY_ICONS = {
    ready = { texture = "Interface\\RaidFrame\\ReadyCheck-Ready" },
    notready = { texture = "Interface\\RaidFrame\\ReadyCheck-NotReady" },
    pending = { texture = "Interface\\RaidFrame\\ReadyCheck-Waiting" },
    dead = { atlas = "poi-graveyard-neutral" },
    -- Disconnect-Icon's art is small inside a padded canvas; oversize it so the
    -- visible plug matches the other icons. The padding overflow is transparent.
    offline = { texture = "Interface\\CharacterFrame\\Disconnect-Icon", scale = 1.6 },
}

-- Question-mark icon shown when spell data has not loaded yet. A nil texture
-- must never hide a column or a has-the-buff cell: an invisible column reads
-- as "this buff is not audited", which is a lie.
local FALLBACK_ICON = 134400

local function SpellTexture(spellId)
    if not spellId then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellId)
    end
    return nil
end

-- GetSpellTexture returns nil for spells not in the client's spell cache
-- (anything outside your own spellbook on a fresh session). Request an async
-- load for every audited buff; SPELL_DATA_LOAD_RESULT refreshes the frame
-- when the data arrives. Re-requesting already-cached spells is a no-op.
local function RequestBuffSpellData(columns)
    if not (C_Spell and C_Spell.RequestLoadSpellData) then return end
    for _, col in ipairs(columns) do
        if col.spellId then
            C_Spell.RequestLoadSpellData(col.spellId)
        end
    end
end

local function DecodeVersion(encoded)
    if not encoded then return nil end
    local major = math.floor(encoded / 1000000)
    local minor = math.floor((encoded % 1000000) / 1000)
    local patch = encoded % 1000
    return string.format("%d.%d.%d", major, minor, patch)
end

local function GetBuffColumns()
    local columns = {}
    for _, buff in ipairs(PRT.RAID_BUFFS) do
        table.insert(columns, { name = buff.name, spellId = buff.spellId })
    end
    table.insert(columns, { name = PRT.SOULSTONE_BUFF_NAME, spellId = PRT.SOULSTONE_SPELL_ID })
    return columns
end

local function GetFixedColumnsWidth(showReady)
    local w = COL_NAME_WIDTH + COLUMN_PADDING
        + COL_ICON_WIDTH + COLUMN_PADDING
        + COL_ICON_WIDTH + COLUMN_PADDING
        + COL_VERSION_WIDTH + COLUMN_PADDING
    if showReady then
        w = w + COL_ICON_WIDTH + COLUMN_PADDING
    end
    return w
end

local frame
local headerRow
local rows = {}
local buffColumns = {}
local currentMode = nil

local function CreateRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if index % 2 == 0 then
        bg:SetColorTexture(1, 1, 1, 0.03)
    else
        bg:SetColorTexture(0, 0, 0, 0.03)
    end

    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetJustifyH("LEFT")
    row.nameText = nameText

    local specIcon = row:CreateTexture(nil, "ARTWORK")
    specIcon:SetSize(COL_ICON_WIDTH - 4, COL_ICON_WIDTH - 4)
    row.specIcon = specIcon

    local roleIcon = row:CreateTexture(nil, "ARTWORK")
    roleIcon:SetSize(COL_ICON_WIDTH - 4, COL_ICON_WIDTH - 4)
    row.roleIcon = roleIcon

    local versionText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetWidth(COL_VERSION_WIDTH)
    versionText:SetJustifyH("CENTER")
    row.versionText = versionText

    local readyIcon = row:CreateTexture(nil, "ARTWORK")
    readyIcon:SetSize(COL_ICON_WIDTH - 4, COL_ICON_WIDTH - 4)
    row.readyIcon = readyIcon

    row.buffIcons = {}

    return row
end

local function LayoutRowColumns(row, showReady, buffCount)
    local x = BACKDROP_PADDING

    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT", row, "LEFT", x, 0)
    row.nameText:SetWidth(COL_NAME_WIDTH)
    x = x + COL_NAME_WIDTH + COLUMN_PADDING

    row.specIcon:ClearAllPoints()
    row.specIcon:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    x = x + COL_ICON_WIDTH + COLUMN_PADDING

    row.roleIcon:ClearAllPoints()
    row.roleIcon:SetPoint("LEFT", row, "LEFT", x + 2, 0)
    x = x + COL_ICON_WIDTH + COLUMN_PADDING

    row.versionText:ClearAllPoints()
    row.versionText:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + COL_VERSION_WIDTH + COLUMN_PADDING

    if showReady then
        row.readyIcon:ClearAllPoints()
        -- Anchor by center so oversized entries (see READY_ICONS scale) stay
        -- aligned with the column instead of growing rightward off the anchor.
        row.readyIcon:SetPoint("CENTER", row, "LEFT", x + 2 + (COL_ICON_WIDTH - 4) / 2, 0)
        x = x + COL_ICON_WIDTH + COLUMN_PADDING
    end

    while #row.buffIcons < buffCount do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(COL_ICON_WIDTH - 4, COL_ICON_WIDTH - 4)
        table.insert(row.buffIcons, icon)
    end

    for i = 1, buffCount do
        row.buffIcons[i]:ClearAllPoints()
        row.buffIcons[i]:SetPoint("LEFT", row, "LEFT", x + 2, 0)
        x = x + COL_ICON_WIDTH + COLUMN_PADDING
    end
end

local function CreateHeaderRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(HEADER_HEIGHT)

    local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetWidth(COL_NAME_WIDTH)
    nameLabel:SetJustifyH("LEFT")
    nameLabel:SetText("Name")
    nameLabel:SetTextColor(0.8, 0.8, 0.8)
    row.nameLabel = nameLabel

    local specLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specLabel:SetWidth(COL_ICON_WIDTH)
    specLabel:SetJustifyH("CENTER")
    specLabel:SetText("Spec")
    specLabel:SetTextColor(0.8, 0.8, 0.8)
    row.specLabel = specLabel

    local roleLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleLabel:SetWidth(COL_ICON_WIDTH)
    roleLabel:SetJustifyH("CENTER")
    roleLabel:SetText("Role")
    roleLabel:SetTextColor(0.8, 0.8, 0.8)
    row.roleLabel = roleLabel

    local versionLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionLabel:SetWidth(COL_VERSION_WIDTH)
    versionLabel:SetJustifyH("CENTER")
    versionLabel:SetText("PRT")
    versionLabel:SetTextColor(0.8, 0.8, 0.8)
    row.versionLabel = versionLabel

    local readyLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readyLabel:SetWidth(COL_ICON_WIDTH)
    readyLabel:SetJustifyH("CENTER")
    readyLabel:SetText("Rdy")
    readyLabel:SetTextColor(0.8, 0.8, 0.8)
    row.readyLabel = readyLabel

    row.buffHeaders = {}

    return row
end

local function LayoutHeaderColumns(row, showReady, columns)
    local x = BACKDROP_PADDING

    row.nameLabel:ClearAllPoints()
    row.nameLabel:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + COL_NAME_WIDTH + COLUMN_PADDING

    row.specLabel:ClearAllPoints()
    row.specLabel:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + COL_ICON_WIDTH + COLUMN_PADDING

    row.roleLabel:ClearAllPoints()
    row.roleLabel:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + COL_ICON_WIDTH + COLUMN_PADDING

    row.versionLabel:ClearAllPoints()
    row.versionLabel:SetPoint("LEFT", row, "LEFT", x, 0)
    x = x + COL_VERSION_WIDTH + COLUMN_PADDING

    if showReady then
        row.readyLabel:ClearAllPoints()
        row.readyLabel:SetPoint("LEFT", row, "LEFT", x, 0)
        row.readyLabel:Show()
        x = x + COL_ICON_WIDTH + COLUMN_PADDING
    else
        row.readyLabel:Hide()
    end

    while #row.buffHeaders < #columns do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(COL_ICON_WIDTH - 4, COL_ICON_WIDTH - 4)
        table.insert(row.buffHeaders, icon)
    end

    for i, col in ipairs(columns) do
        local icon = row.buffHeaders[i]
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", row, "LEFT", x + 2, 0)
        icon:SetTexture(SpellTexture(col.spellId) or FALLBACK_ICON)
        icon:Show()
        x = x + COL_ICON_WIDTH + COLUMN_PADDING
    end

    for i = #columns + 1, #row.buffHeaders do
        row.buffHeaders[i]:Hide()
    end
end

local function GetRaidLeaderVersion()
    for unit in PRT:IterateGroup() do
        if UnitIsGroupLeader(unit) then
            local guid = UnitGUID(unit)
            if guid then
                local member = PRT.GroupInspect.members[guid]
                if member then
                    return member.addonVersion
                end
            end
            return nil
        end
    end
    return nil
end

local function InitFrame()
    if frame then return end

    frame = CreateFrame("Frame", "PRT_ReadyScreenFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", BACKDROP_PADDING, -BACKDROP_PADDING)
    frame.title = title

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeButton:SetScript("OnClick", function()
        PRT.ReadyScreen:Close()
    end)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        PRT.ReadyScreenFrame:SavePosition()
    end)

    headerRow = CreateHeaderRow(frame)
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(BACKDROP_PADDING + HEADER_HEIGHT + 4))
    headerRow:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

    -- Swap the question-mark fallbacks for real icons once requested spell
    -- data arrives. Refresh already no-ops while the frame is hidden.
    frame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    frame:SetScript("OnEvent", function(_, event, spellId, success)
        if event ~= "SPELL_DATA_LOAD_RESULT" or not success then return end
        for _, col in ipairs(buffColumns) do
            if col.spellId == spellId then
                PRT.ReadyScreenFrame:Refresh()
                return
            end
        end
    end)
end

local ReadyScreenFrame = {}
PRT.ReadyScreenFrame = ReadyScreenFrame

function ReadyScreenFrame:SavePosition()
    if not frame then return end
    local settings = PRT:GetSetting("readyScreen")
    if not settings then return end

    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = frame:GetLeft() * scale
    local y = (frame:GetTop() - UIParent:GetTop()) * scale

    settings.position = { x = x, y = y }
end

function ReadyScreenFrame:RestorePosition()
    if not frame then return end
    local settings = PRT:GetSetting("readyScreen")
    local pos = settings and settings.position

    frame:ClearAllPoints()
    if pos then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function ReadyScreenFrame:Show(mode)
    InitFrame()
    currentMode = mode
    RequestBuffSpellData(GetBuffColumns())

    if mode == "audit" then
        frame.title:SetText("Raid Audit")
    else
        frame.title:SetText("Ready Screen")
    end

    self:RestorePosition()
    frame:Show()
    self:Refresh()
end

function ReadyScreenFrame:Hide()
    if frame then
        frame:Hide()
    end
    currentMode = nil
end

function ReadyScreenFrame:IsShown()
    return frame and frame:IsShown()
end

function ReadyScreenFrame:Refresh()
    if not frame or not frame:IsShown() then return end

    buffColumns = GetBuffColumns()
    local showReady = currentMode == "readycheck" or currentMode == "completed"
    local rlVersion = GetRaidLeaderVersion()

    LayoutHeaderColumns(headerRow, showReady, buffColumns)

    local unitMap = {}
    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        if guid then
            unitMap[guid] = unit
        end
    end

    local roster = {}
    for guid, member in pairs(PRT.GroupInspect.members) do
        local unit = unitMap[guid]
        local displayName = member.name
        if unit then
            displayName = GetUnitName(unit, true) or member.name
        end
        table.insert(roster, {
            guid = guid,
            name = displayName,
            class = member.class,
            specId = member.specId,
            addonVersion = member.addonVersion,
            unit = unit,
        })
    end

    PRT.ReadyScreen.SortRoster(roster)

    local frameWidth = BACKDROP_PADDING * 2 + GetFixedColumnsWidth(showReady) + #buffColumns * (COL_ICON_WIDTH + COLUMN_PADDING)
    frame:SetWidth(frameWidth)

    while #rows < #roster do
        table.insert(rows, CreateRow(frame, #rows + 1))
    end

    local responses = PRT.ReadyScreen:GetResponses()

    for i, entry in ipairs(roster) do
        local row = rows[i]
        LayoutRowColumns(row, showReady, #buffColumns)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(BACKDROP_PADDING + HEADER_HEIGHT + 4 + HEADER_HEIGHT + (i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

        local isOffline = entry.unit and not UnitIsConnected(entry.unit)
        local isDead = entry.unit and UnitIsDeadOrGhost(entry.unit)

        row:SetAlpha(isOffline and 0.5 or 1)

        local classColor = RAID_CLASS_COLORS[entry.class]
        if classColor then
            row.nameText:SetText(classColor:WrapTextInColorCode(entry.name or ""))
        else
            row.nameText:SetText(entry.name or "")
        end

        if entry.specId then
            local _, _, _, icon = GetSpecializationInfoByID(entry.specId)
            if icon then
                row.specIcon:SetTexture(icon)
                row.specIcon:Show()
            else
                row.specIcon:Hide()
            end
        else
            row.specIcon:Hide()
        end

        local role = entry.unit and UnitGroupRolesAssigned(entry.unit)
        local roleAtlas = role and ROLE_ATLASES[role]
        if roleAtlas then
            row.roleIcon:SetAtlas(roleAtlas)
            row.roleIcon:Show()
        else
            row.roleIcon:Hide()
        end

        local versionStr = DecodeVersion(entry.addonVersion)
        if versionStr then
            row.versionText:SetText(versionStr)
            local classification = PRT.ReadyScreen.ClassifyVersion(entry.addonVersion, rlVersion)
            if classification == "outdated" then
                row.versionText:SetTextColor(1, 0.3, 0.3)
            else
                row.versionText:SetTextColor(1, 1, 1)
            end
        else
            row.versionText:SetText("\226\128\148")
            row.versionText:SetTextColor(0.5, 0.5, 0.5)
        end

        if showReady then
            local responseState = responses[entry.guid]
            if PRT.ReadyScreen:IsReadyCheckActive() and entry.unit then
                local status = GetReadyCheckStatus(entry.unit)
                if status == "ready" then
                    responseState = "ready"
                elseif status == "notready" then
                    responseState = "notready"
                end
            end
            local displayedState = PRT.ReadyScreen.GetDisplayedState(isOffline or false, isDead or false, responseState)
            local iconInfo = displayedState and READY_ICONS[displayedState]
            if iconInfo then
                if iconInfo.atlas then
                    row.readyIcon:SetAtlas(iconInfo.atlas)
                else
                    row.readyIcon:SetTexture(iconInfo.texture)
                end
                local size = (COL_ICON_WIDTH - 4) * (iconInfo.scale or 1)
                row.readyIcon:SetSize(size, size)
                row.readyIcon:Show()
            else
                row.readyIcon:Hide()
            end
        else
            row.readyIcon:Hide()
        end

        for j, col in ipairs(buffColumns) do
            local buffIcon = row.buffIcons[j]
            local hasBuff = false
            if entry.unit and not isOffline and UnitIsVisible(entry.unit) then
                hasBuff = C_UnitAuras.GetAuraDataBySpellName(entry.unit, col.name, "HELPFUL") ~= nil
            end

            if hasBuff then
                buffIcon:SetTexture(SpellTexture(col.spellId) or FALLBACK_ICON)
                buffIcon:Show()
            else
                buffIcon:Hide()
            end
        end

        for j = #buffColumns + 1, #row.buffIcons do
            row.buffIcons[j]:Hide()
        end

        row:Show()
    end

    for i = #roster + 1, #rows do
        rows[i]:Hide()
    end

    local contentHeight = BACKDROP_PADDING * 2 + HEADER_HEIGHT + 4 + HEADER_HEIGHT + #roster * ROW_HEIGHT
    frame:SetHeight(contentHeight)
end
