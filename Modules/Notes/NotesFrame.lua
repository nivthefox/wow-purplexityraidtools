-- NotesFrame: static assignment-sheet frame. A persistent, movable, resizable
-- frame that renders one note's reminder and freeform rows. Reminder rows count
-- down in real time during an encounter (driven by TickUpdate) and show static
-- times when no reference is known. Names are class-colored, raid-marker tokens
-- become raid target icons, spell icons come from spellid/bossSpell.
--
-- One render path and no preview mode; the frame renders identically whether or
-- not an encounter runs. Public method signatures are frozen.
local PRT = PurplexityRaidTools
local NotesFrame = {}
PRT.NotesFrame = NotesFrame

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local FRAME_WIDTH = 280
local FRAME_HEIGHT = 320
local MIN_WIDTH = 160
local MIN_HEIGHT = 80
local BACKDROP_PADDING = 6
local ROW_HEIGHT = 18
local ROW_SPACING = 2
local ICON_SIZE = 16
local TIME_WIDTH = 42          -- width reserved for the M:SS countdown column
local HEADER_HEIGHT = 16       -- per-encounter / phase header row height

-- Raid marker token aliases -> raid target index (1-8). {rtN} handled separately.
local MARKER_SYMBOLS = {
    star = 1, circle = 2, diamond = 3, triangle = 4,
    moon = 5, square = 6, cross = 7, skull = 8,
}

-- Countdown color-state thresholds (spec 7.1).
local WARN_THRESHOLD = 10      -- 1..10s remaining uses the configurable countdown color

--------------------------------------------------------------------------------
-- Local state
--------------------------------------------------------------------------------

local frame
local rows = {}
local rowCount = 0
local nameColorMap = {}        -- lower-cased player name -> classFile
local currentNote = nil
local fadeTicker = nil

--------------------------------------------------------------------------------
-- Settings access
--------------------------------------------------------------------------------

local function GetSettings()
    return PRT:GetSetting("notes")
end

local function GetDisplay()
    local s = GetSettings()
    return s and s.display
end

local function ResolveFont(display)
    local face = display and display.fontFace
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM and face then
        local path = LSM:Fetch("font", face, true)
        if path then
            return path
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

--------------------------------------------------------------------------------
-- Roster / name coloring
--------------------------------------------------------------------------------

-- Always includes the local player so coloring works outside a group.
function NotesFrame:RebuildRoster()
    wipe(nameColorMap)

    local playerName = UnitName("player")
    local _, playerClass = UnitClass("player")
    if playerName and playerClass then
        nameColorMap[playerName:lower()] = playerClass
    end

    for unit in PRT:IterateGroup() do
        local name = UnitName(unit)
        local _, classFile = UnitClass(unit)
        if name and classFile then
            nameColorMap[name:lower()] = classFile
        end
    end
end

-- Wraps each word matching a known raider name in that raider's class color.
-- The [%w']+ match leaves surrounding punctuation outside the color code.
local function ColorNames(text)
    if not text or text == "" then
        return text
    end
    return (text:gsub("[%w']+", function(word)
        local classFile = nameColorMap[word:lower()]
        if classFile then
            local color = RAID_CLASS_COLORS[classFile]
            if color then
                return color:WrapTextInColorCode(word)
            end
        end
        return word
    end))
end

local function ReplaceMarkers(text)
    if not text or text == "" then
        return text
    end
    return (text:gsub("{(%a*%d*)}", function(token)
        local id = MARKER_SYMBOLS[token:lower()]
        if not id then
            local n = token:lower():match("^rt(%d)$")
            if n then id = tonumber(n) end
        end
        if id and id >= 1 and id <= 8 then
            return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. id .. ":0|t"
        end
        return "{" .. token .. "}"
    end))
end

local function FormatText(text)
    return ColorNames(ReplaceMarkers(text))
end

--------------------------------------------------------------------------------
-- Time formatting
--------------------------------------------------------------------------------

local function FormatTime(seconds)
    if not seconds or seconds < 0 then
        seconds = 0
    end
    local total = math.ceil(seconds)
    local m = math.floor(total / 60)
    local s = total % 60
    return string.format("%d:%02d", m, s)
end

--------------------------------------------------------------------------------
-- Row pool
--------------------------------------------------------------------------------

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeText:SetPoint("TOPLEFT", 0, 0)
    timeText:SetWidth(TIME_WIDTH)
    timeText:SetJustifyH("RIGHT")
    timeText:SetJustifyV("TOP")
    row.timeText = timeText

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("TOPLEFT", timeText, "TOPRIGHT", 4, -1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon = icon

    local bodyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bodyText:SetJustifyH("LEFT")
    bodyText:SetJustifyV("TOP")
    bodyText:SetWordWrap(true)
    row.bodyText = bodyText

    return row
end

local function EnsureRows(n)
    while #rows < n do
        rows[#rows + 1] = CreateRow(frame.scrollChild)
    end
end

local function HideRowsFrom(from)
    for i = from, #rows do
        local row = rows[i]
        row:Hide()
        row.reminder = nil
        row.phase = nil
        row.isStatic = nil
    end
end

--------------------------------------------------------------------------------
-- Row styling / layout
--------------------------------------------------------------------------------

local function SafeSetFont(fontString, fontPath, fontSize, outline)
    fontString:SetFont(fontPath, fontSize, outline)
    if not fontString:GetFont() then
        fontString:SetFont("Fonts\\FRIZQT__.TTF", fontSize, outline)
    end
end

local function StyleRowFont(row, fontPath, fontSize, outline)
    SafeSetFont(row.timeText, fontPath, fontSize, outline)
    SafeSetFont(row.bodyText, fontPath, fontSize, outline)
end

local function LayoutRowBody(row, hasIcon, contentWidth)
    row.bodyText:ClearAllPoints()
    if hasIcon then
        row.bodyText:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 4, 1)
        row.bodyText:SetWidth(contentWidth - TIME_WIDTH - 4 - ICON_SIZE - 4)
    else
        row.bodyText:SetPoint("TOPLEFT", row.timeText, "TOPRIGHT", 4, 0)
        row.bodyText:SetWidth(contentWidth - TIME_WIDTH - 4)
    end
end

--------------------------------------------------------------------------------
-- Countdown color state (spec 7.1)
--------------------------------------------------------------------------------

-- referenceKnown false means the phase has not begun: show a static time in the
-- normal color with no countdown.
local function ApplyCountdownState(row, remaining, referenceKnown, display, hideExpired)
    local timeText = row.timeText

    if not referenceKnown then
        timeText:SetText(FormatTime(row.reminder.time))
        timeText:SetTextColor(1, 1, 1, 1)
        row:SetAlpha(1)
        return true
    end

    if remaining <= 0 then
        if hideExpired then
            return false
        end
        timeText:SetText(FormatTime(0))
        timeText:SetTextColor(0.5, 0.5, 0.5, 1)
        row:SetAlpha(0.5)
        return true
    end

    timeText:SetText(FormatTime(remaining))
    row:SetAlpha(1)

    if remaining <= WARN_THRESHOLD then
        local c = display and display.countdownColor
        if c then
            timeText:SetTextColor(c.r or 0, c.g or 1, c.b or 0, c.a or 1)
        else
            timeText:SetTextColor(0, 1, 0, 1)
        end
    else
        timeText:SetTextColor(1, 1, 1, 1)
    end
    return true
end

--------------------------------------------------------------------------------
-- Content building
--------------------------------------------------------------------------------

-- player spellID first, then bossSpell.
local function ReminderIconTexture(reminder)
    local id = reminder.spellID or reminder.bossSpell
    if id then
        return C_Spell.GetSpellTexture(id)
    end
    return nil
end

local function ReminderIncluded(reminder, showOnlyMine)
    if not showOnlyMine then
        return true
    end
    return reminder.relevant == true
end

-- Each entry is { header=string } or { reminder=..., phase=number } or
-- { freeform=string }. The note's name becomes the single header; rows follow in
-- note.lines order.
local function BuildEntries(note, showOnlyMine)
    local entries = {}
    if note.name and note.name ~= "" then
        entries[#entries + 1] = { header = note.name }
    end
    if note.lines then
        for _, line in ipairs(note.lines) do
            if line.type == "reminder" then
                if ReminderIncluded(line.reminder, showOnlyMine) then
                    entries[#entries + 1] = {
                        reminder = line.reminder,
                        phase = line.reminder.phase,
                    }
                end
            elseif line.type == "freeform" then
                entries[#entries + 1] = { freeform = line.text }
            end
        end
    end
    return entries
end

-- Returns the total content height so the scroll child can be sized.
local function RenderEntries(entries)
    local display = GetDisplay()
    local fontPath = ResolveFont(display)
    local fontSize = (display and display.fontSize) or 12
    local outline = (display and display.fontOutline) or "NONE"
    if outline == "NONE" then outline = "" end

    local contentWidth = frame.scrollChild:GetWidth()

    EnsureRows(#entries)

    local y = 0
    local index = 0
    for _, entry in ipairs(entries) do
        index = index + 1
        local row = rows[index]
        StyleRowFont(row, fontPath, fontSize, outline)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", frame.scrollChild, "RIGHT", 0, 0)
        row.reminder = nil
        row.phase = nil
        row.isStatic = nil

        if entry.header then
            row.timeText:SetText("")
            row.icon:Hide()
            row.bodyText:ClearAllPoints()
            row.bodyText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.bodyText:SetWidth(contentWidth)
            row.bodyText:SetText(entry.header)
            row.bodyText:SetTextColor(0.68, 0.51, 0.68, 1)
            row:SetHeight(HEADER_HEIGHT)
            row:SetAlpha(1)
            row:Show()
            y = y + HEADER_HEIGHT + ROW_SPACING

        elseif entry.freeform then
            row.timeText:SetText("")
            row.icon:Hide()
            LayoutRowBody(row, false, contentWidth)
            row.bodyText:SetText(FormatText(entry.freeform))
            row.bodyText:SetTextColor(1, 1, 1, 1)
            local h = math.max(ROW_HEIGHT, row.bodyText:GetStringHeight() + 2)
            row:SetHeight(h)
            row:SetAlpha(1)
            row:Show()
            y = y + h + ROW_SPACING

        else
            local reminder = entry.reminder
            row.reminder = reminder
            row.phase = entry.phase
            row.isStatic = true

            local tex = ReminderIconTexture(reminder)
            local hasIcon = tex ~= nil
            if hasIcon then
                row.icon:SetTexture(tex)
                row.icon:Show()
            else
                row.icon:Hide()
            end

            LayoutRowBody(row, hasIcon, contentWidth)
            row.bodyText:SetText(FormatText(reminder.text or ""))
            row.bodyText:SetTextColor(1, 1, 1, 1)

            -- Static time by default; TickUpdate mutates it while live.
            row.timeText:SetText(FormatTime(reminder.time))
            row.timeText:SetTextColor(1, 1, 1, 1)

            local h = math.max(ROW_HEIGHT, row.bodyText:GetStringHeight() + 2)
            row:SetHeight(h)
            row:SetAlpha(1)
            row:Show()
            y = y + h + ROW_SPACING
        end
    end

    HideRowsFrom(index + 1)
    rowCount = index

    return y
end

local function SizeScrollChild(contentHeight)
    local child = frame.scrollChild
    local minHeight = frame.scrollFrame:GetHeight()
    child:SetHeight(math.max(contentHeight, minHeight))
end

--------------------------------------------------------------------------------
-- Position persistence
--------------------------------------------------------------------------------

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

function NotesFrame:SaveFramePosition()
    if not frame then return end
    local positions = EnsurePositions()

    -- Normalize to TOPLEFT so the frame always grows downward on resize.
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local x = frame:GetLeft() * scale
    local y = (frame:GetTop() - UIParent:GetTop()) * scale

    positions.noteFrame = {
        point = "TOPLEFT",
        x = x,
        y = y,
        width = frame:GetWidth(),
        height = frame:GetHeight(),
    }
end

function NotesFrame:RestoreFramePosition()
    if not frame then return end
    local settings = GetSettings()
    local positions = settings and settings.positions
    local pos = positions and positions.noteFrame

    frame:ClearAllPoints()
    if pos then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", pos.x or 0, pos.y or 0)
        frame:SetSize(pos.width or FRAME_WIDTH, pos.height or FRAME_HEIGHT)
    else
        frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

--------------------------------------------------------------------------------
-- Lock / drag / resize
--------------------------------------------------------------------------------

local function ApplyLockState()
    if not frame then return end
    local settings = GetSettings()
    local locked = not settings or settings.locked ~= false
    local unlocked = not locked

    frame:SetMovable(unlocked)
    frame:SetResizable(unlocked)
    frame:EnableMouse(unlocked)

    if unlocked then
        frame:RegisterForDrag("LeftButton")
        frame.resizeHandle:Show()
        frame.dragHint:Show()
    else
        frame:RegisterForDrag()
        frame.resizeHandle:Hide()
        frame.dragHint:Hide()
    end
end

--------------------------------------------------------------------------------
-- Appearance (background, font applied on next render)
--------------------------------------------------------------------------------

local function ApplyBackground()
    if not frame then return end
    local display = GetDisplay()
    local bg = display and display.backgroundColor
    local opacity = (display and display.backgroundOpacity)
    if opacity == nil then opacity = 0.7 end
    local r = (bg and bg.r) or 0
    local g = (bg and bg.g) or 0
    local b = (bg and bg.b) or 0
    frame:SetBackdropColor(r, g, b, opacity)
end

--------------------------------------------------------------------------------
-- Frame construction
--------------------------------------------------------------------------------

local function CancelFade()
    if fadeTicker then
        fadeTicker:Cancel()
        fadeTicker = nil
    end
    if frame then
        frame:SetAlpha(1)
    end
end

function NotesFrame:Init()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "PRT_NotesFrame", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        tile = true, tileSize = 16,
    })

    local scrollFrame = CreateFrame("ScrollFrame", "PRT_NotesFrameScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", BACKDROP_PADDING, -BACKDROP_PADDING)
    scrollFrame:SetPoint("BOTTOMRIGHT", -(BACKDROP_PADDING + 18), BACKDROP_PADDING)
    scrollFrame.scrollBarHideable = true
    scrollFrame.ScrollBar:Hide()
    frame.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(FRAME_WIDTH - BACKDROP_PADDING * 2 - 18, FRAME_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild

    local dragHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dragHint:SetPoint("BOTTOM", frame, "BOTTOM", 0, 3)
    dragHint:SetText("PRT Notes (drag to move)")
    dragHint:Hide()
    frame.dragHint = dragHint

    local resizeHandle = CreateFrame("Frame", nil, frame)
    resizeHandle:SetSize(12, 12)
    resizeHandle:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    resizeHandle:EnableMouse(true)
    resizeHandle:SetFrameLevel(frame:GetFrameLevel() + 10)
    local handleTex = resizeHandle:CreateTexture(nil, "OVERLAY")
    handleTex:SetAllPoints()
    handleTex:SetColorTexture(1, 1, 1, 0.3)
    resizeHandle.texture = handleTex
    resizeHandle:SetScript("OnEnter", function(self) self.texture:SetColorTexture(1, 1, 1, 0.6) end)
    resizeHandle:SetScript("OnLeave", function(self) self.texture:SetColorTexture(1, 1, 1, 0.3) end)
    resizeHandle:Hide()
    frame.resizeHandle = resizeHandle

    frame:SetScript("OnDragStart", function(self)
        if not self:IsMovable() then return end
        CancelFade()
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        NotesFrame:SaveFramePosition()
    end)

    resizeHandle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not frame:IsResizable() then return end
        CancelFade()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        NotesFrame:SaveFramePosition()
    end)

    frame:SetScript("OnSizeChanged", function(self)
        -- Keep the scroll child width in sync so wrapped rows re-flow on resize.
        self.scrollChild:SetWidth(self.scrollFrame:GetWidth())
        NotesFrame:Refresh()
    end)

    self:RebuildRoster()
    self:RestoreFramePosition()
    ApplyLockState()
    ApplyBackground()
end

--------------------------------------------------------------------------------
-- Rendering entry points
--------------------------------------------------------------------------------

function NotesFrame:Refresh()
    if not frame or not frame:IsShown() then
        return
    end
    if not currentNote then
        HideRowsFrom(1)
        rowCount = 0
        SizeScrollChild(0)
        return
    end
    local settings = GetSettings()
    local display = settings and settings.display
    local showOnlyMine = not display or display.showOnlyMine ~= false
    local entries = BuildEntries(currentNote, showOnlyMine)
    local contentHeight = RenderEntries(entries)
    SizeScrollChild(contentHeight)
end

-- Never changes visibility: re-parse refreshes content only if already shown.
function NotesFrame:SetNote(note)
    if not frame then self:Init() end
    currentNote = note
    self:Refresh()
end

function NotesFrame:Show()
    if not frame then self:Init() end
    CancelFade()
    frame:Show()
    self:Refresh()
end

--------------------------------------------------------------------------------
-- Per-second tick
--------------------------------------------------------------------------------

-- A reminder row whose phase matches currentPhase has a known reference and
-- counts down; otherwise it shows a static time.
function NotesFrame:TickUpdate(now, phaseStart, currentPhase)
    if not frame or not frame:IsShown() then
        return
    end
    local display = GetDisplay()
    local hideExpired = not display or display.hideExpired ~= false

    local layoutDirty = false

    for i = 1, rowCount do
        local row = rows[i]
        local reminder = row.reminder
        if reminder then
            local referenceKnown = (currentPhase ~= nil) and (row.phase == currentPhase)
            local remaining
            if referenceKnown then
                remaining = reminder.time - (now - phaseStart)
            end
            local keep = ApplyCountdownState(row, remaining, referenceKnown, display, hideExpired)
            if keep then
                if not row:IsShown() then
                    row:Show()
                    layoutDirty = true
                end
            else
                if row:IsShown() then
                    row:Hide()
                    layoutDirty = true
                end
            end
        end
    end

    if layoutDirty then
        self:Relayout()
    end
end

-- Re-flow visible rows without rebuilding text/icons, so the sheet has no gaps
-- after TickUpdate hides/shows expired rows.
function NotesFrame:Relayout()
    if not frame then return end
    local y = 0
    for i = 1, rowCount do
        local row = rows[i]
        if row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", frame.scrollChild, "RIGHT", 0, 0)
            y = y + row:GetHeight() + ROW_SPACING
        end
    end
    SizeScrollChild(y)
end

--------------------------------------------------------------------------------
-- Encounter end / visibility
--------------------------------------------------------------------------------

function NotesFrame:OnEncounterEnd(hideMode)
    if not frame then return end
    hideMode = hideMode or "Immediately"

    if hideMode == "Never" then
        return
    end

    if hideMode == "Fade" then
        CancelFade()
        -- Linger 5 seconds, then fade out over ~1s.
        fadeTicker = C_Timer.NewTimer(5, function()
            fadeTicker = nil
            if frame then
                if frame.FadeOut then
                    frame:FadeOut()
                else
                    UIFrameFadeOut(frame, 1, frame:GetAlpha(), 0)
                    C_Timer.After(1, function()
                        if frame then
                            frame:Hide()
                            frame:SetAlpha(1)
                        end
                    end)
                end
            end
        end)
        return
    end

    self:Hide()
end

function NotesFrame:Hide()
    CancelFade()
    if frame then
        frame:Hide()
    end
end

function NotesFrame:Toggle()
    if not frame then self:Init() end
    if frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------------------------------------
-- Settings application
--------------------------------------------------------------------------------

function NotesFrame:ApplySettings()
    if not frame then
        self:Init()
        return
    end
    ApplyLockState()
    ApplyBackground()
    self:Refresh()
    if C_Timer then
        C_Timer.After(0.1, function()
            if frame and frame:IsShown() then
                self:Refresh()
            end
        end)
    end
end
