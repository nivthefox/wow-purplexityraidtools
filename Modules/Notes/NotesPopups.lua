-- NotesPopups: active reminder popup display. Renders the four timed popup types
-- (Icon, Bar, Text, Circle) that fire during an encounter, plus the audio helpers
-- (sound / TTS / countdown announcements). Owns its own frames, pools, and
-- movers. Public method signatures are frozen.

local PRT = PurplexityRaidTools
local NotesPopups = {}
PRT.NotesPopups = NotesPopups

-- Position keys are created lazily under profile.notes.positions; defaults ship
-- notes.positions as an empty table.
local TYPES = { "Icon", "Bar", "Text", "Circle" }
local POSITION_KEY = {
    Icon = "popupIcon",
    Bar = "popupBar",
    Text = "popupText",
    Circle = "popupCircle",
}

-- Default mover offsets from UIParent center, spread so the four types do not
-- overlap on first appearance.
local DEFAULT_ANCHOR = {
    Icon = { x = 0, y = 180 },
    Bar = { x = 0, y = 120 },
    Text = { x = 0, y = 60 },
    Circle = { x = 0, y = 0 },
}

local ICON_SIZE = 48
local BAR_WIDTH = 220
local BAR_HEIGHT = 24
local BAR_MIN_WIDTH = 100
local BAR_MAX_WIDTH = 1000
local BAR_MIN_HEIGHT = 10
local BAR_MAX_HEIGHT = 100
local DEFAULT_BAR_TEXTURE = "Blizzard"
local DEFAULT_BAR_TEXTURE_PATH = "Interface\\TargetingFrame\\UI-StatusBar"
local CIRCLE_SIZE = 56
local TEXT_HEIGHT = 22
local POPUP_SPACING = 4
local FADE_TIME = 0.5

local MOVER_SIZE = { -- visual size of each empty mover when unlocked
    Icon = { w = ICON_SIZE, h = ICON_SIZE + 14 },
    Bar = { w = BAR_WIDTH, h = BAR_HEIGHT },
    Text = { w = 160, h = TEXT_HEIGHT },
    Circle = { w = CIRCLE_SIZE, h = CIRCLE_SIZE + 14 },
}

local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"

local movers = {}       -- type -> mover frame
local pools = {}        -- type -> { free = {}, active = {} }
local activeByType = {} -- type -> array of active popup frames (for arrangement)
local reminderToPopup = {} -- reminder table -> popup frame (for Expire/Dismiss)
local initialized = false
local GetBarStyle

local function GetSettings()
    return PRT:GetSetting("notes")
end

local function GetPopupSettings()
    local s = GetSettings()
    return s and s.popups
end

local function GetScale()
    local p = GetPopupSettings()
    if p and type(p.scale) == "number" and p.scale > 0 then
        return p.scale
    end
    return 1
end

local function GetGrowSign()
    local p = GetPopupSettings()
    if p and p.growDirection == "Up" then
        return 1
    end
    return -1
end

local function IsLocked()
    local popups = GetPopupSettings()
    if popups and popups.locked ~= nil then
        return popups.locked
    end
    return true
end

-- reminder.colors is a raw string of space/colon separated RGBA numbers.
-- Interpretation depends on DisplayType: Bar -> fill color, all others -> text.
local function ParseColors(raw)
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local r, g, b, a
    local i = 0
    for token in raw:gmatch("([^%s:]+)") do
        local n = tonumber(token)
        if n then
            i = i + 1
            if i == 1 then r = n
            elseif i == 2 then g = n
            elseif i == 3 then b = n
            elseif i == 4 then a = n
            end
        end
    end
    if not (r and g and b) then
        return nil
    end
    return r, g, b, a or 1
end

local MARKER_INDEX = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, x = 7, skull = 8,
}

local function ReplaceMarkers(text)
    if type(text) ~= "string" or text == "" then
        return text or ""
    end
    text = text:gsub("{([%a]+)}", function(name)
        local idx = MARKER_INDEX[name:lower()]
        if idx then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. idx .. ":0|t"
        end
        return "{" .. name .. "}"
    end)
    text = text:gsub("{rt(%d)}", function(n)
        n = tonumber(n)
        if n and n >= 1 and n <= 8 then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. n .. ":0|t"
        end
        return "{rt" .. tostring(n) .. "}"
    end)
    return text
end

local function SpellTexture(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(spellID)
    end
    return nil
end

-- Popups are parented to their mover; Arrange re-anchors them on every call.
local function CreateIconPopup(mover)
    local f = CreateFrame("Frame", nil, mover)
    f:SetSize(ICON_SIZE, ICON_SIZE + 14)

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOP", 0, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local swipe = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    swipe:SetAllPoints(icon)
    swipe:SetDrawEdge(false)
    swipe:SetHideCountdownNumbers(true)
    swipe:SetReverse(true)
    f.swipe = swipe

    local timer = f:CreateFontString(nil, "OVERLAY")
    timer:SetFont(DEFAULT_FONT, 18, "OUTLINE")
    timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
    timer:SetTextColor(1, 1, 0, 1)
    f.timer = timer

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(DEFAULT_FONT, 12, "OUTLINE")
    label:SetPoint("TOP", icon, "BOTTOM", 0, -2)
    label:SetWidth(ICON_SIZE + 40)
    label:SetWordWrap(false)
    f.label = label

    return f
end

local function CreateBarPopup(mover)
    local style = GetBarStyle()
    local f = CreateFrame("StatusBar", nil, mover)
    f:SetSize(style.width, style.height)
    f:SetStatusBarTexture(style.texturePath)
    f:SetMinMaxValues(0, 1)
    f:SetValue(1)

    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)
    f.bg = bg

    local icon = f:CreateTexture(nil, "ARTWORK")
    local iconSize = math.max(1, style.height - 2)
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", f, "LEFT", 1, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.icon = icon

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(DEFAULT_FONT, 13, "OUTLINE")
    label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    f.label = label

    local timer = f:CreateFontString(nil, "OVERLAY")
    timer:SetFont(DEFAULT_FONT, 13, "OUTLINE")
    timer:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    timer:SetTextColor(1, 1, 1, 1)
    f.timer = timer
    f.tickMarks = {}

    return f
end

local function CreateTextPopup(mover)
    local f = CreateFrame("Frame", nil, mover)
    f:SetSize(160, TEXT_HEIGHT)

    local text = f:CreateFontString(nil, "OVERLAY")
    text:SetFont(DEFAULT_FONT, 20, "OUTLINE")
    text:SetPoint("CENTER")
    f.text = text

    return f
end

local function CreateCirclePopup(mover)
    local f = CreateFrame("Frame", nil, mover)
    f:SetSize(CIRCLE_SIZE, CIRCLE_SIZE + 14)

    local ring = f:CreateTexture(nil, "BACKGROUND")
    ring:SetSize(CIRCLE_SIZE, CIRCLE_SIZE)
    ring:SetPoint("TOP", 0, 0)
    ring:SetTexture("Interface\\Cooldown\\ping4")
    f.ring = ring

    local swipe = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    swipe:SetSize(CIRCLE_SIZE, CIRCLE_SIZE)
    swipe:SetPoint("TOP", 0, 0)
    swipe:SetDrawEdge(true)
    swipe:SetHideCountdownNumbers(true)
    swipe:SetReverse(true)
    swipe:SetSwipeTexture("Interface\\Cooldown\\ping4")
    f.swipe = swipe

    local timer = f:CreateFontString(nil, "OVERLAY")
    timer:SetFont(DEFAULT_FONT, 16, "OUTLINE")
    timer:SetPoint("CENTER", ring, "CENTER", 0, 0)
    timer:SetTextColor(1, 1, 0, 1)
    f.timer = timer

    local label = f:CreateFontString(nil, "OVERLAY")
    label:SetFont(DEFAULT_FONT, 12, "OUTLINE")
    label:SetPoint("TOP", ring, "BOTTOM", 0, -2)
    label:SetWidth(CIRCLE_SIZE + 40)
    label:SetWordWrap(false)
    f.label = label

    return f
end

local CONSTRUCTORS = {
    Icon = CreateIconPopup,
    Bar = CreateBarPopup,
    Text = CreateTextPopup,
    Circle = CreateCirclePopup,
}

local function HasActivePopups(displayType)
    local active = activeByType[displayType]
    return active and #active > 0
end

local function EnsureMoverVisibility(displayType)
    local mover = movers[displayType]
    if not mover then return end
    if not IsLocked() or HasActivePopups(displayType) then
        mover:Show()
    else
        mover:Hide()
    end
end

local function AcquirePopup(displayType)
    local pool = pools[displayType]
    local f = table.remove(pool.free)
    if not f then
        f = CONSTRUCTORS[displayType](movers[displayType])
        f.displayType = displayType
    end
    f.fading = false
    f.fadeElapsed = 0
    f:SetParent(movers[displayType])
    f:SetAlpha(1)
    movers[displayType]:Show()
    f:Show()
    return f
end

local function ReleasePopup(f)
    if not f or f.released then return end
    f.released = true
    f:Hide()
    f:SetScript("OnUpdate", nil)
    f:SetAlpha(1)

    local reminder = f.reminder
    if reminder then
        reminderToPopup[reminder] = nil
    end
    f.reminder = nil
    f.barTimeline = nil
    if f.tickMarks then
        for _, marker in ipairs(f.tickMarks) do
            marker:Hide()
        end
    end

    local displayType = f.displayType
    local active = activeByType[displayType]
    for i = #active, 1, -1 do
        if active[i] == f then
            table.remove(active, i)
            break
        end
    end

    table.insert(pools[displayType].free, f)
    NotesPopups:Arrange(displayType)
    EnsureMoverVisibility(displayType)
end

-- Popups of a type stack from the mover, sorted soonest-to-expire on top. A
-- fading frame keeps its slot until released so the stack does not jump.
local function ExpiryOf(f)
    return f.eventTime or 0
end

function NotesPopups:Arrange(displayType)
    local mover = movers[displayType]
    if not mover then return end
    local active = activeByType[displayType]

    table.sort(active, function(a, b)
        local ea, eb = ExpiryOf(a), ExpiryOf(b)
        if ea == eb then
            return tostring(a) < tostring(b)
        end
        return ea < eb
    end)

    local scale = GetScale()
    local sign = GetGrowSign()
    local anchorPoint = (sign < 0) and "TOP" or "BOTTOM"
    local relPoint = anchorPoint

    local offset = 0
    for _, f in ipairs(active) do
        f:SetScale(scale)
        f:ClearAllPoints()
        f:SetPoint(anchorPoint, mover, relPoint, 0, sign * offset)
        offset = offset + f:GetHeight() + POPUP_SPACING
    end
end

-- The timer text is reformatted only when the displayed value changes, so no
-- per-frame string garbage.
local function FormatRemaining(secs)
    if secs >= 10 then
        return tostring(math.floor(secs + 0.5))
    end
    -- Under 10s show one decimal, matching the bar/circle sweeps.
    return string.format("%.1f", secs)
end

local function PopupOnUpdate(f)
    local now = GetTime()
    local remaining = f.eventTime - now
    if remaining < 0 then remaining = 0 end

    if f.displayType == "Bar" and f.duration and f.duration > 0 then
        f:SetValue(remaining / f.duration)
    end

    local shown
    if remaining >= 10 then
        shown = math.floor(remaining + 0.5)
    else
        shown = math.floor(remaining * 10 + 0.5) -- tenths
    end
    if shown ~= f.lastShown then
        f.lastShown = shown
        if f.timer then
            f.timer:SetText(FormatRemaining(remaining))
        end
        if f.textFormat then
            f.text:SetText(f.baseText .. " (" .. math.ceil(remaining) .. ")")
        end
    end
end

local function FadeOnUpdate(f, elapsed)
    f.fadeElapsed = f.fadeElapsed + elapsed
    local t = f.fadeElapsed / FADE_TIME
    if t >= 1 then
        ReleasePopup(f)
        return
    end
    f:SetAlpha(1 - t)
end

local function Clamp(value, minimum, maximum, fallback)
    value = tonumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

function NotesPopups.MigrateSettings(_, popups)
    popups = popups or GetPopupSettings()
    if type(popups) ~= "table" then
        return
    end
    if not popups.typeEnablementMigrated then
        local enabled = popups.enabled ~= false
        popups.enabledTypes = popups.enabledTypes or {}
        for _, displayType in ipairs(TYPES) do
            popups.enabledTypes[displayType] = enabled
        end
        popups.enabled = nil
        popups.typeEnablementMigrated = true
    end
    if type(popups.enabledTypes) ~= "table" then
        popups.enabledTypes = {}
    end
    for _, displayType in ipairs(TYPES) do
        if popups.enabledTypes[displayType] == nil then
            popups.enabledTypes[displayType] = true
        end
    end
end

function NotesPopups.IsTypeEnabled(_, displayType, popups)
    popups = popups or GetPopupSettings()
    if type(popups) ~= "table" then
        return true
    end
    local enabledTypes = popups.enabledTypes
    return type(enabledTypes) ~= "table" or enabledTypes[displayType] ~= false
end

function NotesPopups.GetBarStyle(_, popups, fetchTexture)
    popups = popups or GetPopupSettings()
    local width = Clamp(
        popups and popups.barWidth,
        BAR_MIN_WIDTH,
        BAR_MAX_WIDTH,
        BAR_WIDTH
    )
    local height = Clamp(
        popups and popups.barHeight,
        BAR_MIN_HEIGHT,
        BAR_MAX_HEIGHT,
        BAR_HEIGHT
    )
    local texture = popups and popups.barTexture or DEFAULT_BAR_TEXTURE
    local texturePath = fetchTexture and fetchTexture(texture)
    return {
        width = width,
        height = height,
        texture = texture,
        texturePath = texturePath or DEFAULT_BAR_TEXTURE_PATH,
    }
end

GetBarStyle = function()
    return NotesPopups:GetBarStyle(GetPopupSettings(), function(texture)
        local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
        return lsm and lsm:Fetch("statusbar", texture, true)
    end)
end

local function SetBarTicks(f, timeline)
    for _, marker in ipairs(f.tickMarks) do
        marker:Hide()
    end
    if not timeline then
        return
    end

    for index, tick in ipairs(timeline.ticks) do
        local marker = f.tickMarks[index]
        if not marker then
            marker = f:CreateTexture(nil, "OVERLAY", nil, 7)
            marker:SetColorTexture(1, 1, 1, 0.9)
            f.tickMarks[index] = marker
        end
        local width = f:GetWidth()
        marker:SetSize(2, f:GetHeight())
        local x = math.max(1, math.min(width - 1, tick.progress * width))
        marker:ClearAllPoints()
        marker:SetPoint("CENTER", f, "LEFT", x, 0)
        marker:Show()
    end
end

-- `remaining` is the seconds until the reminder time at the moment of the call.
-- Compound bars continue from there through their final tick.
function NotesPopups:Show(reminder, remaining)
    if not reminder then return end
    if not initialized then self:Init() end

    if reminderToPopup[reminder] then
        return
    end

    local displayType = reminder.displayType
    if not CONSTRUCTORS[displayType] then
        displayType = reminder.spellID and "Icon" or "Text"
    end
    if not self:IsTypeEnabled(displayType) then
        return
    end

    remaining = tonumber(remaining)
    if not remaining then
        remaining = reminder.duration or 0
    end
    local duration = reminder.duration or remaining
    if duration <= 0 then duration = remaining > 0 and remaining or 1 end

    local barTimeline
    if displayType == "Bar" and PRT.NotesBossTimeline then
        barTimeline = PRT.NotesBossTimeline:GetBarTimeline(reminder)
    end
    local popupRemaining = remaining
    if barTimeline then
        duration = barTimeline.duration
        popupRemaining = remaining + barTimeline.postDuration
    elseif popupRemaining < 0 then
        popupRemaining = duration
        remaining = duration
    end

    local now = GetTime()
    local f = AcquirePopup(displayType)
    f.released = false
    f.reminder = reminder
    f.eventTime = now + popupRemaining
    f.duration = duration
    f.lastShown = nil
    f.textFormat = nil
    f.baseText = nil
    f.barTimeline = barTimeline

    reminderToPopup[reminder] = f
    table.insert(activeByType[displayType], f)

    local text = ReplaceMarkers(reminder.text or "")
    local cr, cg, cb, ca = ParseColors(reminder.colors)

    if displayType == "Icon" then
        f.icon:SetTexture(SpellTexture(reminder.spellID) or 134400)
        f.swipe:SetCooldown(now, duration)
        f.label:SetText(text)
        if cr then f.label:SetTextColor(cr, cg, cb, ca) else f.label:SetTextColor(1, 1, 1, 1) end

    elseif displayType == "Bar" then
        if f.SetReverseFill then
            f:SetReverseFill(barTimeline ~= nil)
        end
        SetBarTicks(f, barTimeline)
        local tex = SpellTexture(reminder.spellID)
        if tex then
            f.icon:SetTexture(tex)
            f.icon:Show()
            f.label:ClearAllPoints()
            f.label:SetPoint("LEFT", f.icon, "RIGHT", 4, 0)
        else
            f.icon:Hide()
            f.label:ClearAllPoints()
            f.label:SetPoint("LEFT", f, "LEFT", 4, 0)
        end
        f.label:SetText(text)
        f:SetValue(1)
        if cr then f:SetStatusBarColor(cr, cg, cb, ca) else f:SetStatusBarColor(0.8, 0.1, 0.1, 1) end

    elseif displayType == "Circle" then
        f.swipe:SetCooldown(now, duration)
        f.label:SetText(text)
        if cr then f.timer:SetTextColor(cr, cg, cb, ca) end

    else -- Text
        f.baseText = text
        f.textFormat = true
        if cr then f.text:SetTextColor(cr, cg, cb, ca) else f.text:SetTextColor(1, 0.82, 0, 1) end
        f.text:SetText(text .. " (" .. math.ceil(remaining) .. ")")
        f:SetWidth(math.max(80, f.text:GetStringWidth() + 20))
    end

    f:SetScript("OnUpdate", PopupOnUpdate)
    PopupOnUpdate(f)
    self:Arrange(displayType)
end

function NotesPopups:Expire(reminder)
    local f = reminderToPopup[reminder]
    if not f then return end
    if f.fading then return end
    f.fading = true
    f.fadeElapsed = 0
    f:SetScript("OnUpdate", FadeOnUpdate)
end

function NotesPopups:Dismiss(reminder)
    local f = reminderToPopup[reminder]
    if not f then return end
    f.fading = false
    ReleasePopup(f)
end

function NotesPopups:DismissAll()
    for _, displayType in ipairs(TYPES) do
        local active = activeByType[displayType]
        -- Release from the end; ReleasePopup mutates the array.
        for i = #active, 1, -1 do
            local f = active[i]
            f.fading = false
            ReleasePopup(f)
        end
    end
end

-- Explicit sound wins over TTS. Sound resolves via LibSharedMedia (name) or a
-- direct file path; TTS fires only when no sound is set (or the sound fails to
-- resolve) and the Enable TTS setting is on.
local LSM
local lsmSoundCache

local function GetLSM()
    if LSM == nil then
        LSM = LibStub and LibStub("LibSharedMedia-3.0", true) or false
    end
    return LSM or nil
end

local function BuildSoundCache(lsm)
    lsmSoundCache = {}
    for _, key in ipairs(lsm:List("sound")) do
        local clean = key:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^[%s|]*(.-)[%s|]*$")
        lsmSoundCache[clean:lower()] = key
    end
end

local function ResolveLSMSound(name)
    local lsm = GetLSM()
    if not lsm then return nil end

    local path = lsm:Fetch("sound", name, true)
    if path and path ~= 1 and path ~= "" then
        return path
    end

    if not lsmSoundCache then
        BuildSoundCache(lsm)
    end
    local lsmKey = lsmSoundCache[name:lower()]
    if lsmKey then
        path = lsm:Fetch("sound", lsmKey, true)
        if path and path ~= 1 and path ~= "" then
            return path
        end
    end

    return nil
end

function NotesPopups:PreviewSound(name)
    if not name or name == "" then
        return false
    end

    local path = ResolveLSMSound(name)
    if path and PlaySoundFile(path, "Master") then
        return true
    end
    return PlaySoundFile(name, "Master") == true
end

function NotesPopups:PlayAudio(reminder)
    if not reminder then return end
    local p = GetPopupSettings()

    if reminder.sound and reminder.sound ~= "" then
        if p and p.soundsEnabled == false then
            return
        end
        if self:PreviewSound(reminder.sound) then
            return
        end
    end

    -- tts may be a string or a "true" sentinel kept by the parser; support both.
    local tts = reminder.tts
    if tts == nil or tts == false then return end
    local ttsOn = not p or p.ttsEnabled ~= false
    if not ttsOn then return end

    local spoken
    if type(tts) == "string" and tts ~= "" and tts ~= "true" then
        spoken = tts
    else
        spoken = reminder.text
    end
    spoken = ReplaceMarkers(spoken or "")
    if spoken == "" then return end

    if C_VoiceChat and C_VoiceChat.SpeakText then
        local voiceID = 0
        if C_VoiceChat.GetTtsVoices then
            local voices = C_VoiceChat.GetTtsVoices()
            if voices and voices[1] then voiceID = voices[1].voiceID end
        end
        C_VoiceChat.SpeakText(voiceID, spoken, 0, 100)
    end
end

-- Fires even when the Enable TTS toggle is off; countdowns are independent of it.
local COUNTDOWN_SOUND = "Interface\\AddOns\\BigWigs\\Media\\Sounds\\Amy\\%d.ogg"

function NotesPopups:AnnounceCountdown(n)
    if not n or n < 1 or n > 10 then return end
    PlaySoundFile(COUNTDOWN_SOUND:format(n), "Master")
end

local function GetPositionsStore()
    local profile = PRT.Profiles:GetCurrent()
    if not profile.notes then
        profile.notes = {}
    end
    if not profile.notes.positions then
        profile.notes.positions = {}
    end
    return profile.notes.positions
end

local function SaveMoverPosition(displayType)
    local mover = movers[displayType]
    if not mover then return end
    local positions = GetPositionsStore()
    -- Normalize to a CENTER-vs-CENTER offset so the mover restores identically
    -- regardless of UI scale.
    local scale = mover:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local cx, cy = mover:GetCenter()
    local x = (cx - UIParent:GetWidth() / 2) * scale
    local y = (cy - UIParent:GetHeight() / 2) * scale

    positions[POSITION_KEY[displayType]] = { point = "CENTER", x = x, y = y }
end

local function RestoreMoverPosition(displayType)
    local mover = movers[displayType]
    if not mover then return end
    local settings = GetSettings()
    local positions = settings and settings.positions
    local key = POSITION_KEY[displayType]

    mover:ClearAllPoints()
    if positions and positions[key] then
        local pos = positions[key]
        mover:SetPoint("CENTER", UIParent, "CENTER", pos.x or 0, pos.y or 0)
    else
        local def = DEFAULT_ANCHOR[displayType]
        mover:SetPoint("CENTER", UIParent, "CENTER", def.x, def.y)
    end
end

local function CreateMover(displayType)
    local mover = CreateFrame("Frame", "PRT_NotesPopupMover_" .. displayType, UIParent, "BackdropTemplate")
    local size = MOVER_SIZE[displayType]
    if displayType == "Bar" then
        local style = GetBarStyle()
        mover:SetSize(style.width, style.height)
    else
        mover:SetSize(size.w, size.h)
    end
    mover:SetFrameStrata("HIGH")
    mover:SetClampedToScreen(true)
    mover:EnableMouse(false)

    local label = mover:CreateFontString(nil, "OVERLAY")
    label:SetFont(DEFAULT_FONT, 11, "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(displayType)
    mover.label = label

    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function(self)
        if self:IsMovable() then self:StartMoving() end
    end)
    mover:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveMoverPosition(displayType)
        NotesPopups:Arrange(displayType)
    end)

    return mover
end

local MOVER_BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

function NotesPopups:SetLocked(locked)
    for _, displayType in ipairs(TYPES) do
        local mover = movers[displayType]
        if mover then
            mover:SetMovable(not locked)
            mover:EnableMouse(not locked)
            if locked then
                mover:SetBackdrop(nil)
                mover.label:Hide()
            else
                mover:SetBackdrop(MOVER_BACKDROP)
                mover:SetBackdropColor(0.1, 0.1, 0.3, 0.6)
                mover:SetBackdropBorderColor(0.5, 0.5, 0.8, 0.9)
                mover.label:Show()
            end
            EnsureMoverVisibility(displayType)
        end
    end
end

function NotesPopups:ApplySettings()
    self:MigrateSettings()
    local style = GetBarStyle()
    local barMover = movers.Bar
    if barMover then
        barMover:SetSize(style.width, style.height)
    end
    local barPool = pools.Bar
    if barPool then
        local function ApplyBarStyle(f)
            f:SetSize(style.width, style.height)
            f:SetStatusBarTexture(style.texturePath)
            local iconSize = math.max(1, style.height - 2)
            f.icon:SetSize(iconSize, iconSize)
            SetBarTicks(f, f.barTimeline)
        end
        for _, f in ipairs(barPool.free) do
            ApplyBarStyle(f)
        end
        for _, f in ipairs(activeByType.Bar) do
            ApplyBarStyle(f)
        end
    end

    for _, displayType in ipairs(TYPES) do
        if not self:IsTypeEnabled(displayType) then
            local active = activeByType[displayType] or {}
            for index = #active, 1, -1 do
                ReleasePopup(active[index])
            end
        end
    end

    for _, displayType in ipairs(TYPES) do
        RestoreMoverPosition(displayType)
        self:Arrange(displayType)
    end
    self:SetLocked(IsLocked())
end

function NotesPopups:Init()
    if initialized then return end
    initialized = true
    self:MigrateSettings()

    for _, displayType in ipairs(TYPES) do
        pools[displayType] = { free = {} }
        activeByType[displayType] = {}
        movers[displayType] = CreateMover(displayType)
        RestoreMoverPosition(displayType)
    end

    self:SetLocked(IsLocked())
end

function NotesPopups:ShowTestSamples(samples, schedule)
    for _, reminder in ipairs(samples) do
        local sample = reminder
        self:Show(sample, sample.duration)
        schedule(sample.duration, function()
            self:Expire(sample)
        end)
    end
end

function NotesPopups:Test()
    if not initialized then self:Init() end

    local samples = {
        {
            displayType = "Icon", spellID = 31821, text = "Aura Mastery",
            duration = 8, colors = "1 1 1 1",
        },
        {
            displayType = "Bar", spellID = 62618, text = "Dodge Breath",
            duration = 8, colors = "0.2 0.6 1 1",
        },
        {
            displayType = "Text", text = "Spread Now",
            duration = 8, colors = "0 1 0 1",
        },
        {
            displayType = "Circle", spellID = 740, text = "Tranquility",
            duration = 8, colors = "1 1 0 1",
        },
    }

    self:ShowTestSamples(samples, function(delay, callback)
        C_Timer.After(delay, callback)
    end)
end
