local PRT = PurplexityRaidTools

local ROW_HEIGHT = 20
local HEADER_HEIGHT = 24
local TITLE_HEIGHT = 28
local VIEW_TABS_HEIGHT = 26
local COLUMN_PADDING = 4
local BACKDROP_PADDING = 8

local COL_NAME_WIDTH = 130
local COL_ICON_WIDTH = 24
local COL_VERSION_WIDTH = 50
local HEADER_DESCRIPTIONS = {
    name = "The character's name. Characters from another realm also show their realm name.",
    spec = "The character's current specialization. A blank cell means it is not available yet.",
    role = "The character's assigned group role: tank, healer, or damage dealer.",
    version = "The character's PRT version. Red means it is older than the group leader's version. A dash means no version was received.",
    itemLevel = "The character's average equipped item level. A dash means it is not available yet.",
    ready = "The character's ready check response, or whether they are dead or offline.",
    enchants = "Whether the checked equipment slots have their required enchants. Unknown means the item data is not available. Hover over a character's row for details.",
    gems = "Whether the checked equipment sockets have gems. Unknown means the item data is not available. Hover over a character's row for details.",
    wellFed = "Whether the character has a Well Fed food buff.",
    weaponEnhancement = "Whether at least one weapon has a temporary enhancement, such as an oil or sharpening stone. This status is reported by PRT.",
    flask = "Whether the character has a recognized flask buff.",
    augmentRune = "Whether the character has a recognized augment rune buff.",
    vantusRune = "Whether the character has a Vantus Rune buff. This does not check whether it matches the current boss.",
    durability = "The character's remaining equipment durability, reported by PRT. Yellow means 50% or less; red means 20% or less. A dash means no value is available.",
}
local GEAR_COLUMNS = {
    { key = "enchants", name = "Enchants", width = 80, display = "audit" },
    { key = "gems", name = "Gems", width = 80, display = "audit" },
}
local AUDIT_STATUSES = {
    complete = { text = "Complete", color = { 0.3, 1, 0.3 } },
    missing = { text = "Missing", color = { 1, 0.3, 0.3 } },
    unknown = { text = "Unknown", color = { 0.6, 0.6, 0.6 } },
}

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

local function ColumnTexture(column)
    return column.texture or SpellTexture(column.spellId) or FALLBACK_ICON
end

local function ColumnWidth(column)
    return column.width or COL_ICON_WIDTH
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
    for _, buff in ipairs(PRT.ReadyScreen.GetPersonalBuffColumns()) do
        table.insert(columns, {
            kind = "personal",
            key = buff.key,
            name = buff.name,
            spellId = buff.spellId,
            texture = buff.texture,
            display = buff.display,
            width = buff.width,
        })
    end
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
local currentView = nil

local function UpdateViewTab(tab, selected)
    tab.selected = selected
    if selected then
        PanelTemplates_SelectTab(tab)
        return
    end
    PanelTemplates_DeselectTab(tab)
end

local function CreateViewTab(parent, label, onClick)
    local tab = PRT.Components.GetTab(parent, label)
    tab:SetScript("OnShow", function(self)
        PanelTemplates_TabResize(self, 15, nil, 70)
        UpdateViewTab(self, self.selected)
    end)
    tab:SetScript("OnClick", onClick)
    return tab
end

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
    row.buffTexts = {}

    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if currentView ~= "gear" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, column in ipairs(GEAR_COLUMNS) do
            GameTooltip:AddLine(column.name, 1, 1, 1)
            GameTooltip:AddLine(PRT.GearAudit.GetDetails(self.gearAudit and self.gearAudit[column.key]),
                0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnHide", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    return row
end

local function LayoutRowColumns(row, showReady, columns)
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

    while #row.buffIcons < #columns do
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(COL_ICON_WIDTH - 4, COL_ICON_WIDTH - 4)
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        table.insert(row.buffIcons, icon)

        local textValue = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        textValue:SetJustifyH("CENTER")
        table.insert(row.buffTexts, textValue)
    end

    for i, col in ipairs(columns) do
        local width = ColumnWidth(col)
        row.buffIcons[i]:ClearAllPoints()
        row.buffIcons[i]:SetPoint("CENTER", row, "LEFT", x + width / 2, 0)
        row.buffTexts[i]:ClearAllPoints()
        row.buffTexts[i]:SetPoint("LEFT", row, "LEFT", x, 0)
        row.buffTexts[i]:SetWidth(width)
        x = x + width + COLUMN_PADDING
    end
end

local function HideHeaderTooltip(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide()
    end
end

local function SetHeaderTooltip(row, key, anchor, width, title, description)
    local target = row.tooltipTargets[key]
    if not target then
        target = CreateFrame("Frame", nil, row)
        target:EnableMouse(true)
        target:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1)
            GameTooltip:AddLine(self.tooltipDescription, 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        target:SetScript("OnLeave", HideHeaderTooltip)
        target:SetScript("OnHide", HideHeaderTooltip)
        row.tooltipTargets[key] = target
    end
    if target.tooltipTitle ~= title then
        HideHeaderTooltip(target)
    end
    target.tooltipTitle = title
    target.tooltipDescription = description
    target:ClearAllPoints()
    target:SetPoint("CENTER", anchor, "CENTER")
    target:SetSize(width, HEADER_HEIGHT)
    target:Show()
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
    row.buffLabels = {}
    row.tooltipTargets = {}

    return row
end

local function LayoutHeaderColumns(row, showReady, columns, isGear)
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
    row.versionLabel:SetText(isGear and "iLvl" or "PRT")
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
        icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        table.insert(row.buffHeaders, icon)
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetJustifyH("CENTER")
        label:SetTextColor(0.8, 0.8, 0.8)
        table.insert(row.buffLabels, label)
    end

    for i, col in ipairs(columns) do
        local icon = row.buffHeaders[i]
        local label = row.buffLabels[i]
        local width = ColumnWidth(col)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", row, "LEFT", x + width / 2, 0)
        label:ClearAllPoints()
        label:SetPoint("LEFT", row, "LEFT", x, 0)
        label:SetWidth(width)
        if col.display == "audit" then
            icon:Hide()
            label:SetText(col.name)
            label:Show()
        else
            label:Hide()
            icon:SetTexture(ColumnTexture(col))
            icon:Show()
        end
        x = x + width + COLUMN_PADDING
    end

    for i = #columns + 1, #row.buffHeaders do
        row.buffHeaders[i]:Hide()
        row.buffLabels[i]:Hide()
        row.tooltipTargets[i]:Hide()
    end

    SetHeaderTooltip(row, "name", row.nameLabel, COL_NAME_WIDTH, "Name", HEADER_DESCRIPTIONS.name)
    SetHeaderTooltip(row, "spec", row.specLabel, COL_ICON_WIDTH, "Specialization", HEADER_DESCRIPTIONS.spec)
    SetHeaderTooltip(row, "role", row.roleLabel, COL_ICON_WIDTH, "Role", HEADER_DESCRIPTIONS.role)
    SetHeaderTooltip(row, "version", row.versionLabel, COL_VERSION_WIDTH,
        isGear and "Equipped Item Level" or "PRT Version",
        isGear and HEADER_DESCRIPTIONS.itemLevel or HEADER_DESCRIPTIONS.version)
    if showReady then
        SetHeaderTooltip(row, "ready", row.readyLabel, COL_ICON_WIDTH, "Ready Check", HEADER_DESCRIPTIONS.ready)
    elseif row.tooltipTargets.ready then
        row.tooltipTargets.ready:Hide()
    end
    for i, col in ipairs(columns) do
        local description = HEADER_DESCRIPTIONS[col.key]
            or ("Whether the character has " .. col.name .. ". A blank cell means the buff is missing or could not be read.")
        local anchor = col.display == "audit" and row.buffLabels[i] or row.buffHeaders[i]
        SetHeaderTooltip(row, i, anchor, ColumnWidth(col), col.name, description)
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

--- Reproduce GetUnitName(unit, true): a name from the player's own realm shows
--- bare, any other realm keeps its suffix. GroupInspect built the stored name
--- from these same two sources, so the comparison agrees with the client.
local function DisplayName(fullName)
    if not fullName then
        return ""
    end
    local realm = fullName:match("%-(.+)$")
    if not realm or realm == GetNormalizedRealmName() then
        return Ambiguate(fullName, "short")
    end
    return fullName
end

local function BuildRoster()
    local preview = PRT.ReadyScreen:GetPreviewRoster()
    if preview then
        local roster = {}
        for _, entry in ipairs(preview) do
            table.insert(roster, entry)
        end
        local _, class = UnitClass("player")
        local spec = GetSpecialization()
        local _, equipped = GetAverageItemLevel()
        table.insert(roster, {
            guid = UnitGUID("player"), name = GetUnitName("player", true), class = class,
            specId = spec and GetSpecializationInfo(spec), unit = "player", itemLevel = equipped,
            gearAudit = PRT.GearAudit.Evaluate(PRT.GearAudit.Capture("player")),
        })
        return PRT.ReadyScreen.SortRoster(roster)
    end
    local unitMap = {}
    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        if guid then
            unitMap[guid] = unit
        end
    end

    local roster = {}
    for guid, member in pairs(PRT.GroupInspect.members) do
        table.insert(roster, {
            guid = guid,
            name = DisplayName(member.name),
            class = member.class,
            specId = member.specId,
            addonVersion = member.addonVersion,
            itemLevel = member.itemLevel,
            gearAudit = member.gearAudit,
            unit = unitMap[guid],
        })
    end

    PRT.ReadyScreen.SortRoster(roster)
    return roster
end

local function SetRowName(row, entry)
    local classColor = RAID_CLASS_COLORS[entry.class]
    if classColor then
        row.nameText:SetText(classColor:WrapTextInColorCode(entry.name or ""))
    else
        row.nameText:SetText(entry.name or "")
    end
end

local function SetRowSpec(row, entry)
    if not entry.specId then
        row.specIcon:Hide()
        return
    end

    local _, _, _, icon = GetSpecializationInfoByID(entry.specId)
    if not icon then
        row.specIcon:Hide()
        return
    end

    row.specIcon:SetTexture(icon)
    row.specIcon:Show()
end

local function SetRowRole(row, entry)
    local role = entry.role or (entry.unit and UnitGroupRolesAssigned(entry.unit))
    local roleAtlas = role and ROLE_ATLASES[role]
    if not roleAtlas then
        row.roleIcon:Hide()
        return
    end

    row.roleIcon:SetAtlas(roleAtlas)
    row.roleIcon:Show()
end

local function SetRowVersion(row, entry, rlVersion)
    local versionStr = DecodeVersion(entry.addonVersion)
    if not versionStr then
        row.versionText:SetText("\226\128\148")
        row.versionText:SetTextColor(0.5, 0.5, 0.5)
        return
    end

    row.versionText:SetText(versionStr)
    if PRT.ReadyScreen.ClassifyVersion(entry.addonVersion, rlVersion) == "outdated" then
        row.versionText:SetTextColor(1, 0.3, 0.3)
    else
        row.versionText:SetTextColor(1, 1, 1)
    end
end

local function SetRowReady(row, entry, responses, isOffline, isDead)
    local responseState = responses[entry.guid]
    if PRT.ReadyScreen:IsReadyCheckActive() and entry.unit then
        local status = GetReadyCheckStatus(entry.unit)
        if status == "ready" then
            responseState = "ready"
        elseif status == "notready" then
            responseState = "notready"
        end
    end

    local displayedState = PRT.ReadyScreen.GetDisplayedState(isOffline, isDead, responseState)
    local iconInfo = displayedState and READY_ICONS[displayedState]
    if not iconInfo then
        row.readyIcon:Hide()
        return
    end

    if iconInfo.atlas then
        row.readyIcon:SetAtlas(iconInfo.atlas)
    else
        row.readyIcon:SetTexture(iconInfo.texture)
    end
    local size = (COL_ICON_WIDTH - 4) * (iconInfo.scale or 1)
    row.readyIcon:SetSize(size, size)
    row.readyIcon:Show()
end

local function SetRowBuffs(row, entry, isOffline)
    local canReadAuras = entry.unit and not isOffline and UnitIsVisible(entry.unit)
    local personalStatuses

    for j, col in ipairs(buffColumns) do
        local buffIcon = row.buffIcons[j]
        local buffText = row.buffTexts[j]
        local hasBuff = false
        local texture

        if col.display == "percent" then
            local percent = PRT.ReadyScreen:GetDurability(entry.guid)
            if entry.previewBuffs then
                percent = entry.durability
            end
            buffIcon:Hide()
            if type(percent) == "number" then
                local rounded = math.floor(percent + 0.5)
                buffText:SetFormattedText("%d%%", rounded)
                if rounded <= 20 then
                    buffText:SetTextColor(1, 0, 0)
                elseif rounded <= 50 then
                    buffText:SetTextColor(1, 1, 0)
                else
                    buffText:SetTextColor(1, 1, 1)
                end
                buffText:Show()
            else
                buffText:SetText("\226\128\148")
                buffText:SetTextColor(0.5, 0.5, 0.5)
                buffText:Show()
            end
        elseif entry.previewBuffs then
            hasBuff = entry.previewBuffs[col.key or col.name] == true
        elseif col.kind == "personal" and col.key == "weaponEnhancement" then
            hasBuff = PRT.ReadyScreen:GetWeaponStatus(entry.guid) == true
        elseif col.kind == "personal" then
            if personalStatuses == nil then
                personalStatuses = {}
                if canReadAuras then
                    local succeeded, statuses = pcall(PRT.ReadyScreen.GetPersonalBuffStatuses, entry.unit)
                    if succeeded then
                        personalStatuses = statuses
                    end
                end
            end
            texture = personalStatuses[col.key]
            hasBuff = texture ~= nil
        elseif canReadAuras then
            hasBuff = C_UnitAuras.GetAuraDataBySpellName(entry.unit, col.name, "HELPFUL") ~= nil
        end

        if col.display ~= "percent" then
            buffText:Hide()
            if hasBuff then
                buffIcon:SetTexture(type(texture) == "number" and texture or ColumnTexture(col))
                buffIcon:Show()
            else
                buffIcon:Hide()
            end
        end
    end

    for j = #buffColumns + 1, #row.buffIcons do
        row.buffIcons[j]:Hide()
        row.buffTexts[j]:Hide()
    end
end

local function SetRowItemLevel(row, entry)
    row.versionText:SetText(PRT.ReadyScreen.FormatItemLevel(entry.itemLevel))
    if PRT.ReadyScreen.IsItemLevelAvailable(entry.itemLevel) then
        row.versionText:SetTextColor(1, 1, 1)
    else
        row.versionText:SetTextColor(0.5, 0.5, 0.5)
    end
end

local function SetRowGearAudit(row, entry)
    row.gearAudit = entry.gearAudit
    for i = 1, #row.buffIcons do
        row.buffIcons[i]:Hide()
        row.buffTexts[i]:Hide()
    end
    for i, column in ipairs(GEAR_COLUMNS) do
        local result = entry.gearAudit and entry.gearAudit[column.key]
        local status = AUDIT_STATUSES[result and result.status or "unknown"]
        local text = row.buffTexts[i]
        text:SetText(status.text)
        text:SetTextColor(unpack(status.color))
        text:Show()
    end
end

local function UpdateRow(row, entry, showReady, responses, rlVersion, isGear)
    local isOffline = (entry.unit and not UnitIsConnected(entry.unit)) or false
    local isDead = (entry.unit and UnitIsDeadOrGhost(entry.unit)) or false

    row:SetAlpha(isOffline and 0.5 or 1)
    SetRowName(row, entry)
    SetRowSpec(row, entry)
    SetRowRole(row, entry)
    if isGear then
        SetRowItemLevel(row, entry)
    else
        SetRowVersion(row, entry, rlVersion)
    end

    if showReady then
        SetRowReady(row, entry, responses, isOffline, isDead)
    else
        row.readyIcon:Hide()
    end

    if isGear then
        SetRowGearAudit(row, entry)
    else
        SetRowBuffs(row, entry, isOffline)
    end
end

local function InitFrame()
    if frame then return end

    frame = CreateFrame("Frame", "PRT_ReadyScreenFrame", UIParent, "ButtonFrameTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:Hide()

    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    frame.Inset:Hide()
    frame:SetTitle("Ready Check")
    frame.CloseButton:SetScript("OnClick", function()
        PRT.ReadyScreen:Close()
    end)

    local readinessButton = CreateViewTab(frame, "Readiness", function()
        PRT.ReadyScreen:ShowReadiness()
    end)
    readinessButton:SetPoint("TOPLEFT", frame, "TOPLEFT", BACKDROP_PADDING, -TITLE_HEIGHT)
    frame.readinessButton = readinessButton

    local gearButton = CreateViewTab(frame, "Gear", function()
        PRT.ReadyScreen:ShowGear()
    end)
    gearButton:SetPoint("LEFT", readinessButton, "RIGHT", 0, 0)
    frame.gearButton = gearButton

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
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 0,
        -(BACKDROP_PADDING + TITLE_HEIGHT + VIEW_TABS_HEIGHT))
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

function ReadyScreenFrame:Show(view)
    InitFrame()
    currentView = view
    if view == "readiness" then
        RequestBuffSpellData(GetBuffColumns())
    end

    self:RestorePosition()
    frame:Show()
    self:Refresh()
end

function ReadyScreenFrame:Hide()
    if frame then
        frame:Hide()
    end
    currentView = nil
end

function ReadyScreenFrame:IsShown()
    return frame and frame:IsShown()
end

function ReadyScreenFrame:Refresh()
    if not frame or not frame:IsShown() then return end

    local isGear = currentView == "gear"
    buffColumns = isGear and GEAR_COLUMNS or GetBuffColumns()
    local mode = PRT.ReadyScreen:GetMode()
    local showReady = not isGear and (mode == "readycheck" or mode == "completed")
    local rlVersion = GetRaidLeaderVersion()

    UpdateViewTab(frame.readinessButton, not isGear)
    UpdateViewTab(frame.gearButton, isGear)
    LayoutHeaderColumns(headerRow, showReady, buffColumns, isGear)

    local roster = BuildRoster()

    local buffColumnsWidth = 0
    for _, col in ipairs(buffColumns) do
        buffColumnsWidth = buffColumnsWidth + ColumnWidth(col) + COLUMN_PADDING
    end
    local frameWidth = BACKDROP_PADDING * 2 + GetFixedColumnsWidth(showReady) + buffColumnsWidth
    frame:SetWidth(frameWidth)

    while #rows < #roster do
        table.insert(rows, CreateRow(frame, #rows + 1))
    end

    local responses = PRT.ReadyScreen:GetResponses()

    for i, entry in ipairs(roster) do
        local row = rows[i]
        LayoutRowColumns(row, showReady, buffColumns)

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0,
            -(BACKDROP_PADDING + TITLE_HEIGHT + VIEW_TABS_HEIGHT
                + HEADER_HEIGHT + (i - 1) * ROW_HEIGHT))
        row:SetPoint("RIGHT", frame, "RIGHT", 0, 0)

        UpdateRow(row, entry, showReady, responses, rlVersion, isGear)
        row:Show()
    end

    for i = #roster + 1, #rows do
        rows[i]:Hide()
    end

    local contentHeight = BACKDROP_PADDING * 2 + TITLE_HEIGHT + VIEW_TABS_HEIGHT
        + HEADER_HEIGHT + #roster * ROW_HEIGHT
    frame:SetHeight(contentHeight)
end
