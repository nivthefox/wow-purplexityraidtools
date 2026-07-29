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
    { spellId = 359816, name = "Dream Flight",            category = "defensive", class = "EVOKER",       specId = 1468, talentId = 359816 },
    { spellId = 363534, name = "Rewind",                  category = "defensive", class = "EVOKER",       specId = 1468, talentId = 363534 },
    { spellId = 108280, name = "Healing Tide Totem",      category = "defensive", class = "SHAMAN",       specId = 264  },
    { spellId = 98008,  name = "Spirit Link Totem",       category = "defensive", class = "SHAMAN",       specId = 264,  talentId = 98008  },
    { spellId = 115310, name = "Revival / Restoral",      category = "defensive", class = "MONK",         specId = 270  },
    { spellId = 31821,  name = "Aura Mastery",            category = "defensive", class = "PALADIN",      specId = 65,   talentId = 31821  },
    { spellId = 62618,  name = "PW:B / Luminous Barrier", category = "defensive", class = "PRIEST",       specId = 256,  talentId = 62618  },
    { spellId = 64843,  name = "Divine Hymn",             category = "defensive", class = "PRIEST",       specId = 257,  talentId = 64843  },
    { spellId = 97462,  name = "Rallying Cry",            category = "defensive", class = "WARRIOR",      specId = nil,  talentId = 97462  },
    { spellId = 51052,  name = "Anti-Magic Zone",         category = "defensive", class = "DEATHKNIGHT",  specId = nil,  talentId = 51052  },
    { spellId = 196718, name = "Darkness",                category = "defensive", class = "DEMONHUNTER",  specId = nil,  talentId = 196718 },

    -- External
    { spellId = 357170, name = "Time Dilation",           category = "external",  class = "EVOKER",       specId = 1468, talentId = 357170 },
    { spellId = 33206,  name = "Pain Suppression",        category = "external",  class = "PRIEST",       specId = 256,  talentId = 33206  },
    { spellId = 102342, name = "Ironbark",                category = "external",  class = "DRUID",        specId = 105  },
    { spellId = 6940,   name = "Blessing of Sacrifice",   category = "external",  class = "PALADIN",      specId = nil,  talentId = 6940   },
    { spellId = 47788,  name = "Guardian Spirit",         category = "external",  class = "PRIEST",       specId = 257,  talentId = 47788  },
    { spellId = 53480,  name = "Roar of Sacrifice",      category = "external",  class = "HUNTER",       specId = nil,  talentId = 53480  },

    -- Movement
    { spellId = 106898, name = "Stampeding Roar",         category = "movement",  class = "DRUID",        specId = nil,  talentId = 106898 },
    { spellId = 192077, name = "Wind Rush Totem",         category = "movement",  class = "SHAMAN",       specId = nil,  talentId = 192077 },
    { spellId = 374968, name = "Time Spiral",             category = "movement",  class = "EVOKER",       specId = nil,  talentId = 374968 },
}

--------------------------------------------------------------------------------
-- Local State
--------------------------------------------------------------------------------

local specCache = {}        -- GUID -> specId
local talentCache = {}      -- GUID -> table of active talent spell IDs (set: spellId -> true)
local priorityQueue = {}    -- array of GUIDs needing immediate inspection (new joins)
local sweepQueue = {}       -- array of GUIDs queued by the periodic full-raid sweep
local inspectPending = nil  -- unit currently being inspected
local inCombat = false
local rosterCooldowns = {}  -- computed array of {spellId, name, category, playerName, playerClass}
local inspectTicker = nil   -- drains the inspect queues, one member per tick
local sweepTicker = nil     -- refills the full-raid sweep on a fixed interval

local TICK_INTERVAL = 1     -- seconds between inspect-drain attempts
local SWEEP_INTERVAL = 60   -- seconds between full-raid sweeps

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

--- Find the unit token for a GUID by scanning the current group.
local function UnitForGUID(guid)
    for unit in PRT:IterateGroup() do
        if UnitGUID(unit) == guid then
            return unit
        end
    end
    return nil
end

--- Fire off an inspect request for the given unit and set a 2-second timeout.
local function BeginInspect(unit)
    inspectPending = unit
    NotifyInspect(unit)
    C_Timer.After(2, function()
        if inspectPending == unit then
            inspectPending = nil
        end
    end)
end

--- Return true if the Blizzard inspect window is open. Inspecting while it is
--- shown hijacks the single inspect slot and breaks the player's gear tooltips.
local function IsInspectFrameOpen()
    return (InspectFrame and InspectFrame:IsShown()) or false
end

--- Return true if anyone in the group is in combat. We never inspect mid-fight,
--- and the player's own PLAYER_REGEN flag misses cases like dying mid-pull, so we
--- scan the whole group.
local function GroupInCombat()
    if inCombat then
        return true
    end
    for unit in PRT:IterateGroup() do
        if UnitAffectingCombat(unit) then
            return true
        end
    end
    return false
end

--- Rebuild the full-raid sweep queue. Runs on a fixed interval as a backstop for
--- spec/talent changes we failed to catch via events. Skips while the previous
--- sweep is still draining so a slow sweep cannot starve itself.
local function RefillSweepQueue()
    if #sweepQueue > 0 then
        return
    end
    for unit in PRT:IterateGroup() do
        if not UnitIsUnit(unit, "player") then
            local guid = UnitGUID(unit)
            if guid then
                table.insert(sweepQueue, guid)
            end
        end
    end
end

local function ProcessNextInspect()
    -- Never inspect mid-fight, while an inspect is already pending, or while the
    -- player has the Blizzard inspect window open (doing so breaks gear tooltips).
    if GroupInCombat() or inspectPending or IsInspectFrameOpen() then
        return
    end

    -- Priority queue: new joins with no cache entry go first.
    while #priorityQueue > 0 do
        local guid = table.remove(priorityQueue, 1)
        local unit = UnitForGUID(guid)
        if unit and not specCache[guid] then
            BeginInspect(unit)
            return
        end
    end

    -- Periodic full sweep: drain one queued member per tick.
    while #sweepQueue > 0 do
        local guid = table.remove(sweepQueue, 1)
        local unit = UnitForGUID(guid)
        if unit and UnitExists(unit) then
            BeginInspect(unit)
            return
        end
    end
end

local function StartInspectTicker()
    if not inspectTicker then
        inspectTicker = C_Timer.NewTicker(TICK_INTERVAL, ProcessNextInspect)
    end
    if not sweepTicker then
        sweepTicker = C_Timer.NewTicker(SWEEP_INTERVAL, RefillSweepQueue)
    end
end

local function StopInspectTicker()
    if inspectTicker then
        inspectTicker:Cancel()
        inspectTicker = nil
    end
    if sweepTicker then
        sweepTicker:Cancel()
        sweepTicker = nil
    end
end

--- Walk a trait config and return a set of active talent spell IDs
--- (spellId -> true). Returns nil if the API data is unavailable.
local function ReadTalentsFromConfig(configId)
    local config = C_Traits.GetConfigInfo(configId)
    if not config or not config.treeIDs then
        return nil
    end

    local treeID = config.treeIDs[1]
    if not treeID then
        return nil
    end

    local nodes = C_Traits.GetTreeNodes(treeID)
    if not nodes then
        return nil
    end

    local talents = {}
    for i = 1, #nodes do
        local nodeID = nodes[i]
        local node = C_Traits.GetNodeInfo(configId, nodeID)
        if node and node.ID ~= 0 and node.activeEntry then
            -- Skip hero talent subtree selection nodes.
            if not (Enum.TraitNodeType and Enum.TraitNodeType.SubTreeSelection
                    and node.type == Enum.TraitNodeType.SubTreeSelection) then
                if node.currentRank and node.currentRank > 0
                        and (not node.subTreeID or node.subTreeActive) then
                    local entryID = node.activeEntry.entryID
                    local entry = C_Traits.GetEntryInfo(configId, entryID)
                    if entry and entry.definitionID then
                        local defInfo = C_Traits.GetDefinitionInfo(entry.definitionID)
                        if defInfo and defInfo.spellID then
                            talents[defInfo.spellID] = true
                        end
                    end
                end
            end
        end
    end

    return talents
end

--- Read the local player's active talents.
local function ReadPlayerTalents()
    if not C_ClassTalents or not C_ClassTalents.GetActiveConfigID then
        return nil
    end
    local configId = C_ClassTalents.GetActiveConfigID()
    if not configId then
        return nil
    end
    return ReadTalentsFromConfig(configId)
end

--- Read the inspected player's active talents via C_Traits and return a set of
--- spell IDs (spellId -> true). Returns nil if the API data is unavailable.
local function ReadInspectTalents()
    return ReadTalentsFromConfig(Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID)
end

local function OnInspectReady(eventGUID)
    if not inspectPending then
        return
    end

    -- Verify the event GUID matches the unit we actually requested. Another
    -- addon may have triggered an inspect for a different target.
    local pendingGUID = UnitGUID(inspectPending)
    if not pendingGUID or eventGUID ~= pendingGUID then
        return
    end

    local specId = GetInspectSpecialization(inspectPending)
    local talents = ReadInspectTalents()
    inspectPending = nil

    -- Release the single inspect slot so we stop squatting on it between sweeps.
    -- Never clear while the player's inspect window is open, or we would yank the
    -- data out from under their gear tooltips.
    if not IsInspectFrameOpen() then
        ClearInspectPlayer()
    end

    local changed = false

    if specId and specId > 0 then
        if specCache[pendingGUID] ~= specId then
            specCache[pendingGUID] = specId
            changed = true
        end
    end

    if talents then
        local oldTalents = talentCache[pendingGUID]
        -- Compare talent sets: rebuild if the new set differs from the cached one.
        local talentsChanged = not oldTalents
        if not talentsChanged then
            for spellId in pairs(talents) do
                if not oldTalents[spellId] then
                    talentsChanged = true
                    break
                end
            end
        end
        if not talentsChanged then
            for spellId in pairs(oldTalents) do
                if not talents[spellId] then
                    talentsChanged = true
                    break
                end
            end
        end
        if talentsChanged then
            talentCache[pendingGUID] = talents
            changed = true
        end
    end

    if changed then
        CooldownRoster:RebuildRoster()
        CooldownRoster:UpdateDisplay()
    end
end

--------------------------------------------------------------------------------
-- Roster Scanning
--------------------------------------------------------------------------------

function CooldownRoster:ScanRoster()
    local activeGUIDs = {}

    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        if guid then
            activeGUIDs[guid] = true

            if UnitIsUnit(unit, "player") then
                local specId = GetPlayerSpecId()
                if specId and specId > 0 then
                    specCache[guid] = specId
                end
                local talents = ReadPlayerTalents()
                if talents then
                    talentCache[guid] = talents
                end
                -- If spec or talents are still missing after load, retry shortly.
                -- The talent system may not be ready on the first frame after login.
                if not specCache[guid] or not talentCache[guid] then
                    C_Timer.After(1, function()
                        CooldownRoster:ScanRoster()
                        CooldownRoster:RebuildRoster()
                        CooldownRoster:UpdateDisplay()
                    end)
                end
            elseif not specCache[guid] then
                -- New join with no cache entry: push to priority queue.
                table.insert(priorityQueue, guid)
            end
        end
    end

    -- Remove stale GUIDs (players who left)
    for guid in pairs(specCache) do
        if not activeGUIDs[guid] then
            specCache[guid] = nil
        end
    end
    for guid in pairs(talentCache) do
        if not activeGUIDs[guid] then
            talentCache[guid] = nil
        end
    end
end

function CooldownRoster:RebuildRoster()
    rosterCooldowns = {}

    for unit in PRT:IterateGroup() do
        local guid = UnitGUID(unit)
        if guid then
            local _, classToken = UnitClass(unit)
            local playerName = UnitName(unit)
            local cachedSpec = specCache[guid]

            local talents = talentCache[guid]

            for _, spell in ipairs(SPELL_DATA) do
                if spell.class == classToken then
                    if spell.specId == nil or spell.specId == cachedSpec then
                        -- When a spell has a talentId, check the player's cached
                        -- talents. If talent data is unavailable, fall back to
                        -- showing based on class + spec only.
                        local show = true
                        if spell.talentId and talents then
                            show = talents[spell.talentId] or false
                        end

                        if show then
                            table.insert(rosterCooldowns, {
                                spellId = spell.spellId,
                                name = spell.name,
                                category = spell.category,
                                playerName = playerName,
                                playerClass = classToken,
                                guid = guid,
                            })
                        end
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

    -- Notify the tracker so it knows which abilities to watch for
    PRT.CooldownTracker:OnRosterChanged(rosterCooldowns, talentCache)
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
end

function CooldownRoster:IsActivatable()
    return IsInGroup() or IsInRaid()
end

function CooldownRoster:OnEnable()
    self.eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.eventFrame:RegisterEvent("INSPECT_READY")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self.eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.eventFrame:SetScript("OnEvent", OnEvent)

    StartInspectTicker()

    self:ScanRoster()
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
    StopInspectTicker()
    for _, frame in pairs(categoryFrames) do
        frame:Hide()
    end
end

