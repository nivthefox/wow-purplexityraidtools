local PRT = PurplexityRaidTools
local NotesEditor = {}
PRT.NotesEditor = NotesEditor

local VPPS = 8
local BLOCK_WIDTH = 95
local BLOCK_HEIGHT = 34
local BLOCK_GAP = 4
local RULER_WIDTH = 50
local EDIT_PANEL_WIDTH = 260
local DEFAULT_FRAME_WIDTH = 700
local DEFAULT_FRAME_HEIGHT = 550
local GRID_INTERVAL = 30
local TICK_INTERVAL = 5
local TICK_LABEL_INTERVAL = 10
local PHASE_PAD = 10
local TOP_PAD = 6

local DIFFICULTY_OPTIONS = {
    { name = "Normal",  value = "Normal" },
    { name = "Heroic",  value = "Heroic" },
    { name = "Mythic",  value = "Mythic" },
    { name = "LFR",     value = "LFR" },
}

local DISPLAY_TYPE_OPTIONS = {
    { name = "Icon (cooldown swipe)", value = "Icon" },
    { name = "Status Bar",           value = "Bar" },
    { name = "Text Overlay",         value = "Text" },
    { name = "Circle (swipe)",       value = "Circle" },
}

local GENERIC_ABILITIES = {
    "Defensive", "Kick", "Soak", "Spread", "Stack",
    "Raid Cooldown", "External", "Dispel",
    "Active Mitigation", "Taunt Swap",
}

local BACKDROP_INFO = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local frame
local state = {}

local function GetSettings()
    return PRT:GetSetting("notes")
end

local function NonEmpty(text)
    if text == "" then
        return nil
    end
    return text
end

local function ParseTTSInput(raw)
    if raw == "true" then
        return true
    end
    if raw == "false" then
        return false
    end
    return NonEmpty(raw)
end

local function FormatTTSValue(tts)
    if tts == true then
        return "true"
    end
    if tts == false then
        return "false"
    end
    return tts or ""
end

local function ByName(a, b)
    return a.name < b.name
end

local function SortRemindersByTime(bucket)
    table.sort(bucket, function(a, b)
        return a.time < b.time
    end)
end

local function EnsurePositions()
    local profile = PRT.Profiles:GetCurrent()
    if not profile.notes then
        profile.notes = {}
    end
    if not profile.notes.positions then
        profile.notes.positions = {}
    end
    return profile.notes.positions
end

local function FormatTime(seconds)
    if not seconds then
        return "0:00"
    end
    local m = math.floor(seconds / 60)
    local s = math.floor(seconds % 60)
    return m .. ":" .. (s < 10 and "0" or "") .. s
end

local function ParseTimeInput(text)
    if not text or text == "" then
        return nil
    end
    local m, s = text:match("^(%d+):(%d+)$")
    if m then
        return tonumber(m) * 60 + tonumber(s)
    end
    return tonumber(text)
end

local function ClassColorForTag(tag)
    if not tag then
        return 0.8, 0.8, 0.8
    end
    local lowerTag = tag:lower()

    if lowerTag == "everyone" then
        return 0.8, 0.8, 0.8
    end
    if lowerTag == "healer" or lowerTag == "healers" then
        return 0.3, 0.8, 0.6
    end
    if lowerTag == "tank" or lowerTag == "tanks" then
        return 0.96, 0.62, 0.04
    end
    if lowerTag == "damager" or lowerTag == "dps" then
        return 0.77, 0.12, 0.23
    end

    if PRT.GroupInspect and PRT.GroupInspect.members then
        for _, member in pairs(PRT.GroupInspect.members) do
            if member.name and member.name:lower() == lowerTag then
                local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[member.class]
                if color then
                    return color.r, color.g, color.b
                end
            end
        end
    end

    return 0.8, 0.8, 0.8
end

local function IsRoleOrGroupTag(tag)
    if not tag then
        return false
    end
    local lower = tag:lower()
    return lower == "everyone"
        or lower == "healer" or lower == "healers"
        or lower == "tank" or lower == "tanks"
        or lower == "damager" or lower == "dps"
        or lower == "melee" or lower == "ranged"
        or lower:match("^group%d+$") ~= nil
end

local function IsClassTag(tag)
    if not tag or not PRT.SpellData then
        return false
    end
    local upper = tag:upper()
    for _, specData in pairs(PRT.SpellData) do
        if specData.class == upper then
            return true
        end
    end
    return false
end

local function FindMemberByName(name)
    if not name or not PRT.GroupInspect or not PRT.GroupInspect.members then
        return nil
    end
    local lowerName = name:lower()
    for _, member in pairs(PRT.GroupInspect.members) do
        if member.name and member.name:lower() == lowerName then
            return member
        end
    end
    return nil
end

local function CollectAbilitiesFromSpec(specData)
    local result = {}
    for _, ability in pairs(specData.abilities) do
        if ability.cooldown and ability.cooldown > 0 then
            result[#result + 1] = { name = ability.name, spellId = ability.spellId }
        end
    end
    return result
end

local function GetLocalPlayerAbilities()
    if not PRT.SpellData then
        return {}
    end
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    if not specIndex then
        return {}
    end
    local specId = C_SpecializationInfo.GetSpecializationInfo
        and C_SpecializationInfo.GetSpecializationInfo(specIndex)
    if not specId then
        return {}
    end
    local specData = PRT.SpellData[specId]
    if not specData or not specData.abilities then
        return {}
    end
    local result = CollectAbilitiesFromSpec(specData)
    table.sort(result, ByName)
    return result
end

local function GetAbilitiesForTag(tag)
    if not tag or tag == "" then
        return {}
    end

    if IsRoleOrGroupTag(tag) then
        local result = {}
        for _, name in ipairs(GENERIC_ABILITIES) do
            result[#result + 1] = { name = name, spellId = nil }
        end
        return result
    end

    if not PRT.SpellData then
        return {}
    end

    local playerName = UnitName("player")
    if playerName then
        local shortName = playerName:match("^([^%-]+)")
        if shortName and tag:lower() == shortName:lower() then
            return GetLocalPlayerAbilities()
        end
    end

    local member = FindMemberByName(tag)
    if member and member.specId then
        local specData = PRT.SpellData[member.specId]
        if specData and specData.abilities then
            local result = CollectAbilitiesFromSpec(specData)
            table.sort(result, ByName)
            return result
        end
    end

    local upperTag = tag:upper()
    if IsClassTag(tag) then
        local seen = {}
        local result = {}
        for _, specData in pairs(PRT.SpellData) do
            if specData.class == upperTag and specData.abilities then
                for _, ability in pairs(specData.abilities) do
                    if ability.cooldown and ability.cooldown > 0 and not seen[ability.name] then
                        seen[ability.name] = true
                        result[#result + 1] = { name = ability.name, spellId = ability.spellId }
                    end
                end
            end
        end
        table.sort(result, ByName)
        return result
    end

    return {}
end

local function BuildPlayerCtx()
    local name = UnitName("player")
    local _, _, classID = UnitClass("player")
    local role = UnitGroupRolesAssigned("player")
    local specID
    local specIndex = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization
        and C_SpecializationInfo.GetSpecialization()
    if specIndex then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end

    if (not role or role == "NONE") and specIndex then
        local specRole = GetSpecializationRole(specIndex)
        if specRole and specRole ~= "NONE" then
            role = specRole
        end
    end

    local subgroup = 1
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local unitName, _, subGroup = GetRaidRosterInfo(i)
            if unitName and name and unitName == name then
                subgroup = subGroup
                break
            end
        end
    end

    local isMelee = role == "TANK" or PRT.NotesTags.IsMeleeSpec(specID)
    return {
        name = name,
        role = role,
        classID = classID,
        specID = specID,
        subgroup = subgroup,
        isMelee = isMelee,
    }
end

local function DerivePhases(parsedNote)
    if not parsedNote or not parsedNote.reminders then
        return { { num = 1, name = "Phase 1", start = 0, duration = PHASE_PAD } }
    end

    local phaseNums = {}
    local phaseSet = {}
    for phaseKey, bucket in pairs(parsedNote.reminders) do
        local num = tonumber(phaseKey)
        if num and not phaseSet[num] then
            phaseSet[num] = true
            phaseNums[#phaseNums + 1] = num
        end
    end

    if #phaseNums == 0 then
        return { { num = 1, name = "Phase 1", start = 0, duration = PHASE_PAD } }
    end

    table.sort(phaseNums)

    local phases = {}
    local offset = 0
    for _, num in ipairs(phaseNums) do
        local bucket = parsedNote.reminders[tostring(num)]
        local maxTime = 0
        if bucket then
            for _, r in ipairs(bucket) do
                if r.time > maxTime then
                    maxTime = r.time
                end
            end
        end
        local duration = maxTime + PHASE_PAD
        phases[#phases + 1] = {
            num = num,
            name = "Phase " .. num,
            start = offset,
            duration = duration,
        }
        offset = offset + duration
    end

    return phases
end

local function TimeToY(time, phaseNum, phases, activePhase)
    if activePhase == "all" then
        for _, p in ipairs(phases) do
            if p.num == phaseNum then
                return (p.start + time) * VPPS + TOP_PAD
            end
        end
        return time * VPPS + TOP_PAD
    end
    return time * VPPS + TOP_PAD
end

local function YToTimeAndPhase(y, phases, activePhase)
    local absTime = (y - TOP_PAD) / VPPS
    if activePhase == "all" then
        for i = #phases, 1, -1 do
            if absTime >= phases[i].start then
                return math.max(0, math.floor(absTime - phases[i].start + 0.5)), phases[i].num
            end
        end
        return math.max(0, math.floor(absTime + 0.5)), phases[1] and phases[1].num or 1
    end
    return math.max(0, math.floor(absTime + 0.5)), activePhase
end

local function TotalDuration(phases, activePhase)
    if activePhase == "all" then
        local last = phases[#phases]
        if not last then
            return PHASE_PAD
        end
        return last.start + last.duration
    end
    for _, p in ipairs(phases) do
        if p.num == activePhase then
            return p.duration
        end
    end
    return PHASE_PAD
end

local function CollectReminders(parsedNote, activePhase)
    if not parsedNote or not parsedNote.reminders then
        return {}
    end

    local phaseKeys = {}
    for phaseKey in pairs(parsedNote.reminders) do
        phaseKeys[#phaseKeys + 1] = phaseKey
    end
    table.sort(phaseKeys, function(a, b)
        return (tonumber(a) or 0) < (tonumber(b) or 0)
    end)

    local result = {}
    for _, phaseKey in ipairs(phaseKeys) do
        local num = tonumber(phaseKey)
        if activePhase == "all" or num == activePhase then
            for _, r in ipairs(parsedNote.reminders[phaseKey]) do
                result[#result + 1] = r
            end
        end
    end
    return result
end

local function CollectFreeformLines(parsedNote, activePhase)
    if not parsedNote or not parsedNote.lines then
        return {}
    end

    local result = {}
    local lastReminder = nil

    for _, entry in ipairs(parsedNote.lines) do
        if entry.type == "reminder" then
            lastReminder = entry.reminder
        elseif entry.type == "freeform" then
            local phase = lastReminder and lastReminder.phase or 1
            local time = lastReminder and lastReminder.time or 0
            local dur = lastReminder and lastReminder.duration or 0
            local visualHeight = math.max(dur * VPPS, BLOCK_HEIGHT)
            local timeOffset = visualHeight / VPPS
            local num = tonumber(phase) or 1
            if activePhase == "all" or num == activePhase then
                local label = entry.text:match("^%-%-%s*(.+)") or entry.text
                result[#result + 1] = {
                    text = label,
                    phase = num,
                    time = time + timeOffset,
                }
            end
        end
    end

    return result
end

local function SplitAbilityAndText(text, knownAbilities)
    if not text or text == "" then
        return "", ""
    end
    if knownAbilities then
        for _, ab in ipairs(knownAbilities) do
            local abLen = #ab.name
            if text:sub(1, abLen) == ab.name then
                local rest = text:sub(abLen + 1)
                if rest == "" then
                    return ab.name, ""
                end
                if rest:sub(1, 1) == " " then
                    return ab.name, rest:sub(2)
                end
            end
        end
    end
    return text, ""
end

local function SaveEditorPosition()
    if not frame then
        return
    end
    local positions = EnsurePositions()
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = frame:GetLeft() * scale
    local y = (frame:GetTop() - UIParent:GetTop()) * scale
    positions.editor = {
        point = "TOPLEFT",
        x = x,
        y = y,
    }
end

local function RestoreEditorPosition()
    if not frame then
        return
    end
    local settings = GetSettings()
    local positions = settings and settings.positions
    local pos = positions and positions.editor

    frame:ClearAllPoints()
    frame:SetSize(DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT)
    if pos then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local titleBar, modeBar, phaseTabs, timelineArea, editPanel
local rulerFrame, bodyScroll, canvas, cursorLine, cursorLabel
local blockPool = {}
local gridPool = {}
local tickPool = {}
local phaseTabPool = {}
local phaseDividerPool = {}
local freeformPool = {}

local function RecyclePool(pool)
    for _, obj in ipairs(pool) do
        obj:Hide()
        obj:ClearAllPoints()
    end
end

local function GetFromPool(pool, createFn)
    for _, obj in ipairs(pool) do
        if not obj:IsShown() then
            return obj
        end
    end
    local obj = createFn()
    pool[#pool + 1] = obj
    return obj
end

local function CreateBlock(parent)
    local block = CreateFrame("Button", nil, parent, "BackdropTemplate")
    block:SetSize(BLOCK_WIDTH, BLOCK_HEIGHT)
    block:SetBackdrop(BACKDROP_INFO)
    block:SetBackdropColor(0, 0, 0, 0.7)

    block.who = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    block.who:SetPoint("TOPLEFT", 4, -3)
    block.who:SetPoint("RIGHT", -4, 0)
    block.who:SetJustifyH("LEFT")
    block.who:SetWordWrap(false)

    block.ability = block:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    block.ability:SetPoint("TOPLEFT", block.who, "BOTTOMLEFT", 0, -1)
    block.ability:SetPoint("RIGHT", -4, 0)
    block.ability:SetJustifyH("LEFT")
    block.ability:SetWordWrap(false)
    block.ability:SetTextColor(0.8, 0.8, 0.8)

    block.extra = block:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    block.extra:SetPoint("TOPLEFT", block.ability, "BOTTOMLEFT", 0, -1)
    block.extra:SetPoint("RIGHT", -4, 0)
    block.extra:SetJustifyH("LEFT")
    block.extra:SetWordWrap(false)
    block.extra:SetTextColor(0.5, 0.5, 0.5)

    block.personalBorder = block:CreateTexture(nil, "OVERLAY")
    block.personalBorder:SetAllPoints()
    block.personalBorder:SetColorTexture(0.94, 0.75, 0.25, 0.15)
    block.personalBorder:Hide()

    block.annotatedDot = block:CreateTexture(nil, "OVERLAY")
    block.annotatedDot:SetSize(8, 8)
    block.annotatedDot:SetPoint("TOPRIGHT", -1, -1)
    block.annotatedDot:SetColorTexture(0.94, 0.75, 0.25, 1)
    block.annotatedDot:Hide()

    block:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.91, 0.27, 0.37, 1)
    end)
    block:SetScript("OnLeave", function(self)
        if self.isPersonal or self.isAnnotated then
            self:SetBackdropBorderColor(0.94, 0.75, 0.25, 1)
        else
            self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        end
    end)

    return block
end

local function CreateGridLine(parent)
    local line = parent:CreateTexture(nil, "BACKGROUND")
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.04)
    return line
end

local function CreateTick(parent)
    local tick = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tick:SetTextColor(0.5, 0.5, 0.5)
    tick:SetJustifyH("RIGHT")
    return tick
end

local function CreatePhaseDivider(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(14)

    holder.line = holder:CreateTexture(nil, "ARTWORK")
    holder.line:SetHeight(2)
    holder.line:SetPoint("TOPLEFT")
    holder.line:SetPoint("TOPRIGHT")
    holder.line:SetColorTexture(0.91, 0.27, 0.37, 1)

    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", holder.line, "BOTTOMLEFT", 4, -2)
    holder.label:SetTextColor(0.91, 0.27, 0.37, 1)

    return holder
end

local function CreateFreeformSeparator(parent)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(14)

    holder.line = holder:CreateTexture(nil, "ARTWORK")
    holder.line:SetHeight(1)
    holder.line:SetPoint("TOPLEFT")
    holder.line:SetPoint("TOPRIGHT")

    holder.label = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    holder.label:SetPoint("TOPLEFT", holder.line, "BOTTOMLEFT", 4, -2)
    holder.label:SetFont(holder.label:GetFont(), 9)

    return holder
end

local function CreatePhaseTab(parent)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(22)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.bg:SetColorTexture(0.91, 0.27, 0.37, 0.8)
    tab.bg:Hide()

    tab.highlight = tab:CreateTexture(nil, "HIGHLIGHT")
    tab.highlight:SetAllPoints()
    tab.highlight:SetColorTexture(1, 1, 1, 0.05)

    tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.text:SetPoint("CENTER")
    tab.text:SetTextColor(0.6, 0.6, 0.6)

    tab.underline = tab:CreateTexture(nil, "OVERLAY")
    tab.underline:SetHeight(2)
    tab.underline:SetPoint("BOTTOMLEFT")
    tab.underline:SetPoint("BOTTOMRIGHT")
    tab.underline:SetColorTexture(0.91, 0.27, 0.37, 1)
    tab.underline:Hide()

    return tab
end

local editFields = {}
local currentAbilities = {}

local function CreateFieldLabel(parent, text)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetTextColor(0.5, 0.5, 0.5)
    label:SetText(text)
    return label
end

local function CreateFieldInput(parent)
    local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return box
end

local function CreateFieldDropdown(parent, getItems, onSelect)
    local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dropdown:SetHeight(22)
    dropdown.getItems = getItems
    dropdown.onSelect = onSelect
    dropdown.currentValue = nil

    dropdown:SetupMenu(function(_, rootDescription)
        local items = dropdown.getItems()
        for _, item in ipairs(items) do
            rootDescription:CreateRadio(
                item.name,
                function() return dropdown.currentValue == item.value end,
                function()
                    dropdown.currentValue = item.value
                    if dropdown.onSelect then
                        dropdown.onSelect(item.value)
                    end
                end
            )
        end
    end)

    function dropdown:SetValue(value)
        self.currentValue = value
        self:GenerateMenu()
    end

    function dropdown:GetValue()
        return self.currentValue
    end

    return dropdown
end

local function BuildEditPanel()
    local panel = CreateFrame("Frame", "PRT_NotesEditPanel", UIParent, "ButtonFrameTemplate")
    panel:SetSize(EDIT_PANEL_WIDTH, 500)
    panel:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    panel:SetFrameStrata("DIALOG")
    panel:SetToplevel(true)
    panel:Hide()

    ButtonFrameTemplate_HidePortrait(panel)
    ButtonFrameTemplate_HideButtonBar(panel)
    panel.Inset:Hide()

    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    panel:SetScript("OnHide", function()
        state.editingReminder = nil
    end)

    panel.headerText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.headerText:SetPoint("TOPLEFT", 12, -28)
    panel.headerText:SetTextColor(0.91, 0.27, 0.37, 1)

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -46)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 40)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(EDIT_PANEL_WIDTH - 44)
    scrollChild:SetHeight(600)
    scrollFrame:SetScrollChild(scrollChild)

    local yOff = 0
    local fieldWidth = EDIT_PANEL_WIDTH - 48

    local function AddLabel(text)
        local label = CreateFieldLabel(scrollChild, text)
        label:SetPoint("TOPLEFT", 4, yOff)
        yOff = yOff - 14
        return label
    end

    local function AddInput()
        local input = CreateFieldInput(scrollChild)
        input:SetPoint("TOPLEFT", 4, yOff)
        input:SetWidth(fieldWidth)
        yOff = yOff - 28
        return input
    end

    local function AddDropdown(getItems, onSelect)
        local dd = CreateFieldDropdown(scrollChild, getItems, onSelect)
        dd:SetPoint("TOPLEFT", 4, yOff)
        dd:SetWidth(fieldWidth)
        yOff = yOff - 28
        return dd
    end

    panel.originalInfo = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.originalInfo:SetPoint("TOPLEFT", 4, yOff)
    panel.originalInfo:SetWidth(fieldWidth)
    panel.originalInfo:SetJustifyH("LEFT")
    panel.originalInfo:SetTextColor(0.5, 0.5, 0.5)
    panel.originalInfo:SetWordWrap(true)
    panel.originalInfo:Hide()
    panel.originalInfoLabel = AddLabel("THIS REMINDER")
    panel.originalInfoLabel:Hide()

    editFields.phaseLabel = AddLabel("PHASE")
    editFields.phase = AddInput()
    editFields.phase:SetNumeric(true)

    editFields.timeLabel = AddLabel("TIME (PHASE-RELATIVE)")
    editFields.time = AddInput()

    editFields.whoLabel = AddLabel("WHO")
    editFields.who = AddInput()
    editFields.who:SetScript("OnTextChanged", function(self)
        local tag = self:GetText()
        local abilities = GetAbilitiesForTag(tag)
        currentAbilities = abilities
        editFields.ability:GenerateMenu()
    end)

    editFields.abilityLabel = AddLabel("ABILITY")
    editFields.ability = AddDropdown(
        function()
            local items = { { name = "(free text)", value = "" } }
            for _, ab in ipairs(currentAbilities) do
                items[#items + 1] = { name = ab.name, value = ab.name }
            end
            return items
        end,
        function(value)
            if value and value ~= "" then
                editFields.abilityText = value
                editFields.abilitySpellId = nil
                for _, ab in ipairs(currentAbilities) do
                    if ab.name == value then
                        editFields.abilitySpellId = ab.spellId
                        break
                    end
                end
            else
                editFields.abilityText = nil
                editFields.abilitySpellId = nil
            end
        end
    )

    editFields.displayTextLabel = AddLabel("DISPLAY TEXT (OPTIONAL)")
    editFields.displayText = AddInput()

    editFields.durationLabel = AddLabel("DURATION")
    editFields.duration = AddInput()
    editFields.duration:SetNumeric(false)

    editFields.displayTypeLabel = AddLabel("DISPLAY TYPE")
    editFields.displayType = AddDropdown(
        function() return DISPLAY_TYPE_OPTIONS end,
        function() end
    )

    editFields.soundLabel = AddLabel("SOUND")
    editFields.sound = AddInput()

    editFields.ttsLabel = AddLabel("TTS")
    editFields.tts = AddInput()

    editFields.ttsTimerLabel = AddLabel("TTS TIMER")
    editFields.ttsTimer = AddInput()
    editFields.ttsTimer:SetNumeric(false)

    editFields.countdownLabel = AddLabel("COUNTDOWN")
    editFields.countdown = AddInput()
    editFields.countdown:SetNumeric(false)

    editFields.bossSpellLabel = AddLabel("BOSS SPELL ID")
    editFields.bossSpell = AddInput()

    editFields.colorsLabel = AddLabel("COLORS")
    editFields.colors = AddInput()

    local allFields = {
        { label = panel.originalInfoLabel, field = panel.originalInfo, fieldHeight = 32 },
        { label = editFields.phaseLabel, field = editFields.phase },
        { label = editFields.timeLabel, field = editFields.time },
        { label = editFields.whoLabel, field = editFields.who },
        { label = editFields.abilityLabel, field = editFields.ability },
        { label = editFields.displayTextLabel, field = editFields.displayText },
        { label = editFields.durationLabel, field = editFields.duration },
        { label = editFields.displayTypeLabel, field = editFields.displayType },
        { label = editFields.soundLabel, field = editFields.sound },
        { label = editFields.ttsLabel, field = editFields.tts },
        { label = editFields.ttsTimerLabel, field = editFields.ttsTimer },
        { label = editFields.countdownLabel, field = editFields.countdown },
        { label = editFields.bossSpellLabel, field = editFields.bossSpell },
        { label = editFields.colorsLabel, field = editFields.colors },
    }

    local function layoutFields(visibleSet)
        local lookup = {}
        for _, entry in ipairs(visibleSet) do
            lookup[entry] = true
        end

        local y = 0
        for _, row in ipairs(allFields) do
            if lookup[row.field] then
                row.label:ClearAllPoints()
                row.label:SetPoint("TOPLEFT", 4, y)
                row.label:Show()
                y = y - 14
                row.field:ClearAllPoints()
                row.field:SetPoint("TOPLEFT", 4, y)
                row.field:Show()
                y = y - (row.fieldHeight or 28)
            else
                row.label:Hide()
                row.field:Hide()
            end
        end
        scrollChild:SetHeight(math.abs(y) + 20)
    end

    function panel:LayoutForEdit()
        layoutFields({
            editFields.phase, editFields.time, editFields.who,
            editFields.ability, editFields.displayText, editFields.duration,
            editFields.bossSpell,
        })
    end

    function panel:LayoutForAnnotate()
        layoutFields({
            panel.originalInfo,
            editFields.displayType, editFields.sound, editFields.tts,
            editFields.ttsTimer, editFields.countdown,
        })
    end

    function panel:LayoutForAddPersonal()
        layoutFields({
            editFields.phase, editFields.time, editFields.ability,
            editFields.displayText, editFields.displayType, editFields.sound,
            editFields.tts, editFields.ttsTimer, editFields.countdown,
        })
    end

    local footer = CreateFrame("Frame", nil, panel)
    footer:SetHeight(36)
    footer:SetPoint("BOTTOMLEFT", 8, 4)
    footer:SetPoint("BOTTOMRIGHT", -8, 4)

    local deleteBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    deleteBtn:SetSize(70, 22)
    deleteBtn:SetPoint("LEFT", 0, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:Hide()
    panel.deleteBtn = deleteBtn

    local saveBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    saveBtn:SetSize(70, 22)
    saveBtn:SetPoint("RIGHT", 0, 0)
    saveBtn:SetText("Save")
    panel.saveBtn = saveBtn

    local cancelBtn = CreateFrame("Button", nil, footer, "UIPanelButtonTemplate")
    cancelBtn:SetSize(70, 22)
    cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
        panel:Hide()
        state.editingReminder = nil
    end)

    local errorText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    errorText:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 2)
    errorText:SetWidth(EDIT_PANEL_WIDTH - 20)
    errorText:SetJustifyH("LEFT")
    errorText:SetTextColor(1, 0.3, 0.3, 1)
    panel.errorText = errorText

    return panel
end

local function BuildFrame()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "PRT_NotesEditor", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(frame)
    ButtonFrameTemplate_HideButtonBar(frame)
    frame.Inset:Hide()
    frame:SetTitle("Note Editor")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
        SaveEditorPosition()
    end)
    frame:Hide()

    frame:SetScript("OnHide", function()
        SaveEditorPosition()
        editPanel:Hide()
        if not state.rawMode then
            state = {}
        end
    end)

    table.insert(UISpecialFrames, "PRT_NotesEditor")

    titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(28)
    titleBar:SetPoint("TOPLEFT", 8, -28)
    titleBar:SetPoint("TOPRIGHT", -8, -28)

    titleBar.nameText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleBar.nameText:SetPoint("LEFT", 8, 0)
    titleBar.nameText:SetTextColor(0.91, 0.27, 0.37, 1)
    titleBar.nameText:EnableMouse(true)

    titleBar.nameEdit = CreateFrame("EditBox", nil, titleBar, "InputBoxTemplate")
    titleBar.nameEdit:SetSize(150, 20)
    titleBar.nameEdit:SetPoint("LEFT", 4, 0)
    titleBar.nameEdit:SetAutoFocus(false)
    titleBar.nameEdit:Hide()
    titleBar.nameEdit:SetScript("OnEnterPressed", function(self)
        local newName = self:GetText():match("^%s*(.-)%s*$")
        if not newName or newName == "" then
            self:Hide()
            titleBar.nameText:Show()
            return
        end
        if not state.noteName then
            local text = PRT.NotesSerializer:Serialize(state.parsedNote)
            local ok = PRT.Notes:SaveNote(newName, text)
            if ok then
                state.noteName = newName
                NotesEditor:NotifyConfigSaved(newName)
            end
        elseif newName ~= state.noteName then
            if PRT.Notes:RenameNote(state.noteName, newName) then
                state.noteName = newName
                NotesEditor:NotifyConfigSaved(newName)
            end
        end
        self:Hide()
        titleBar.nameText:Show()
        titleBar.nameText:SetText(state.noteName or "New Note")
    end)
    titleBar.nameEdit:SetScript("OnEscapePressed", function(self)
        self:Hide()
        titleBar.nameText:Show()
    end)

    titleBar.nameText:SetScript("OnMouseDown", function()
        titleBar.nameEdit:SetText(state.noteName or "")
        titleBar.nameText:Hide()
        titleBar.nameEdit:Show()
        titleBar.nameEdit:SetFocus()
        titleBar.nameEdit:HighlightText()
    end)

    titleBar.encounterText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleBar.encounterText:SetPoint("LEFT", titleBar.nameText, "RIGHT", 12, 0)
    titleBar.encounterText:SetTextColor(0.5, 0.5, 0.5)

    titleBar.difficultyDropdown = CreateFieldDropdown(titleBar,
        function() return DIFFICULTY_OPTIONS end,
        function(value)
            if state.parsedNote then
                state.parsedNote.difficulty = value
            end
            state.difficulty = value
            NotesEditor:SaveCurrentNote()
        end
    )
    titleBar.difficultyDropdown:SetSize(100, 20)
    titleBar.difficultyDropdown:SetPoint("LEFT", titleBar.encounterText, "RIGHT", 12, 0)

    modeBar = CreateFrame("Frame", nil, frame)
    modeBar:SetHeight(24)
    modeBar:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
    modeBar:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)

    modeBar.showMineCheck = CreateFrame("CheckButton", nil, modeBar, "UICheckButtonTemplate")
    modeBar.showMineCheck:SetSize(20, 20)
    modeBar.showMineCheck:SetPoint("LEFT", 8, 0)
    modeBar.showMineCheck:SetScript("OnClick", function(self)
        state.showOnlyMine = self:GetChecked()
        NotesEditor:Render()
    end)

    modeBar.showMineLabel = modeBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeBar.showMineLabel:SetPoint("LEFT", modeBar.showMineCheck, "RIGHT", 2, 0)
    modeBar.showMineLabel:SetText("Show Only Mine")

    modeBar.annotateBtn = CreateFrame("Button", nil, modeBar, "UIPanelButtonTemplate")
    modeBar.annotateBtn:SetSize(80, 20)
    modeBar.annotateBtn:SetPoint("RIGHT", -100, 0)
    modeBar.annotateBtn:SetText("Annotate")
    modeBar.annotateBtn:SetScript("OnClick", function()
        if not state.noteName then
            return
        end
        local text = PRT.NotesSerializer:Serialize(state.parsedNote)
        NotesEditor:Open(state.noteName, text, "annotate")
    end)

    modeBar.rawBtn = CreateFrame("Button", nil, modeBar, "UIPanelButtonTemplate")
    modeBar.rawBtn:SetSize(80, 20)
    modeBar.rawBtn:SetPoint("RIGHT", -8, 0)
    modeBar.rawBtn:SetText("Import")
    modeBar.rawBtn:SetScript("OnClick", function()
        state.rawMode = true
        NotesEditor:ShowRawMode()
    end)

    phaseTabs = CreateFrame("Frame", nil, frame)
    phaseTabs:SetHeight(24)
    phaseTabs:SetPoint("TOPLEFT", modeBar, "BOTTOMLEFT", 0, -2)
    phaseTabs:SetPoint("TOPRIGHT", modeBar, "BOTTOMRIGHT", 0, -2)

    timelineArea = CreateFrame("Frame", nil, frame)
    timelineArea:SetPoint("TOPLEFT", phaseTabs, "BOTTOMLEFT", 0, -2)
    timelineArea:SetPoint("BOTTOMRIGHT", -6, 6)

    rulerFrame = CreateFrame("Frame", nil, timelineArea, "BackdropTemplate")
    rulerFrame:SetWidth(RULER_WIDTH)
    rulerFrame:SetPoint("TOPLEFT")
    rulerFrame:SetPoint("BOTTOMLEFT")
    rulerFrame:SetBackdrop(BACKDROP_INFO)
    rulerFrame:SetBackdropColor(0, 0, 0, 0.8)
    rulerFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    rulerFrame:SetClipsChildren(true)

    bodyScroll = CreateFrame("ScrollFrame", nil, timelineArea, "UIPanelScrollFrameTemplate")
    bodyScroll:SetPoint("TOPLEFT", rulerFrame, "TOPRIGHT", 0, 0)
    bodyScroll:SetPoint("BOTTOMRIGHT", -26, 0)

    canvas = CreateFrame("Frame", nil, bodyScroll)
    canvas:SetSize(400, 2000)
    bodyScroll:SetScrollChild(canvas)

    canvas:EnableMouse(true)
    canvas:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then
            return
        end
        local _, cursorY = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local y = self:GetTop() - (cursorY / scale)
        local phases = DerivePhases(state.parsedNote)
        local time, phaseNum = YToTimeAndPhase(y, phases, state.activePhase)
        NotesEditor:OpenAddPanel(time, phaseNum)
    end)

    cursorLine = canvas:CreateTexture(nil, "OVERLAY")
    cursorLine:SetHeight(1)
    cursorLine:SetColorTexture(0.94, 0.75, 0.25, 0.8)
    cursorLine:Hide()

    cursorLabel = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cursorLabel:SetTextColor(0.94, 0.75, 0.25, 1)
    cursorLabel:Hide()

    bodyScroll:HookScript("OnScrollRangeChanged", function()
        NotesEditor:SyncRuler()
    end)

    bodyScroll:HookScript("OnVerticalScroll", function()
        NotesEditor:SyncRuler()
    end)

    local cursorUpdateFrame = CreateFrame("Frame", nil, canvas)
    cursorUpdateFrame:SetScript("OnUpdate", function()
        if not canvas:IsMouseOver() then
            cursorLine:Hide()
            cursorLabel:Hide()
            return
        end
        cursorLine:Show()
        cursorLabel:Show()
        local _, cursorY = GetCursorPosition()
        local scale = canvas:GetEffectiveScale()
        local y = canvas:GetTop() - (cursorY / scale)
        local phases = DerivePhases(state.parsedNote)
        local time, _ = YToTimeAndPhase(y, phases, state.activePhase)
        cursorLine:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
        cursorLine:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -y)
        cursorLabel:SetPoint("TOPLEFT", canvas, "TOPLEFT", 4, -(y + 2))
        cursorLabel:SetText(FormatTime(time))
    end)

    editPanel = BuildEditPanel()
end

function NotesEditor:SyncRuler()
    if not rulerFrame or not bodyScroll then
        return
    end
    local offset = bodyScroll:GetVerticalScroll()
    rulerFrame.yOffset = offset
    for _, tick in ipairs(tickPool) do
        if tick:IsShown() and tick.baseY then
            tick:SetPoint("TOPRIGHT", rulerFrame, "TOPRIGHT", -4, -(tick.baseY - offset))
        end
    end
end

function NotesEditor:RenderPhaseTabs()
    RecyclePool(phaseTabPool)

    local phases = DerivePhases(state.parsedNote)
    if #phases <= 1 then
        phaseTabs:SetHeight(1)
        return
    end

    phaseTabs:SetHeight(24)
    local xOff = 4

    local allTab = GetFromPool(phaseTabPool, function()
        return CreatePhaseTab(phaseTabs)
    end)
    allTab:SetWidth(80)
    allTab:SetPoint("TOPLEFT", xOff, -1)
    allTab.text:SetText("All Phases")
    if state.activePhase == "all" then
        allTab.underline:Show()
        allTab.text:SetTextColor(1, 1, 1)
    else
        allTab.underline:Hide()
        allTab.text:SetTextColor(0.6, 0.6, 0.6)
    end
    allTab:SetScript("OnClick", function()
        state.activePhase = "all"
        editPanel:Hide()
        state.editingReminder = nil
        self:Render()
    end)
    allTab:Show()
    xOff = xOff + 84

    for _, phase in ipairs(phases) do
        local tab = GetFromPool(phaseTabPool, function()
            return CreatePhaseTab(phaseTabs)
        end)
        tab:SetWidth(80)
        tab:SetPoint("TOPLEFT", xOff, -1)
        tab.text:SetText(phase.name)
        if state.activePhase == phase.num then
            tab.underline:Show()
            tab.text:SetTextColor(1, 1, 1)
        else
            tab.underline:Hide()
            tab.text:SetTextColor(0.6, 0.6, 0.6)
        end
        tab:SetScript("OnClick", function()
            state.activePhase = phase.num
            editPanel:Hide()
            state.editingReminder = nil
            self:Render()
        end)
        tab:Show()
        xOff = xOff + 84
    end
end

function NotesEditor:RenderTimeline()
    RecyclePool(blockPool)
    RecyclePool(gridPool)
    RecyclePool(tickPool)
    RecyclePool(phaseDividerPool)
    RecyclePool(freeformPool)

    local phases = DerivePhases(state.parsedNote)
    local totalDur = TotalDuration(phases, state.activePhase)
    local canvasHeight = totalDur * VPPS + TOP_PAD + 20
    canvas:SetHeight(canvasHeight)
    canvas:SetWidth(bodyScroll:GetWidth() - 26)
    bodyScroll:UpdateScrollChildRect()

    for t = GRID_INTERVAL, totalDur, GRID_INTERVAL do
        local y = t * VPPS + TOP_PAD
        local line = GetFromPool(gridPool, function()
            return CreateGridLine(canvas)
        end)
        line:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
        line:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -y)
        line:Show()
    end

    if state.activePhase == "all" then
        for i, phase in ipairs(phases) do
            if i > 1 then
                local y = phase.start * VPPS + TOP_PAD
                local divider = GetFromPool(phaseDividerPool, function()
                    return CreatePhaseDivider(canvas)
                end)
                divider:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
                divider:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", 0, -y)
                divider.label:SetText(phase.name)
                divider:Show()
            end
        end
    end

    local function PlaceTick(t, y)
        local tick = GetFromPool(tickPool, function()
            return CreateTick(rulerFrame)
        end)
        tick.baseY = y
        tick:SetText(FormatTime(t))
        local scrollOffset = bodyScroll:GetVerticalScroll()
        tick:SetPoint("TOPRIGHT", rulerFrame, "TOPRIGHT", -4, -(y - scrollOffset))
        tick:Show()
    end

    if state.activePhase == "all" then
        for pi, phase in ipairs(phases) do
            local isLast = (pi == #phases)
            for t = 0, phase.duration, TICK_INTERVAL do
                -- The boundary tick is skipped; the next phase's 0:00 covers it.
                local isCoveredBoundary = not isLast and t == phase.duration
                if not isCoveredBoundary and t % TICK_LABEL_INTERVAL == 0 then
                    PlaceTick(t, (phase.start + t) * VPPS + TOP_PAD)
                end
            end
        end
    else
        local phase
        for _, p in ipairs(phases) do
            if p.num == state.activePhase then
                phase = p
                break
            end
        end
        local dur = phase and phase.duration or PHASE_PAD
        for t = 0, dur, TICK_INTERVAL do
            if t % TICK_LABEL_INTERVAL == 0 then
                PlaceTick(t, t * VPPS + TOP_PAD)
            end
        end
    end

    local reminders = CollectReminders(state.parsedNote, state.activePhase)

    local playerCtx
    if state.mode == "annotate" then
        playerCtx = BuildPlayerCtx()
    end

    local columns = {}

    local function blockHeight(reminder)
        local dur = reminder.duration or 5
        local h = dur * VPPS
        if h < BLOCK_HEIGHT then
            h = BLOCK_HEIGHT
        end

        if state.activePhase == "all" then
            for _, p in ipairs(phases) do
                if p.num == reminder.phase then
                    local maxH = (p.duration - reminder.time) * VPPS
                    if maxH > 0 and h > maxH then
                        h = maxH
                    end
                    break
                end
            end
        end

        return h
    end

    local function findColumn(y, height)
        local blockBottom = y + height + BLOCK_GAP
        for col = 1, #columns do
            if y >= columns[col] then
                columns[col] = blockBottom
                return col - 1
            end
        end
        columns[#columns + 1] = blockBottom
        return #columns - 1
    end

    for _, r in ipairs(reminders) do
        local shouldRender = true
        if state.mode == "annotate" and state.showOnlyMine then
            if not PRT.NotesTags.Matches(r.tag, playerCtx) and not r.isPersonal then
                shouldRender = false
            end
        end
        if shouldRender then
            local y = TimeToY(r.time, r.phase, phases, state.activePhase)
            local h = blockHeight(r)
            local stackIdx = findColumn(y, h)
            NotesEditor:RenderBlock(r, y, stackIdx, h, phases, playerCtx)
        end
    end

    local freeformLines = CollectFreeformLines(state.parsedNote, state.activePhase)
    local isAnnotateMode = state.mode == "annotate"
    for _, fl in ipairs(freeformLines) do
        local y = TimeToY(fl.time, fl.phase, phases, state.activePhase)
        local sep = GetFromPool(freeformPool, function()
            return CreateFreeformSeparator(canvas)
        end)
        sep:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, -y)
        sep:SetPoint("RIGHT", canvas, "RIGHT", 0, 0)
        sep:SetFrameLevel(canvas:GetFrameLevel() + 3)

        sep.line:SetColorTexture(0.4, 0.7, 1, 0.5)
        sep.label:SetTextColor(0.4, 0.7, 1, 0.8)

        sep.label:SetText(fl.text)
        sep:Show()
    end
end

function NotesEditor:RenderBlock(reminder, y, stackIdx, height, phases, playerCtx)
    local block = GetFromPool(blockPool, function()
        return CreateBlock(canvas)
    end)

    block:SetPoint("TOPLEFT", canvas, "TOPLEFT", stackIdx * (BLOCK_WIDTH + BLOCK_GAP), -y)
    block:SetHeight(height)
    block:SetFrameLevel(canvas:GetFrameLevel() + 5)

    local r, g, b = ClassColorForTag(reminder.tag)
    block.who:SetText(reminder.tag or "")
    block.who:SetTextColor(r, g, b)

    local abilityText = reminder.text or ""
    block.ability:SetText(abilityText)

    block.extra:SetText("")
    block.extra:Hide()

    block.isPersonal = reminder.isPersonal or false
    block.isAnnotated = reminder.isAnnotated or false

    if reminder.isPersonal then
        block:SetBackdropBorderColor(0.94, 0.75, 0.25, 1)
        block.personalBorder:Show()
    elseif reminder.isAnnotated then
        block:SetBackdropBorderColor(0.94, 0.75, 0.25, 1)
        block.personalBorder:Hide()
    else
        block:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        block.personalBorder:Hide()
    end

    local isInteractive = true
    if state.mode == "annotate" and playerCtx
            and not reminder.isPersonal
            and not PRT.NotesTags.Matches(reminder.tag, playerCtx) then
        isInteractive = false
    end
    block:SetAlpha(isInteractive and 1 or 0.4)

    block:SetScript("OnClick", function()
        if not isInteractive then
            return
        end
        NotesEditor:OpenEditPanel(reminder)
    end)

    block:Show()
end

function NotesEditor:Render()
    if not frame or not frame:IsShown() then
        return
    end

    if state.mode == "annotate" then
        modeBar.showMineCheck:Show()
        modeBar.showMineLabel:Show()
        modeBar.rawBtn:Hide()
        modeBar.annotateBtn:Hide()
        frame:SetTitle("Annotate Note")
    else
        modeBar.showMineCheck:Hide()
        modeBar.showMineLabel:Hide()
        modeBar.rawBtn:Show()
        modeBar.annotateBtn:Show()
        frame:SetTitle("Edit Note")
    end

    titleBar.nameText:SetText(state.noteName or "New Note")
    titleBar.encounterText:SetText(state.encounterName or "")
    titleBar.difficultyDropdown:SetValue(state.difficulty)

    self:RenderPhaseTabs()
    self:RenderTimeline()
end

local rawFrame

local function BuildRawFrame()
    if rawFrame then
        return
    end

    rawFrame = CreateFrame("Frame", "PRT_NotesRawEditor", UIParent, "ButtonFrameTemplate")
    rawFrame:SetSize(600, 450)
    rawFrame:SetPoint("CENTER")
    rawFrame:SetFrameStrata("DIALOG")
    rawFrame:SetToplevel(true)
    rawFrame:Hide()

    ButtonFrameTemplate_HidePortrait(rawFrame)
    ButtonFrameTemplate_HideButtonBar(rawFrame)
    rawFrame.Inset:Hide()
    rawFrame:SetTitle("Import")

    rawFrame:SetMovable(true)
    rawFrame:SetClampedToScreen(true)
    rawFrame:EnableMouse(true)
    rawFrame:RegisterForDrag("LeftButton")
    rawFrame:SetScript("OnDragStart", rawFrame.StartMoving)
    rawFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)

    rawFrame:SetScript("OnHide", function()
        if not state.switchingToVisual then
            state = {}
        end
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, rawFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 50)

    local textBg = CreateFrame("Frame", nil, rawFrame, "BackdropTemplate")
    textBg:SetPoint("TOPLEFT", scrollFrame, -4, 4)
    textBg:SetPoint("BOTTOMRIGHT", scrollFrame, 26, -4)
    textBg:SetBackdrop(BACKDROP_INFO)
    textBg:SetBackdropColor(0, 0, 0, 0.5)
    textBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    textBg:SetFrameLevel(rawFrame:GetFrameLevel() + 1)
    textBg:EnableMouse(false)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    editBox:SetScript("OnEscapePressed", function() rawFrame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    rawFrame.EditBox = editBox

    rawFrame.errorText = rawFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rawFrame.errorText:SetPoint("BOTTOMLEFT", 12, 30)
    rawFrame.errorText:SetPoint("RIGHT", -12, 0)
    rawFrame.errorText:SetJustifyH("LEFT")
    rawFrame.errorText:SetTextColor(1, 0.3, 0.3, 1)

    local saveBtn = CreateFrame("Button", nil, rawFrame, "UIPanelButtonTemplate")
    saveBtn:SetSize(70, 24)
    saveBtn:SetPoint("BOTTOMRIGHT", -12, 4)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        NotesEditor:SaveAndCloseRaw()
    end)

    local visualBtn = CreateFrame("Button", nil, rawFrame, "UIPanelButtonTemplate")
    visualBtn:SetSize(70, 24)
    visualBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
    visualBtn:SetText("Edit")
    visualBtn:SetScript("OnClick", function()
        NotesEditor:SwitchToVisual()
    end)
end

function NotesEditor:ShowRawMode()
    BuildRawFrame()

    local text = PRT.NotesSerializer:Serialize(state.parsedNote)
    rawFrame.EditBox:SetText(text or "")
    rawFrame.errorText:SetText("")

    frame:Hide()
    rawFrame:Show()
end

function NotesEditor:SaveRawText()
    local rawText = rawFrame.EditBox:GetText()
    local parsed, err = PRT.NotesParser:Parse(rawText)
    if err then
        rawFrame.errorText:SetText(err)
        return false
    end

    state.rawMode = false
    state.parsedNote = parsed
    state.encounterName = parsed.name or (parsed.encounterID and tostring(parsed.encounterID)) or ""
    state.difficulty = parsed.difficulty

    local normalizedText = PRT.NotesSerializer:Serialize(parsed)
    state.noteText = normalizedText

    if state.noteName then
        local ok, saveErr = PRT.Notes:SaveNote(state.noteName, normalizedText)
        if ok then
            NotesEditor:NotifyConfigSaved(state.noteName)
        else
            rawFrame.errorText:SetText(saveErr or "")
            return false
        end
    end

    return true
end

function NotesEditor:SaveAndCloseRaw()
    if not self:SaveRawText() then
        return
    end
    rawFrame:Hide()
    state = {}
end

function NotesEditor:SwitchToVisual()
    if not self:SaveRawText() then
        return
    end
    state.switchingToVisual = true
    rawFrame:Hide()
    state.switchingToVisual = nil
    frame:Show()
    self:Render()
end

local function EnsureAnnotationNote()
    if not state.annotationNote then
        state.annotationNote = {
            encounterID = state.parsedNote and state.parsedNote.encounterID,
            reminders = {},
            lines = {},
        }
    end
    return state.annotationNote
end

local function AppendReminderToNote(note, reminder)
    local bucket = note.reminders[reminder.phaseKey]
    if not bucket then
        bucket = {}
        note.reminders[reminder.phaseKey] = bucket
    end
    bucket[#bucket + 1] = reminder
    SortRemindersByTime(bucket)
    note.lines[#note.lines + 1] = { type = "reminder", reminder = reminder }
end

local function RemoveReminderFromNote(note, reminder)
    local bucket = note.reminders[reminder.phaseKey]
    if bucket then
        for i, r in ipairs(bucket) do
            if r == reminder then
                table.remove(bucket, i)
                break
            end
        end
        if #bucket == 0 then
            note.reminders[reminder.phaseKey] = nil
        end
    end

    for i, entry in ipairs(note.lines) do
        if entry.type == "reminder" and entry.reminder == reminder then
            table.remove(note.lines, i)
            break
        end
    end
end

function NotesEditor:OpenAddPanel(time, phaseNum)
    editPanel:Show()
    editPanel.errorText:SetText("")
    editPanel.deleteBtn:Hide()
    state.editingReminder = nil

    editFields.phase:SetText(tostring(phaseNum or 1))
    editFields.time:SetText(FormatTime(time or 0))
    editFields.who:SetText("")
    editFields.who:Enable()
    editFields.ability:SetValue("")
    editFields.abilityText = nil
    editFields.abilitySpellId = nil
    editFields.displayText:SetText("")
    editFields.duration:SetText("5")
    editFields.displayType:SetValue("Icon")
    editFields.sound:SetText("")
    editFields.tts:SetText("")
    editFields.ttsTimer:SetText("")
    editFields.countdown:SetText("")
    editFields.bossSpell:SetText("")
    editFields.colors:SetText("")
    currentAbilities = {}
    editFields.ability:GenerateMenu()

    if state.mode == "annotate" then
        editPanel:SetTitle("Add Personal Reminder")
        editPanel.saveBtn:SetText("Add")
        editFields.who:SetText(UnitName("player") or "")
        editFields.who:Disable()
        currentAbilities = GetLocalPlayerAbilities()
        editFields.ability:GenerateMenu()
        editPanel:LayoutForAddPersonal()
    else
        editPanel:SetTitle("Add Reminder")
        editPanel.saveBtn:SetText("Add")
        editPanel:LayoutForEdit()
    end

    editPanel.saveBtn:SetScript("OnClick", function()
        NotesEditor:SaveFromPanel()
    end)
end

function NotesEditor:OpenEditPanel(reminder)
    editPanel:Show()
    editPanel.errorText:SetText("")
    state.editingReminder = reminder

    if state.mode == "annotate" and not reminder.isPersonal then
        editPanel:SetTitle("Customize Alert")
        editPanel.deleteBtn:Hide()
        editPanel.saveBtn:SetText("Save")

        editPanel.originalInfo:SetText(
            FormatTime(reminder.time) .. " - " .. (reminder.tag or "") .. " - " .. (reminder.text or "")
        )
        editFields.displayType:SetValue(reminder.displayType or "Icon")
        editFields.sound:SetText(reminder.sound or "")
        editFields.tts:SetText(FormatTTSValue(reminder.tts))
        editFields.ttsTimer:SetText(reminder.ttsTimer and tostring(reminder.ttsTimer) or "")
        editFields.countdown:SetText(reminder.countdown and tostring(reminder.countdown) or "")

        editPanel:LayoutForAnnotate()
        editPanel.saveBtn:SetScript("OnClick", function()
            NotesEditor:SaveAnnotationFromPanel()
        end)
        return
    end

    if state.mode == "annotate" and reminder.isPersonal then
        editPanel:SetTitle("Edit Personal Reminder")
        editPanel.deleteBtn:Show()
    else
        editPanel:SetTitle("Edit Reminder")
        editPanel.deleteBtn:Show()
    end
    editPanel.saveBtn:SetText("Save")

    editFields.phase:SetText(tostring(reminder.phase or 1))
    editFields.time:SetText(FormatTime(reminder.time))
    editFields.who:SetText(reminder.tag or "")
    editFields.who:Enable()
    currentAbilities = GetAbilitiesForTag(reminder.tag)

    local abilityName, displayText = SplitAbilityAndText(reminder.text, currentAbilities)
    editFields.ability:SetValue(abilityName)
    editFields.abilityText = abilityName
    editFields.ability:GenerateMenu()
    editFields.displayText:SetText(displayText)

    editFields.duration:SetText(tostring(reminder.duration or 5))
    editFields.displayType:SetValue(reminder.displayType or "Icon")
    editFields.sound:SetText(reminder.sound or "")
    editFields.tts:SetText(FormatTTSValue(reminder.tts))
    editFields.ttsTimer:SetText(reminder.ttsTimer and tostring(reminder.ttsTimer) or "")
    editFields.countdown:SetText(reminder.countdown and tostring(reminder.countdown) or "")
    editFields.bossSpell:SetText(reminder.bossSpell and tostring(reminder.bossSpell) or "")
    editFields.colors:SetText(reminder.colors or "")
    editFields.abilitySpellId = reminder.spellID

    editPanel:LayoutForEdit()
    editPanel.deleteBtn:SetScript("OnClick", function()
        NotesEditor:DeleteFromPanel()
    end)
    editPanel.saveBtn:SetScript("OnClick", function()
        NotesEditor:SaveFromPanel()
    end)
end

function NotesEditor:SaveFromPanel()
    local timeVal = ParseTimeInput(editFields.time:GetText())
    if not timeVal then
        editPanel.errorText:SetText("Invalid time format. Use M:SS or seconds.")
        return
    end

    local phaseVal = tonumber(editFields.phase:GetText()) or 1
    local tag = editFields.who:GetText()
    if not tag or tag == "" then
        if state.mode == "annotate" then
            tag = UnitName("player") or "player"
        else
            editPanel.errorText:SetText("Who is required.")
            return
        end
    end

    local abilityName = editFields.abilityText or ""
    local abilitySpellId = editFields.abilitySpellId
    local displayText = editFields.displayText:GetText() or ""
    local combinedText
    if abilityName ~= "" and displayText ~= "" then
        combinedText = abilityName .. " " .. displayText
    elseif abilityName ~= "" then
        combinedText = abilityName
    elseif displayText ~= "" then
        combinedText = displayText
    else
        editPanel.errorText:SetText("Ability or text is required.")
        return
    end

    local durVal = tonumber(editFields.duration:GetText())
    local displayTypeVal = editFields.displayType:GetValue() or "Icon"
    local soundVal = NonEmpty(editFields.sound:GetText())
    local ttsVal = ParseTTSInput(editFields.tts:GetText())
    local ttsTimerVal = tonumber(editFields.ttsTimer:GetText())
    local countdownVal = tonumber(editFields.countdown:GetText())
    local bossSpellVal = tonumber(editFields.bossSpell:GetText())
    local colorsVal = NonEmpty(editFields.colors:GetText())

    if not state.parsedNote then
        state.parsedNote = {
            encounterID = tonumber(state.encounterName) or state.encounterName,
            name = state.encounterName,
            difficulty = state.difficulty,
            reminders = {},
            lines = {},
        }
    end

    local newReminder = {
        time = timeVal,
        tag = tag,
        text = combinedText,
        spellID = abilitySpellId,
        phase = phaseVal,
        phaseKey = tostring(phaseVal),
        duration = durVal or 5,
        displayType = displayTypeVal,
        tts = ttsVal,
        ttsTimer = ttsTimerVal,
        countdown = countdownVal,
        sound = soundVal,
        bossSpell = bossSpellVal,
        colors = colorsVal,
    }

    local note = state.parsedNote

    if state.editingReminder then
        RemoveReminderFromNote(note, state.editingReminder)
    end

    AppendReminderToNote(note, newReminder)

    if state.mode == "annotate" then
        newReminder.isPersonal = true
        AppendReminderToNote(EnsureAnnotationNote(), newReminder)
        self:SaveCurrentAnnotation()
    else
        self:SaveCurrentNote()
    end

    editPanel:Hide()
    state.editingReminder = nil
    self:Render()
end

function NotesEditor:SaveAnnotationFromPanel()
    if not state.editingReminder then
        return
    end

    local displayTypeVal = editFields.displayType:GetValue() or "Icon"
    local soundVal = NonEmpty(editFields.sound:GetText())
    local ttsVal = ParseTTSInput(editFields.tts:GetText())
    local countdownVal = tonumber(editFields.countdown:GetText())

    local annReminder = {
        time = state.editingReminder.time,
        tag = state.editingReminder.tag,
        text = state.editingReminder.text,
        phase = state.editingReminder.phase,
        phaseKey = state.editingReminder.phaseKey,
        duration = state.editingReminder.duration or 5,
        displayType = displayTypeVal,
        sound = soundVal,
        tts = ttsVal,
        countdown = countdownVal,
    }

    local annNote = EnsureAnnotationNote()
    local bucket = annNote.reminders[annReminder.phaseKey]

    local found = false
    if bucket then
        for i, existing in ipairs(bucket) do
            if existing.time == annReminder.time and existing.text == annReminder.text then
                bucket[i] = annReminder
                found = true
                break
            end
        end
    end
    if not found then
        AppendReminderToNote(annNote, annReminder)
    end

    local annText = PRT.NotesSerializer:Serialize(annNote)
    PRT.Notes:SaveAnnotation(state.noteName, annText)

    editPanel:Hide()
    state.editingReminder = nil
    self:ReloadNote()
    self:Render()
end

function NotesEditor:DeleteFromPanel()
    if not state.editingReminder then
        return
    end

    local reminder = state.editingReminder
    local note

    if state.mode == "annotate" and reminder.isPersonal then
        note = state.annotationNote
    else
        note = state.parsedNote
    end

    if not note then
        editPanel:Hide()
        state.editingReminder = nil
        return
    end

    RemoveReminderFromNote(note, reminder)

    if state.mode == "annotate" and reminder.isPersonal then
        self:SaveCurrentAnnotation()
    else
        self:SaveCurrentNote()
    end

    editPanel:Hide()
    state.editingReminder = nil
    self:ReloadNote()
    self:Render()
end

function NotesEditor:SaveCurrentNote()
    if not state.noteName then
        titleBar.nameText:Hide()
        titleBar.nameEdit:SetText("")
        titleBar.nameEdit:Show()
        titleBar.nameEdit:SetFocus()
        return
    end
    local text = PRT.NotesSerializer:Serialize(state.parsedNote)
    PRT.Notes:SaveNote(state.noteName, text)
    NotesEditor:NotifyConfigSaved(state.noteName)
end

function NotesEditor:SaveCurrentAnnotation()
    if not state.noteName then
        return
    end
    if not state.annotationNote then
        return
    end
    local text = PRT.NotesSerializer:Serialize(state.annotationNote)
    PRT.Notes:SaveAnnotation(state.noteName, text)
    NotesEditor:NotifyConfigSaved(state.noteName)
end

function NotesEditor:NotifyConfigSaved(savedName)
    if PRT.NotesConfig and PRT.NotesConfig._refreshAfterSave then
        PRT.NotesConfig._refreshAfterSave(savedName)
    end
end

function NotesEditor:ReloadNote()
    if not state.noteName then
        return
    end
    local settings = GetSettings()
    local noteText = settings and settings.savedNotes and settings.savedNotes[state.noteName]
    if not noteText then
        return
    end
    local parsed, err = PRT.NotesParser:Parse(noteText)
    if err then
        return
    end

    if state.mode == "annotate" then
        local annText = PRT.Notes:GetAnnotation(state.noteName)
        if annText then
            local annParsed = PRT.NotesParser:Parse(annText)
            if annParsed then
                state.annotationNote = annParsed
                parsed = PRT.NotesMerge:Merge(parsed, annParsed)
            end
        end
    end

    state.parsedNote = parsed
    state.encounterName = parsed.name or (parsed.encounterID and tostring(parsed.encounterID)) or ""
    state.difficulty = parsed.difficulty
end

function NotesEditor:Open(name, text, mode)
    BuildFrame()

    state = {
        noteName = name,
        encounterName = "",
        difficulty = nil,
        parsedNote = { encounterID = nil, reminders = {}, lines = {} },
        annotationNote = nil,
        mode = mode or "edit",
        activePhase = "all",
        rawMode = false,
        showOnlyMine = false,
        editingReminder = nil,
    }

    if name then
        local parsed, err = PRT.NotesParser:Parse(text or "")
        if not err and parsed then
            state.parsedNote = parsed
        end
        state.encounterName = state.parsedNote.name
            or (state.parsedNote.encounterID and tostring(state.parsedNote.encounterID))
            or ""
        state.difficulty = state.parsedNote.difficulty

        if state.mode == "annotate" then
            local annText = PRT.Notes:GetAnnotation(name)
            if annText then
                local annParsed = PRT.NotesParser:Parse(annText)
                if annParsed then
                    state.annotationNote = annParsed
                    state.parsedNote = PRT.NotesMerge:Merge(state.parsedNote, annParsed)
                end
            end
        end
    end

    modeBar.showMineCheck:SetChecked(false)

    if rawFrame then
        rawFrame:Hide()
    end
    timelineArea:Show()
    phaseTabs:Show()

    RestoreEditorPosition()
    frame:Show()
    self:Render()

    if not name then
        titleBar.nameText:Hide()
        titleBar.nameEdit:SetText("")
        titleBar.nameEdit:Show()
        titleBar.nameEdit:SetFocus()
    end
end

function NotesEditor:Close()
    if not frame then
        return
    end
    frame:Hide()
end

function NotesEditor:IsOpen()
    return frame ~= nil and frame:IsShown()
end
