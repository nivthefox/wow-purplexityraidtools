local PRT = PurplexityRaidTools
local NotesPlanner = PRT.NotesPlanner
local NotesEditor = {}
PRT.NotesEditor = NotesEditor

local VPPS = 8
local BLOCK_WIDTH = 95
local BLOCK_HEIGHT = 34
local BLOCK_GAP = 4
local RULER_WIDTH = 50
local EDIT_PANEL_WIDTH = 260
local DEFAULT_FRAME_WIDTH = 920
local DEFAULT_FRAME_HEIGHT = 550
local BOSS_CHANNEL_WIDTH = 210
local BOSS_ABILITY_HEIGHT = 30
local BOSS_CHANNEL_PADDING = 8
local GRID_INTERVAL = 30
local TICK_INTERVAL = 5
local TICK_LABEL_INTERVAL = 10
local TOP_PAD = 20

local DIFFICULTY_OPTIONS = NotesPlanner:GetDifficultyOptions()

local DISPLAY_TYPE_OPTIONS = {
    { name = "Icon (cooldown swipe)", value = "Icon" },
    { name = "Status Bar",           value = "Bar" },
    { name = "Text Overlay",         value = "Text" },
    { name = "Circle (swipe)",       value = "Circle" },
}

local TTS_MODE_OPTIONS = {
    { name = "Off",           value = "off" },
    { name = "Reminder Text", value = "reminder" },
    { name = "Custom Text",   value = "custom" },
}

local ALERT_FIELD_LAYOUTS = {
    edit = {
        "phase", "time", "who", "ability", "displayText", "duration",
        "bossSpell", "colors",
    },
    annotation = {
        "originalInfo", "displayType", "sound", "ttsMode", "ttsCustom",
        "audioLeadTime", "countdown",
    },
    personal = {
        "phase", "time", "ability", "displayText", "duration",
        "displayType", "sound", "ttsMode", "ttsCustom", "audioLeadTime",
        "countdown",
    },
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
local encounterNameCache
local requestedSpellIDs = {}

local function GetSettings()
    return PRT:GetSetting("notes")
end

local function CountKeys(values)
    local count = 0
    for _ in pairs(values) do
        count = count + 1
    end
    return count
end

local function LoadEncounterNames()
    if encounterNameCache then
        return encounterNameCache
    end

    encounterNameCache = {}
    local database = PRT.BossTimelineDatabase
    local encounters = database and database.encounters
    if type(encounters) ~= "table"
        or type(EJ_GetNumTiers) ~= "function"
        or type(EJ_SelectTier) ~= "function"
        or type(EJ_GetInstanceByIndex) ~= "function"
        or type(EJ_GetEncounterInfoByIndex) ~= "function"
    then
        return encounterNameCache
    end

    local targets = {}
    for encounterID in pairs(encounters) do
        targets[encounterID] = true
    end
    local remaining = CountKeys(targets)
    local selectedTier = type(EJ_GetCurrentTier) == "function" and EJ_GetCurrentTier()

    local ok = pcall(function()
        for tier = EJ_GetNumTiers(), 1, -1 do
            EJ_SelectTier(tier)
            local instanceIndex = 1
            while remaining > 0 do
                local journalInstanceID = EJ_GetInstanceByIndex(instanceIndex, true)
                if not journalInstanceID then
                    break
                end
                if type(EJ_SelectInstance) == "function" then
                    EJ_SelectInstance(journalInstanceID)
                end
                local encounterIndex = 1
                while remaining > 0 do
                    local name, _, _, _, _, _, dungeonEncounterID =
                        EJ_GetEncounterInfoByIndex(encounterIndex, journalInstanceID)
                    if not name then
                        break
                    end
                    if targets[dungeonEncounterID] and not encounterNameCache[dungeonEncounterID] then
                        encounterNameCache[dungeonEncounterID] = name
                        remaining = remaining - 1
                    end
                    encounterIndex = encounterIndex + 1
                end
                instanceIndex = instanceIndex + 1
            end
            if remaining == 0 then
                break
            end
        end
    end)

    if selectedTier and type(EJ_SelectTier) == "function" then
        pcall(EJ_SelectTier, selectedTier)
    end
    if not ok then
        encounterNameCache = {}
    end
    return encounterNameCache
end

local function GetEncounterChoices()
    local names = LoadEncounterNames()
    local currentEncounterID = state.parsedNote and state.parsedNote.encounterID
    return NotesPlanner:BuildEncounterChoices(
        PRT.BossTimelineDatabase,
        currentEncounterID,
        function(encounterID)
            return names[encounterID]
        end
    )
end

local function FindEncounterChoice(encounterID)
    for _, choice in ipairs(GetEncounterChoices()) do
        if choice.value == encounterID then
            return choice
        end
    end
end

local function IsContextLocked()
    return NotesPlanner:IsContextLocked(
        state.mode,
        state.parsedNote,
        state.contextAnnotationNote
    )
end

local function RequestSpellData(spellID)
    if not requestedSpellIDs[spellID]
        and C_Spell
        and C_Spell.RequestLoadSpellData
    then
        requestedSpellIDs[spellID] = true
        C_Spell.RequestLoadSpellData(spellID)
    end
end

local function ResolveSpellIcon(spellID)
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    if not icon then
        RequestSpellData(spellID)
    end
    return icon
end

local function ResolveBossSpell(spellID)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    local icon = ResolveSpellIcon(spellID)
    if not name then
        RequestSpellData(spellID)
    end
    return name, icon
end

function NotesEditor.FormatSpellLabel(name, spellID, size)
    if not name or name == "" or not spellID then
        return name or ""
    end

    local icon = ResolveSpellIcon(spellID)
    if not icon then
        return name
    end

    local iconSize = size or 14
    return "|T" .. icon .. ":" .. iconSize .. ":" .. iconSize .. "|t " .. name
end

local function NonEmpty(text)
    if text == "" then
        return nil
    end
    return text
end

function NotesEditor.GetTTSFormState(tts)
    if tts == nil or tts == false then
        return "off", ""
    end
    if tts == true then
        return "reminder", ""
    end
    return "custom", tostring(tts)
end

function NotesEditor.BuildTTSValue(mode, customText)
    if mode == "off" then
        return nil
    end
    if mode == "reminder" then
        return true
    end
    if mode ~= "custom" then
        return nil, "Invalid TTS mode."
    end
    if not customText or customText == "" then
        return nil, "Custom TTS text is required."
    end
    return customText
end

local function ParseWholeSeconds(raw, label, minimum, maximum)
    if raw == nil or raw == "" then
        return nil
    end

    local value = tonumber(raw)
    if not value or value ~= math.floor(value) then
        return nil, label .. " must be a whole number of seconds."
    end
    if minimum and value < minimum then
        if minimum == 0 then
            return nil, label .. " cannot be negative."
        end
        return nil, label .. " must be at least " .. minimum .. " second."
    end
    if maximum and value > maximum then
        return nil, label .. " must be between " .. minimum .. " and " .. maximum .. " seconds."
    end
    return value
end

function NotesEditor.ParseAlertTiming(durationText, audioLeadTimeText, countdownText)
    local duration, err = ParseWholeSeconds(durationText, "Duration", 1)
    if err then
        return nil, err
    end

    local audioLeadTime
    audioLeadTime, err = ParseWholeSeconds(audioLeadTimeText, "Audio Lead Time", 0)
    if err then
        return nil, err
    end

    local countdown
    countdown, err = ParseWholeSeconds(countdownText, "Countdown", 1, 10)
    if err then
        return nil, err
    end

    return {
        duration = duration or 5,
        audioLeadTime = audioLeadTime,
        countdown = countdown,
    }
end

function NotesEditor.BuildAnnotationReminder(source, values)
    return {
        time = source.time,
        tag = source.tag,
        text = source.text,
        phase = source.phase,
        phaseKey = source.phaseKey,
        duration = source.duration or 5,
        displayType = values.displayType,
        sound = values.sound,
        tts = values.tts,
        ttsTimer = values.audioLeadTime,
        countdown = values.countdown,
    }
end

function NotesEditor.GetAlertFieldKeys(layout)
    local keys = ALERT_FIELD_LAYOUTS[layout] or {}
    local result = {}
    for i, key in ipairs(keys) do
        result[i] = key
    end
    return result
end

function NotesEditor.BuildSoundOptions(soundNames, currentValue)
    local options = { { name = "None", value = "" } }
    local seen = { none = true }

    for _, name in ipairs(soundNames or {}) do
        if type(name) == "string" and name ~= "" then
            local key = name:lower()
            if not seen[key] then
                seen[key] = true
                options[#options + 1] = { name = name, value = name }
            end
        end
    end

    table.sort(options, function(a, b)
        if a.value == "" then
            return true
        end
        if b.value == "" then
            return false
        end
        return a.name:lower() < b.name:lower()
    end)

    if currentValue and currentValue ~= "" and not seen[currentValue:lower()] then
        options[#options + 1] = {
            name = currentValue .. " (current)",
            value = currentValue,
        }
    end

    return options
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

-- GroupInspect stores a placeholder without a realm until both the unit name and
-- the local realm resolve (Modules/GroupInspect.lua PlaceholderName); a
-- placeholder identifies nobody, so it must never answer to a tag.
local function ResolvedShortName(name)
    if not name or not name:match("^[^%-]+%-.+$") then
        return nil
    end
    return Ambiguate(name, "short")
end

local function ResolvedBareName(name)
    local shortName = ResolvedShortName(name)
    return shortName and shortName:lower()
end

-- Ordering by full name and then GUID is a total order, so a bare name shared by
-- two members resolves to the same one however pairs happens to hand them over.
local function OutranksBest(name, guid, bestName, bestGuid)
    if not bestName then
        return true
    end
    if name ~= bestName then
        return name < bestName
    end
    return guid < bestGuid
end

function NotesEditor.FindMemberByTag(members, tag)
    if not members or not tag or tag == "" then
        return nil
    end

    local lowerTag = tag:lower()
    local bestGuid, bestMember
    for guid, member in pairs(members) do
        if ResolvedBareName(member.name) == lowerTag
                and OutranksBest(member.name, guid, bestMember and bestMember.name, bestGuid) then
            bestGuid, bestMember = guid, member
        end
    end

    return bestGuid, bestMember
end

local function AddTargetOption(optionsByTag, character, specId, classToken)
    local shortName = ResolvedShortName(character)
    if not shortName then
        return
    end

    local key = shortName:lower()
    local current = optionsByTag[key]
    if current and current.character <= character then
        return
    end

    optionsByTag[key] = {
        name = shortName,
        value = shortName,
        character = character,
        specId = specId,
        class = classToken,
    }
end

function NotesEditor.BuildTargetOptions(isGrouped, groupMembers, rosterEntries)
    local optionsByTag = {}

    if isGrouped then
        for _, member in pairs(groupMembers or {}) do
            AddTargetOption(optionsByTag, member.name, member.specId, member.class)
        end
    else
        for _, entry in ipairs(rosterEntries or {}) do
            for _, character in ipairs(entry.characters or {}) do
                local characterData = entry.characterData and entry.characterData[character]
                if characterData and characterData.mainSpec then
                    AddTargetOption(
                        optionsByTag,
                        character,
                        characterData.mainSpec,
                        characterData.class
                    )
                end
            end
        end
    end

    local options = {}
    for _, option in pairs(optionsByTag) do
        options[#options + 1] = option
    end
    table.sort(options, function(a, b)
        local aName = a.name:lower()
        local bName = b.name:lower()
        if aName ~= bName then
            return aName < bName
        end
        return a.character < b.character
    end)
    return options
end

local function GetTargetOptions()
    if IsInGroup() then
        return NotesEditor.BuildTargetOptions(
            true,
            PRT.GroupInspect and PRT.GroupInspect.members,
            nil
        )
    end

    local entries
    if PRT.Roster and PRT.Roster.GetEntries then
        entries = PRT.Roster:GetEntries()
    end
    return NotesEditor.BuildTargetOptions(false, nil, entries)
end

local function FindTargetOption(tag)
    if not tag or tag == "" then
        return nil
    end

    local lowerTag = tag:lower()
    for _, option in ipairs(GetTargetOptions()) do
        if option.value:lower() == lowerTag then
            return option
        end
    end
    return nil
end

function NotesEditor.GetClassColorForTag(tag)
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

    local target = FindTargetOption(tag)
    if target then
        local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[target.class]
        if color then
            return color.r, color.g, color.b
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

function NotesEditor.GetAbilitiesForTag(tag)
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

    local target = FindTargetOption(tag)
    if target and target.specId then
        local specData = PRT.SpellData[target.specId]
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

local function RefreshPlanningModel()
    state.planningModel = nil
    local encounterID = state.parsedNote and tonumber(state.parsedNote.encounterID)
    if not encounterID or not PRT.EncounterPhases then
        return
    end
    local difficultyID = NotesPlanner:GetDifficultyID(state.difficulty)
    state.planningModel = PRT.EncounterPhases:GetPlanningModel(encounterID, difficultyID)
end

local function DerivePhases(parsedNote)
    return NotesPlanner:BuildPhases(parsedNote, state.planningModel)
end

local function TimeToY(time, phaseNum, phases, activePhase)
    return NotesPlanner:TimeToY(time, phaseNum, phases, activePhase, VPPS, TOP_PAD)
end

local function YToTimeAndPhase(y, phases, activePhase)
    return NotesPlanner:YToTimeAndPhase(y, phases, activePhase, VPPS, TOP_PAD)
end

local function TotalDuration(phases, activePhase)
    return NotesPlanner:TotalDuration(phases, activePhase)
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

function NotesEditor.FindAbilitySpellID(text, knownAbilities)
    local abilityName = SplitAbilityAndText(text, knownAbilities)
    for _, ability in ipairs(knownAbilities or {}) do
        if ability.name == abilityName then
            return ability.spellId
        end
    end
    return nil
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

local titleBar, modeBar, phaseTabs, bossHeading, timelineArea, editPanel
local rulerFrame, bodyScroll, canvas, assignmentCanvas, bossChannel
local cursorOverlay, cursorLine, cursorLabel
local blockPool = {}
local bossAbilityPool = {}
local gridPool = {}
local bossGridPool = {}
local tickPool = {}
local phaseTabPool = {}
local phaseDividerPool = {}
local bossDividerPool = {}
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

local function CreateBossAbility(parent)
    local ability = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ability:SetHeight(BOSS_ABILITY_HEIGHT)
    ability:SetBackdrop(BACKDROP_INFO)
    ability:SetBackdropColor(0.12, 0.1, 0.18, 0.96)
    ability:SetBackdropBorderColor(0.5, 0.4, 0.75, 0.8)
    ability:EnableMouse(true)
    ability:SetScript("OnEnter", function(self)
        if not self.abilityName or not GameTooltip then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local spellDataAvailable = not self.abilityName:match("^Unknown Spell %(")
        if self.spellID and spellDataAvailable and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(self.spellID)
        else
            GameTooltip:SetText(self.abilityName, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    ability:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    ability.icon = ability:CreateTexture(nil, "ARTWORK")
    ability.icon:SetSize(22, 22)
    ability.icon:SetPoint("LEFT", 4, 0)

    ability.name = ability:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    ability.name:SetPoint("LEFT", ability.icon, "RIGHT", 5, 0)
    ability.name:SetPoint("RIGHT", -4, 0)
    ability.name:SetJustifyH("LEFT")
    ability.name:SetWordWrap(false)
    ability.name:SetTextColor(0.85, 0.82, 0.95)

    return ability
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
    holder.label:SetPoint("BOTTOMLEFT", holder.line, "TOPLEFT", 4, 2)
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

local function CreateTargetPicker(parent, getItems, getTextColor, onTextChanged)
    local picker = CreateFrame("Frame", nil, parent)
    picker:SetHeight(22)

    local input = CreateFieldInput(picker)
    input:SetPoint("TOPLEFT")
    input:SetPoint("BOTTOMRIGHT", -28, 0)
    input:SetScript("OnTextChanged", function(self)
        local r, g, b = getTextColor(self:GetText())
        self:SetTextColor(r, g, b)
        onTextChanged(self:GetText())
    end)

    local dropdown = CreateFrame("DropdownButton", nil, picker, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(24)
    dropdown:SetPoint("TOPRIGHT")
    dropdown:SetPoint("BOTTOMRIGHT")
    dropdown:SetupMenu(function(_, rootDescription)
        local currentValue = input:GetText():lower()
        for _, item in ipairs(getItems()) do
            local itemName = item.name
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[item.class]
            if color then
                itemName = color:WrapTextInColorCode(itemName)
            end
            rootDescription:CreateRadio(
                itemName,
                function() return currentValue == item.value:lower() end,
                function() input:SetText(item.value) end
            )
        end
    end)

    function picker:SetText(value)
        input:SetText(value or "")
    end

    function picker:GetText()
        return input:GetText()
    end

    function picker:Enable()
        input:Enable()
        dropdown:SetEnabled(true)
    end

    function picker:Disable()
        input:Disable()
        dropdown:SetEnabled(false)
    end

    return picker
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

local function GetRegisteredSoundNames()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not lsm then
        return {}
    end
    return lsm:List("sound") or {}
end

local function CreateSoundPicker(parent)
    local picker = CreateFrame("Frame", nil, parent)
    picker:SetHeight(22)
    picker.currentValue = ""

    local button = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT")
    button:SetPoint("BOTTOMRIGHT", -26, 0)
    button:SetText("None")

    local selectedPreview = CreateFrame("Button", nil, picker)
    selectedPreview:SetSize(22, 22)
    selectedPreview:SetPoint("RIGHT")
    selectedPreview:SetNormalAtlas("common-icon-sound")
    selectedPreview:SetPushedAtlas("common-icon-sound-pressed")

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(260, 220)
    popup:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", 0, -2)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetBackdrop(BACKDROP_INFO)
    popup:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
    popup:SetBackdropBorderColor(0.35, 0.35, 0.4, 1)
    popup:Hide()

    local search = CreateFrame("EditBox", nil, popup, "SearchBoxTemplate")
    search:SetHeight(22)
    search:SetAutoFocus(false)
    search:SetPoint("TOPLEFT", 8, -8)
    search:SetPoint("TOPRIGHT", -8, -8)

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -36)
    scroll:SetPoint("BOTTOMRIGHT", -26, 8)

    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetWidth(218)
    scrollChild:SetHeight(1)
    scroll:SetScrollChild(scrollChild)

    local rows = {}

    local function Preview(value)
        if value == "" then
            return
        end
        if PRT.NotesPopups and PRT.NotesPopups.PreviewSound then
            PRT.NotesPopups:PreviewSound(value)
        end
    end

    local function AcquireRow(index)
        if rows[index] then
            return rows[index]
        end

        local row = CreateFrame("Button", nil, scrollChild)
        row:SetHeight(22)
        row:SetPoint("TOPLEFT", 0, -((index - 1) * 22))
        row:SetPoint("TOPRIGHT")

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.label:SetPoint("LEFT", 4, 0)
        row.label:SetPoint("RIGHT", -26, 0)
        row.label:SetJustifyH("LEFT")

        row.preview = CreateFrame("Button", nil, row)
        row.preview:SetSize(18, 18)
        row.preview:SetPoint("RIGHT", -2, 0)
        row.preview:SetNormalAtlas("common-icon-sound")
        row.preview:SetPushedAtlas("common-icon-sound-pressed")

        rows[index] = row
        return row
    end

    local function RefreshRows()
        local query = search:GetText():lower()
        local options = NotesEditor.BuildSoundOptions(
            GetRegisteredSoundNames(),
            picker.currentValue
        )
        local shown = 0

        for _, item in ipairs(options) do
            if query == "" or item.name:lower():find(query, 1, true) then
                shown = shown + 1
                local row = AcquireRow(shown)
                local itemValue = item.value
                row.value = itemValue
                row.label:SetText(item.name)
                row:SetScript("OnClick", function()
                    picker:SetValue(itemValue)
                    popup:Hide()
                end)
                row.preview:SetShown(itemValue ~= "")
                row.preview:SetScript("OnClick", function()
                    Preview(itemValue)
                end)
                row:Show()
            end
        end

        for i = shown + 1, #rows do
            rows[i]:Hide()
        end
        scrollChild:SetHeight(math.max(1, shown * 22))
    end

    search:SetScript("OnTextChanged", RefreshRows)
    search:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        popup:Hide()
    end)

    button:SetScript("OnClick", function()
        if popup:IsShown() then
            popup:Hide()
            return
        end
        search:SetText("")
        RefreshRows()
        popup:Show()
        search:SetFocus()
    end)

    selectedPreview:SetScript("OnClick", function()
        Preview(picker.currentValue)
    end)

    function picker:SetValue(value)
        self.currentValue = value or ""
        if self.currentValue == "" then
            button:SetText("None")
        else
            button:SetText(self.currentValue)
        end
        selectedPreview:SetEnabled(self.currentValue ~= "")
    end

    function picker:GetValue()
        return self.currentValue ~= "" and self.currentValue or nil
    end

    function picker:ClosePopup()
        popup:Hide()
    end

    picker:SetScript("OnHide", function()
        popup:Hide()
    end)
    picker:SetValue("")

    return picker
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
        if editFields.sound and editFields.sound.ClosePopup then
            editFields.sound:ClosePopup()
        end
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

    local function AddTargetPicker(getItems, getTextColor, onTextChanged)
        local picker = CreateTargetPicker(scrollChild, getItems, getTextColor, onTextChanged)
        picker:SetPoint("TOPLEFT", 4, yOff)
        picker:SetWidth(fieldWidth)
        yOff = yOff - 28
        return picker
    end

    local function AddSoundPicker()
        local picker = CreateSoundPicker(scrollChild)
        picker:SetPoint("TOPLEFT", 4, yOff)
        picker:SetWidth(fieldWidth)
        yOff = yOff - 28
        return picker
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
    editFields.who = AddTargetPicker(GetTargetOptions, NotesEditor.GetClassColorForTag, function(tag)
        local abilities = NotesEditor.GetAbilitiesForTag(tag)
        currentAbilities = abilities
        editFields.ability:GenerateMenu()
    end)

    editFields.abilityLabel = AddLabel("ABILITY")
    editFields.ability = AddDropdown(
        function()
            local items = { { name = "(free text)", value = "" } }
            for _, ab in ipairs(currentAbilities) do
                items[#items + 1] = {
                    name = NotesEditor.FormatSpellLabel(ab.name, ab.spellId, 16),
                    value = ab.name,
                }
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

    editFields.durationLabel = AddLabel("DURATION (SECONDS)")
    editFields.duration = AddInput()
    editFields.duration:SetNumeric(true)

    editFields.displayTypeLabel = AddLabel("DISPLAY TYPE")
    editFields.displayType = AddDropdown(
        function() return DISPLAY_TYPE_OPTIONS end,
        function() end
    )

    editFields.soundLabel = AddLabel("SOUND")
    editFields.sound = AddSoundPicker()

    editFields.ttsLabel = AddLabel("TTS")
    editFields.ttsMode = AddDropdown(
        function() return TTS_MODE_OPTIONS end,
        function()
            if editPanel and editPanel.RefreshLayout then
                editPanel:RefreshLayout()
            end
        end
    )

    editFields.ttsCustomLabel = AddLabel("CUSTOM TTS TEXT")
    editFields.ttsCustom = AddInput()

    editFields.audioLeadTimeLabel = AddLabel("AUDIO LEAD TIME (SECONDS)")
    editFields.audioLeadTime = AddInput()
    editFields.audioLeadTime:SetNumeric(true)

    editFields.countdownLabel = AddLabel("COUNTDOWN (BLANK = OFF)")
    editFields.countdown = AddInput()
    editFields.countdown:SetNumeric(true)

    editFields.bossSpellLabel = AddLabel("BOSS SPELL ID")
    editFields.bossSpell = AddInput()
    editFields.bossSpell:SetNumeric(true)

    editFields.colorsLabel = AddLabel("COLORS")
    editFields.colors = AddInput()

    local allFields = {
        { key = "originalInfo", label = panel.originalInfoLabel, field = panel.originalInfo, fieldHeight = 32 },
        { key = "phase", label = editFields.phaseLabel, field = editFields.phase },
        { key = "time", label = editFields.timeLabel, field = editFields.time },
        { key = "who", label = editFields.whoLabel, field = editFields.who },
        { key = "ability", label = editFields.abilityLabel, field = editFields.ability },
        { key = "displayText", label = editFields.displayTextLabel, field = editFields.displayText },
        { key = "duration", label = editFields.durationLabel, field = editFields.duration },
        { key = "displayType", label = editFields.displayTypeLabel, field = editFields.displayType },
        { key = "sound", label = editFields.soundLabel, field = editFields.sound },
        { key = "ttsMode", label = editFields.ttsLabel, field = editFields.ttsMode },
        { key = "ttsCustom", label = editFields.ttsCustomLabel, field = editFields.ttsCustom },
        { key = "audioLeadTime", label = editFields.audioLeadTimeLabel, field = editFields.audioLeadTime },
        { key = "countdown", label = editFields.countdownLabel, field = editFields.countdown },
        { key = "bossSpell", label = editFields.bossSpellLabel, field = editFields.bossSpell },
        { key = "colors", label = editFields.colorsLabel, field = editFields.colors },
    }

    local function layoutFields(layout)
        local lookup = {}
        for _, key in ipairs(NotesEditor.GetAlertFieldKeys(layout)) do
            lookup[key] = true
        end
        if editFields.ttsMode:GetValue() ~= "custom" then
            lookup.ttsCustom = nil
        end

        local y = 0
        for _, row in ipairs(allFields) do
            if lookup[row.key] then
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

    function panel:RefreshLayout()
        if self.currentLayout then
            layoutFields(self.currentLayout)
        end
    end

    function panel:LayoutForEdit()
        self.currentLayout = "edit"
        self:RefreshLayout()
    end

    function panel:LayoutForAnnotate()
        self.currentLayout = "annotation"
        self:RefreshLayout()
    end

    function panel:LayoutForPersonal()
        self.currentLayout = "personal"
        self:RefreshLayout()
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

    titleBar.encounterDropdown = CreateFieldDropdown(titleBar,
        GetEncounterChoices,
        function(value)
            if IsContextLocked() or not state.parsedNote then
                return
            end
            local choice = FindEncounterChoice(value)
            if not choice then
                return
            end
            state.parsedNote.encounterID = value
            state.parsedNote.name = choice.encounterName
            state.encounterName = choice.encounterName
            NotesEditor:SaveCurrentNote()
            NotesEditor:Render()
        end
    )
    titleBar.encounterDropdown:SetSize(210, 20)

    titleBar.difficultyDropdown = CreateFieldDropdown(titleBar,
        function() return DIFFICULTY_OPTIONS end,
        function(value)
            if IsContextLocked() then
                return
            end
            if state.parsedNote then
                state.parsedNote.difficulty = value
            end
            state.difficulty = value
            NotesEditor:SaveCurrentNote()
            NotesEditor:Render()
        end
    )
    titleBar.difficultyDropdown:SetSize(100, 20)
    titleBar.difficultyDropdown:SetPoint("RIGHT", -4, 0)
    titleBar.encounterDropdown:SetPoint("RIGHT", titleBar.difficultyDropdown, "LEFT", -12, 0)

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

    bossHeading = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    bossHeading:SetSize(BOSS_CHANNEL_WIDTH, 24)
    bossHeading:SetPoint("TOPRIGHT", modeBar, "BOTTOMRIGHT", -24, -2)
    bossHeading:SetBackdrop(BACKDROP_INFO)
    bossHeading:SetBackdropColor(0.08, 0.07, 0.12, 0.9)
    bossHeading:SetBackdropBorderColor(0.5, 0.4, 0.75, 0.7)
    bossHeading.text = bossHeading:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossHeading.text:SetPoint("CENTER")
    bossHeading.text:SetText("Boss Abilities")
    bossHeading.text:SetTextColor(0.85, 0.8, 1)

    phaseTabs:SetPoint("TOPRIGHT", bossHeading, "TOPLEFT", 0, 0)

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
    canvas:SetSize(620, 2000)
    bodyScroll:SetScrollChild(canvas)

    bossChannel = CreateFrame("Frame", nil, canvas, "BackdropTemplate")
    bossChannel:SetWidth(BOSS_CHANNEL_WIDTH)
    bossChannel:SetPoint("TOPRIGHT")
    bossChannel:SetPoint("BOTTOMRIGHT")
    bossChannel:SetBackdrop(BACKDROP_INFO)
    bossChannel:SetBackdropColor(0.05, 0.045, 0.08, 0.96)
    bossChannel:SetBackdropBorderColor(0.5, 0.4, 0.75, 0.7)

    bossChannel.unavailable = bossChannel:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontDisableSmall"
    )
    bossChannel.unavailable:SetPoint("TOPLEFT", 12, -16)
    bossChannel.unavailable:SetPoint("RIGHT", -12, 0)
    bossChannel.unavailable:SetJustifyH("CENTER")
    bossChannel.unavailable:SetWordWrap(true)

    assignmentCanvas = CreateFrame("Frame", nil, canvas)
    assignmentCanvas:SetPoint("TOPLEFT")
    assignmentCanvas:SetPoint("BOTTOMLEFT")
    assignmentCanvas:SetPoint("RIGHT", bossChannel, "LEFT")
    assignmentCanvas:EnableMouse(true)
    assignmentCanvas:SetScript("OnMouseDown", function(self, button)
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

    cursorOverlay = CreateFrame("Frame", nil, canvas)
    cursorOverlay:SetAllPoints()
    cursorOverlay:SetFrameLevel(canvas:GetFrameLevel() + 20)
    cursorOverlay:EnableMouse(false)

    cursorLine = cursorOverlay:CreateTexture(nil, "OVERLAY")
    cursorLine:SetHeight(1)
    cursorLine:SetColorTexture(0.94, 0.75, 0.25, 0.8)
    cursorLine:Hide()

    cursorLabel = cursorOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
        cursorLine:ClearAllPoints()
        cursorLine:SetPoint("TOPLEFT", cursorOverlay, "TOPLEFT", 0, -y)
        cursorLine:SetPoint("TOPRIGHT", cursorOverlay, "TOPRIGHT", 0, -y)
        cursorLabel:ClearAllPoints()
        cursorLabel:SetPoint("TOPLEFT", cursorOverlay, "TOPLEFT", 4, -(y + 2))
        cursorLabel:SetText(FormatTime(time))
    end)

    local spellEventFrame = CreateFrame("Frame", nil, frame)
    spellEventFrame:RegisterEvent("SPELL_DATA_LOAD_RESULT")
    spellEventFrame:SetScript("OnEvent", function(_, _, spellID, success)
        if not success or not requestedSpellIDs[spellID] then
            return
        end
        requestedSpellIDs[spellID] = nil
        if frame:IsShown() then
            NotesEditor:Render()
        end
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
    if state.activePhase ~= "all" then
        local activeExists = false
        for _, phase in ipairs(phases) do
            if phase.num == state.activePhase then
                activeExists = true
                break
            end
        end
        if not activeExists then
            state.activePhase = "all"
        end
    end
    if #phases <= 1 then
        return
    end

    local xOff = 4

    local allTab = GetFromPool(phaseTabPool, function()
        return CreatePhaseTab(phaseTabs)
    end)
    allTab:SetWidth(80)
    allTab:SetPoint("TOPLEFT", xOff, -1)
    allTab.text:SetText(NotesPlanner:FormatPhaseTabLabel())
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

    for phaseIndex, phase in ipairs(phases) do
        local tab = GetFromPool(phaseTabPool, function()
            return CreatePhaseTab(phaseTabs)
        end)
        tab:SetWidth(80)
        tab:SetPoint("TOPLEFT", xOff, -1)
        tab.text:SetText(NotesPlanner:FormatPhaseTabLabel(phaseIndex))
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
    RecyclePool(bossAbilityPool)
    RecyclePool(gridPool)
    RecyclePool(bossGridPool)
    RecyclePool(tickPool)
    RecyclePool(phaseDividerPool)
    RecyclePool(bossDividerPool)
    RecyclePool(freeformPool)

    local phases = DerivePhases(state.parsedNote)
    local totalDur = TotalDuration(phases, state.activePhase)
    local canvasHeight = totalDur * VPPS + TOP_PAD + 20
    canvas:SetHeight(canvasHeight)
    canvas:SetWidth(math.max(BOSS_CHANNEL_WIDTH + 1, bodyScroll:GetWidth()))
    bodyScroll:UpdateScrollChildRect()

    for t = GRID_INTERVAL, totalDur, GRID_INTERVAL do
        local y = t * VPPS + TOP_PAD
        local line = GetFromPool(gridPool, function()
            return CreateGridLine(assignmentCanvas)
        end)
        line:SetPoint("TOPLEFT", assignmentCanvas, "TOPLEFT", 0, -y)
        line:SetPoint("TOPRIGHT", assignmentCanvas, "TOPRIGHT", 0, -y)
        line:Show()

        local bossLine = GetFromPool(bossGridPool, function()
            return CreateGridLine(bossChannel)
        end)
        bossLine:SetPoint("TOPLEFT", bossChannel, "TOPLEFT", 0, -y)
        bossLine:SetPoint("TOPRIGHT", bossChannel, "TOPRIGHT", 0, -y)
        bossLine:Show()
    end

    local function PlacePhaseDivider(phase, y)
        local divider = GetFromPool(phaseDividerPool, function()
            return CreatePhaseDivider(assignmentCanvas)
        end)
        divider:SetPoint("TOPLEFT", assignmentCanvas, "TOPLEFT", 0, -y)
        divider:SetPoint("TOPRIGHT", assignmentCanvas, "TOPRIGHT", 0, -y)
        divider.label:SetText(phase.name)
        divider:Show()

        local bossDivider = GetFromPool(bossDividerPool, function()
            return CreatePhaseDivider(bossChannel)
        end)
        bossDivider:SetPoint("TOPLEFT", bossChannel, "TOPLEFT", 0, -y)
        bossDivider:SetPoint("TOPRIGHT", bossChannel, "TOPRIGHT", 0, -y)
        bossDivider.label:SetText("")
        bossDivider:Show()
    end

    if state.activePhase == "all" then
        for _, phase in ipairs(phases) do
            PlacePhaseDivider(phase, phase.start * VPPS + TOP_PAD)
        end
    else
        for _, phase in ipairs(phases) do
            if phase.num == state.activePhase then
                PlacePhaseDivider(phase, TOP_PAD)
                break
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
        local dur = phase and phase.duration or NotesPlanner.PHASE_PAD
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
            return CreateFreeformSeparator(assignmentCanvas)
        end)
        sep:SetPoint("TOPLEFT", assignmentCanvas, "TOPLEFT", 0, -y)
        sep:SetPoint("RIGHT", assignmentCanvas, "RIGHT", 0, 0)
        sep:SetFrameLevel(assignmentCanvas:GetFrameLevel() + 3)

        sep.line:SetColorTexture(0.4, 0.7, 1, 0.5)
        sep.label:SetTextColor(0.4, 0.7, 1, 0.8)

        sep.label:SetText(fl.text)
        sep:Show()
    end

    local unavailableMessage = NotesPlanner:GetUnavailableMessage(state.planningModel)
    bossChannel.unavailable:SetText(unavailableMessage or "")
    if unavailableMessage then
        bossChannel.unavailable:Show()
    else
        bossChannel.unavailable:Hide()
    end

    local abilities = NotesPlanner:BuildAbilityEntries(
        state.planningModel,
        phases,
        state.activePhase,
        ResolveBossSpell,
        {
            scale = VPPS,
            topPad = TOP_PAD,
            height = BOSS_ABILITY_HEIGHT,
            gap = BLOCK_GAP,
        }
    )
    for _, ability in ipairs(abilities) do
        local block = GetFromPool(bossAbilityPool, function()
            return CreateBossAbility(bossChannel)
        end)
        local columns = math.max(1, ability.columnCount)
        local availableWidth = BOSS_CHANNEL_WIDTH - (BOSS_CHANNEL_PADDING * 2)
        local width = (
            availableWidth - ((columns - 1) * BLOCK_GAP)
        ) / columns
        local x = BOSS_CHANNEL_PADDING + ability.column * (width + BLOCK_GAP)

        block:SetWidth(math.max(1, width))
        block:SetPoint("TOPLEFT", bossChannel, "TOPLEFT", x, -ability.y)
        block:SetFrameLevel(bossChannel:GetFrameLevel() + 5)
        block.icon:SetTexture(ability.icon)
        block.name:SetText(ability.name)
        block.abilityName = ability.name
        block.spellID = ability.spellID
        block:Show()
    end
end

function NotesEditor:RenderBlock(reminder, y, stackIdx, height, phases, playerCtx)
    local block = GetFromPool(blockPool, function()
        return CreateBlock(assignmentCanvas)
    end)

    block:SetPoint(
        "TOPLEFT",
        assignmentCanvas,
        "TOPLEFT",
        stackIdx * (BLOCK_WIDTH + BLOCK_GAP),
        -y
    )
    block:SetHeight(height)
    block:SetFrameLevel(assignmentCanvas:GetFrameLevel() + 5)

    local r, g, b = NotesEditor.GetClassColorForTag(reminder.tag)
    block.who:SetText(reminder.tag or "")
    block.who:SetTextColor(r, g, b)

    local abilityText = reminder.text or ""
    local abilitySpellID = reminder.spellID
        or NotesEditor.FindAbilitySpellID(
            abilityText,
            NotesEditor.GetAbilitiesForTag(reminder.tag)
        )
    block.ability:SetText(NotesEditor.FormatSpellLabel(abilityText, abilitySpellID, 14))

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

    RefreshPlanningModel()
    local modeState = NotesPlanner:GetEditorModeState(state.mode, IsContextLocked())
    NotesPlanner:ApplyEditorModeState(modeState, {
        showOnlyMine = modeBar.showMineCheck,
        showOnlyMineLabel = modeBar.showMineLabel,
        annotate = modeBar.annotateBtn,
        import = modeBar.rawBtn,
        boss = bossChannel,
        encounter = titleBar.encounterDropdown,
        difficulty = titleBar.difficultyDropdown,
    })
    if state.mode == "annotate" then
        frame:SetTitle("Annotate Note")
    else
        frame:SetTitle("Edit Note")
    end

    titleBar.nameText:SetText(state.noteName or "New Note")
    titleBar.encounterDropdown:SetValue(
        state.parsedNote and state.parsedNote.encounterID
    )
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

local function LoadAnnotationNote(noteName)
    if not noteName then
        return nil
    end
    local text = PRT.Notes:GetAnnotation(noteName)
    if not text then
        return nil
    end
    local parsed = PRT.NotesParser:Parse(text)
    return parsed
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

    local contextValid, contextError = NotesPlanner:ValidateImportedContext(
        state.parsedNote,
        state.contextAnnotationNote,
        parsed,
        state.mode
    )
    if not contextValid then
        rawFrame.errorText:SetText(contextError or "")
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
        state.contextAnnotationNote = state.annotationNote
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

local function SameStoredReminder(a, b)
    return a.phaseKey == b.phaseKey
        and a.time == b.time
        and a.tag == b.tag
        and a.text == b.text
end

function NotesEditor.ReplaceAnnotationReminder(note, source, replacement)
    if not note or not source then
        return false
    end

    local bucket = note.reminders[source.phaseKey]
    local stored
    local storedIndex
    for i, reminder in ipairs(bucket or {}) do
        if SameStoredReminder(reminder, source) then
            stored = reminder
            storedIndex = i
            break
        end
    end
    if not stored then
        return false
    end

    table.remove(bucket, storedIndex)
    if #bucket == 0 then
        note.reminders[source.phaseKey] = nil
    end

    if replacement then
        local replacementBucket = note.reminders[replacement.phaseKey]
        if not replacementBucket then
            replacementBucket = {}
            note.reminders[replacement.phaseKey] = replacementBucket
        end
        replacementBucket[#replacementBucket + 1] = replacement
        SortRemindersByTime(replacementBucket)
    end

    for i, entry in ipairs(note.lines) do
        if entry.type == "reminder" and entry.reminder == stored then
            if replacement then
                entry.reminder = replacement
            else
                table.remove(note.lines, i)
            end
            break
        end
    end
    return true
end

local function SetTTSFields(tts)
    local mode, customText = NotesEditor.GetTTSFormState(tts)
    editFields.ttsMode:SetValue(mode)
    editFields.ttsCustom:SetText(customText)
end

local function ReadAlertFields()
    local timing, err = NotesEditor.ParseAlertTiming(
        editFields.duration:GetText(),
        editFields.audioLeadTime:GetText(),
        editFields.countdown:GetText()
    )
    if not timing then
        return nil, err
    end

    local tts
    tts, err = NotesEditor.BuildTTSValue(
        editFields.ttsMode:GetValue(),
        editFields.ttsCustom:GetText()
    )
    if err then
        return nil, err
    end

    return {
        duration = timing.duration,
        displayType = editFields.displayType:GetValue() or "Icon",
        sound = editFields.sound:GetValue(),
        tts = tts,
        audioLeadTime = timing.audioLeadTime,
        countdown = timing.countdown,
    }
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
    editFields.sound:SetValue("")
    SetTTSFields(nil)
    editFields.audioLeadTime:SetText("5")
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
        editPanel:LayoutForPersonal()
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
        editFields.duration:SetText(tostring(reminder.duration or 5))
        editFields.displayType:SetValue(reminder.displayType or "Icon")
        editFields.sound:SetValue(reminder.sound)
        SetTTSFields(reminder.tts)
        editFields.audioLeadTime:SetText(reminder.ttsTimer and tostring(reminder.ttsTimer) or "")
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
    if state.mode == "annotate" and reminder.isPersonal then
        editFields.who:Disable()
        currentAbilities = GetLocalPlayerAbilities()
    else
        editFields.who:Enable()
        currentAbilities = NotesEditor.GetAbilitiesForTag(reminder.tag)
    end

    local abilityName, displayText = SplitAbilityAndText(reminder.text, currentAbilities)
    editFields.ability:SetValue(abilityName)
    editFields.abilityText = abilityName
    editFields.ability:GenerateMenu()
    editFields.displayText:SetText(displayText)

    editFields.duration:SetText(tostring(reminder.duration or 5))
    editFields.displayType:SetValue(reminder.displayType or "Icon")
    editFields.sound:SetValue(reminder.sound)
    SetTTSFields(reminder.tts)
    editFields.audioLeadTime:SetText(reminder.ttsTimer and tostring(reminder.ttsTimer) or "")
    editFields.countdown:SetText(reminder.countdown and tostring(reminder.countdown) or "")
    editFields.bossSpell:SetText(reminder.bossSpell and tostring(reminder.bossSpell) or "")
    editFields.colors:SetText(reminder.colors or "")
    editFields.abilitySpellId = reminder.spellID

    if state.mode == "annotate" and reminder.isPersonal then
        editPanel:LayoutForPersonal()
    else
        editPanel:LayoutForEdit()
    end
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

    local alertFields, alertErr = ReadAlertFields()
    if not alertFields then
        editPanel.errorText:SetText(alertErr)
        return
    end
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
        duration = alertFields.duration,
        displayType = alertFields.displayType,
        tts = alertFields.tts,
        ttsTimer = alertFields.audioLeadTime,
        countdown = alertFields.countdown,
        sound = alertFields.sound,
        bossSpell = bossSpellVal,
        colors = colorsVal,
    }

    if state.mode == "annotate" then
        local annotationNote = EnsureAnnotationNote()
        if state.editingReminder then
            local replaced = NotesEditor.ReplaceAnnotationReminder(
                annotationNote,
                state.editingReminder,
                newReminder
            )
            if not replaced then
                editPanel.errorText:SetText("Personal reminder could not be found.")
                return
            end
        else
            AppendReminderToNote(annotationNote, newReminder)
        end
        self:SaveCurrentAnnotation()
        self:ReloadNote()
    else
        local note = state.parsedNote
        if state.editingReminder then
            RemoveReminderFromNote(note, state.editingReminder)
        end
        AppendReminderToNote(note, newReminder)
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

    local alertFields, alertErr = ReadAlertFields()
    if not alertFields then
        editPanel.errorText:SetText(alertErr)
        return
    end

    local annReminder = NotesEditor.BuildAnnotationReminder(
        state.editingReminder,
        alertFields
    )

    local annNote = EnsureAnnotationNote()
    local replaced = NotesEditor.ReplaceAnnotationReminder(
        annNote,
        state.editingReminder,
        annReminder
    )
    if not replaced then
        AppendReminderToNote(annNote, annReminder)
    end

    self:SaveCurrentAnnotation()

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

    if state.mode == "annotate" and reminder.isPersonal then
        local removed = NotesEditor.ReplaceAnnotationReminder(note, reminder, nil)
        if not removed then
            editPanel.errorText:SetText("Personal reminder could not be found.")
            return
        end
        self:SaveCurrentAnnotation()
    else
        RemoveReminderFromNote(note, reminder)
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
    state.contextAnnotationNote = state.annotationNote
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

    local annParsed = LoadAnnotationNote(state.noteName)
    state.contextAnnotationNote = annParsed
    if state.mode == "annotate" and annParsed then
        state.annotationNote = annParsed
        parsed = PRT.NotesMerge:Merge(parsed, annParsed)
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
        contextAnnotationNote = nil,
        planningModel = nil,
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

        local annParsed = LoadAnnotationNote(name)
        state.contextAnnotationNote = annParsed
        if state.mode == "annotate" and annParsed then
            state.annotationNote = annParsed
            state.parsedNote = PRT.NotesMerge:Merge(state.parsedNote, annParsed)
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
