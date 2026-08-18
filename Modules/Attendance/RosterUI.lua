-- RosterUI: the Roster sidebar tab. Lists the officer's player entries in the
-- order they hold in the roster array -- that arrangement is the officer's own,
-- and the attendance grid presents the same one -- and owns the add/edit modal,
-- the import picker, the per-character spec controls, and the two sync settings.
--
-- Every control addresses an entry by its nickname rather than by holding the
-- entry table: an incoming roster sync replaces all of them at once, and a
-- captured table would go on being edited after it left the roster.

local PRT = PurplexityRaidTools
local RosterUI = {}
PRT.RosterUI = RosterUI

local HEADER_ROW_HEIGHT = 24
local CHARACTER_ROW_HEIGHT = 24
local LIST_HEIGHT = 300
local ENTRY_SPACING = 6

local NAME_COLUMN = 16
local MAIN_SPEC_COLUMN = 190
local OFF_SPEC_COLUMN = 340
local MAIN_SPEC_WIDTH = 130
local TAG_HEIGHT = 24

local MODAL_WIDTH = 380
local MODAL_HEIGHT = 300
local IMPORT_MODAL_WIDTH = 320
local IMPORT_ROW_HEIGHT = 22

local ISO_DAY_PATTERN = "^(%d%d%d%d)%-(%d%d)%-(%d%d)$"

local MONTH_NAMES = {
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December",
}

local BACKDROP_INFO = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local RefreshList
local listContainer
local entryModal
local entryModalTarget
local importModal
local offSpecModal

local dragState
local dragHighlight
local dragCursor
local memberBounds = {}

local function PrintMessage(message)
    print("|cFF00FF00PurplexityRaidTools:|r " .. message)
end

local function PrintError(message)
    print("|cFFFF0000PurplexityRaidTools:|r " .. message)
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown()
end

local function LongDate(day)
    local year, month, dayOfMonth = tostring(day):match(ISO_DAY_PATTERN)
    if not year or not MONTH_NAMES[tonumber(month)] then
        return tostring(day)
    end
    return MONTH_NAMES[tonumber(month)] .. " " .. tonumber(dayOfMonth) .. ", " .. year
end

local function AttendanceSettings()
    return PRT:GetSetting("attendance")
end

local function ClassColoredName(character, classToken)
    local classColor = classToken and RAID_CLASS_COLORS[classToken]
    if not classColor then
        return character
    end
    return classColor:WrapTextInColorCode(character)
end

local function SpecsByID(specs)
    local byID = {}
    for _, spec in ipairs(specs or {}) do
        byID[spec.id] = spec
    end
    return byID
end

local function HasSpec(specs, specID)
    for _, existing in ipairs(specs or {}) do
        if existing == specID then
            return true
        end
    end
    return false
end

local function ParseCharacterLines(text)
    local characters = {}
    for line in tostring(text):gmatch("[^\r\n]+") do
        local trimmed = strtrim(line)
        if trimmed ~= "" then
            characters[#characters + 1] = trimmed
        end
    end
    return characters
end

local function RefreshDependentViews()
    RosterUI:Refresh()
    if PRT.AttendanceUI then
        PRT.AttendanceUI:Refresh()
    end
end

--- Sorted at the presentation seam rather than in the roster: GetEntries hands
--- out the live database, whose array order is data that sync preserves.
local function AlphabeticalEntries()
    local entries = {}
    for index, entry in ipairs(PRT.Roster:GetEntries()) do
        entries[index] = entry
    end
    table.sort(entries, function(a, b)
        return strcmputf8i(a.nickname, b.nickname) < 0
    end)
    return entries
end

--- The main-spec menu runs this from inside its own selection callback, where
--- the menu is still closing, so the row rebuild waits for the next frame.
local function RefreshListAfterMenuCloses()
    C_Timer.After(0, function()
        RosterUI:Refresh()
    end)
end

local function EnsureDragCursor()
    if dragCursor then
        return
    end
    dragCursor = CreateFrame("Frame", nil, UIParent)
    dragCursor:SetSize(200, 20)
    dragCursor:SetFrameStrata("TOOLTIP")
    dragCursor:EnableMouse(false)

    dragCursor.text = dragCursor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dragCursor.text:SetPoint("LEFT", 8, 0)
    dragCursor.text:SetJustifyH("LEFT")

    dragCursor:SetScript("OnUpdate", function(self)
        local scale = self:GetEffectiveScale()
        local x, y = GetCursorPosition()
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)
    end)

    dragCursor:Hide()
end

local function CancelDrag()
    if not dragState then
        return
    end
    if dragState.sourceRow then
        dragState.sourceRow:SetAlpha(1)
    end
    if dragHighlight then
        dragHighlight:Hide()
    end
    if dragCursor then
        dragCursor:Hide()
    end
    dragState = nil
end

local function CompleteDrag()
    if not dragState then
        return
    end

    local character = dragState.character
    local sourceNickname = dragState.sourceNickname
    local destNickname = dragState.hoverNickname
    CancelDrag()

    if not destNickname or destNickname == sourceNickname then
        return
    end

    local ok, err = PRT.Roster:MoveCharacter(character, sourceNickname, destNickname)
    if not ok and err then
        PrintError(err)
    end
    RefreshDependentViews()
end

local function ShowDragHighlight(frame, nickname)
    if not dragState or nickname == dragState.sourceNickname then
        if dragHighlight then
            dragHighlight:Hide()
        end
        if dragState then
            dragState.hoverNickname = nil
        end
        return
    end

    dragState.hoverNickname = nickname

    local bounds = memberBounds[nickname]
    if not bounds then
        return
    end

    local parent = frame:GetParent()
    if not dragHighlight then
        dragHighlight = parent:CreateTexture(nil, "OVERLAY")
        dragHighlight:SetColorTexture(0.2, 0.6, 1.0, 0.15)
    end

    dragHighlight:SetParent(parent)
    dragHighlight:ClearAllPoints()
    dragHighlight:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -bounds.top)
    dragHighlight:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    dragHighlight:SetHeight(bounds.height)
    dragHighlight:Show()
end

local function HideDragHighlight()
    if dragState then
        dragState.hoverNickname = nil
    end
    if dragHighlight then
        dragHighlight:Hide()
    end
end

--------------------------------------------------------------------------------
-- Add / edit modal
--------------------------------------------------------------------------------

local function SubmitEntryModal()
    if InCombat() then
        entryModal.errorText:SetText("The roster cannot be changed during combat.")
        return
    end

    local nickname = strtrim(entryModal.nickname:GetText())
    local characters = ParseCharacterLines(entryModal.characters:GetText())

    local ok, err
    if entryModalTarget then
        ok, err = PRT.Roster:UpdateEntry(entryModalTarget, nickname, characters)
    else
        ok, err = PRT.Roster:AddEntry(nickname, characters)
    end

    if not ok then
        entryModal.errorText:SetText(err or "The roster rejected that entry.")
        return
    end

    entryModal:Hide()
    RefreshDependentViews()
end

local function EnsureEntryModal()
    if entryModal then
        return
    end

    entryModal = CreateFrame("Frame", "PRT_RosterEntryModal", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(entryModal)
    ButtonFrameTemplate_HideButtonBar(entryModal)
    entryModal.Inset:Hide()
    entryModal:SetSize(MODAL_WIDTH, MODAL_HEIGHT)
    entryModal:SetPoint("CENTER")
    entryModal:SetFrameStrata("DIALOG")
    entryModal:SetToplevel(true)
    entryModal:SetMovable(true)
    entryModal:SetClampedToScreen(true)
    entryModal:EnableMouse(true)
    entryModal:RegisterForDrag("LeftButton")
    entryModal:SetScript("OnDragStart", entryModal.StartMoving)
    entryModal:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    entryModal:Hide()

    table.insert(UISpecialFrames, "PRT_RosterEntryModal")

    local nicknameLabel = entryModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nicknameLabel:SetPoint("TOPLEFT", 16, -32)
    nicknameLabel:SetText("Nickname")

    entryModal.nickname = CreateFrame("EditBox", nil, entryModal, "InputBoxTemplate")
    entryModal.nickname:SetSize(MODAL_WIDTH - 44, 20)
    entryModal.nickname:SetPoint("TOPLEFT", 20, -50)
    entryModal.nickname:SetAutoFocus(false)

    local charactersLabel = entryModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charactersLabel:SetPoint("TOPLEFT", 16, -80)
    charactersLabel:SetText("Characters (one Name-Realm per line)")

    local scrollFrame = CreateFrame("ScrollFrame", nil, entryModal, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -98)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 72)
    scrollFrame:EnableMouse(true)
    scrollFrame:SetScript("OnMouseDown", function()
        entryModal.characters:SetFocus()
        entryModal.characters:SetCursorPosition(#entryModal.characters:GetText())
    end)

    local textBg = CreateFrame("Frame", nil, entryModal, "BackdropTemplate")
    textBg:SetPoint("TOPLEFT", scrollFrame, -4, 4)
    textBg:SetPoint("BOTTOMRIGHT", scrollFrame, 26, -4)
    textBg:SetBackdrop(BACKDROP_INFO)
    textBg:SetBackdropColor(0, 0, 0, 0.5)
    textBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    textBg:SetFrameLevel(entryModal:GetFrameLevel() + 1)
    textBg:EnableMouse(false)

    entryModal.characters = CreateFrame("EditBox", nil, scrollFrame)
    entryModal.characters:SetMultiLine(true)
    entryModal.characters:SetAutoFocus(false)
    entryModal.characters:SetFontObject(ChatFontNormal)
    entryModal.characters:SetWidth(MODAL_WIDTH - 60)
    entryModal.characters:SetScript("OnEscapePressed", function()
        entryModal:Hide()
    end)
    scrollFrame:SetScrollChild(entryModal.characters)

    entryModal.errorText = entryModal:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    entryModal.errorText:SetPoint("BOTTOMLEFT", 16, 42)
    entryModal.errorText:SetPoint("RIGHT", -16, 0)
    entryModal.errorText:SetJustifyH("LEFT")
    entryModal.errorText:SetTextColor(1, 0.3, 0.3, 1)

    local saveButton = CreateFrame("Button", nil, entryModal, "UIPanelButtonTemplate")
    saveButton:SetSize(80, 22)
    saveButton:SetPoint("BOTTOMRIGHT", -16, 12)
    saveButton:SetText("Save")
    saveButton:SetScript("OnClick", SubmitEntryModal)

    local cancelButton = CreateFrame("Button", nil, entryModal, "UIPanelButtonTemplate")
    cancelButton:SetSize(80, 22)
    cancelButton:SetPoint("RIGHT", saveButton, "LEFT", -6, 0)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        entryModal:Hide()
    end)
end

local function OpenEntryModal(nickname, characters)
    if InCombat() then
        PrintError("The roster cannot be changed during combat.")
        return
    end

    EnsureEntryModal()

    entryModalTarget = nickname
    entryModal:SetTitle(nickname and "Edit Player" or "Add Player")
    entryModal.nickname:SetText(nickname or "")
    entryModal.characters:SetText(table.concat(characters or {}, "\n"))
    entryModal.errorText:SetText("")
    entryModal:Show()
end

StaticPopupDialogs["PRT_ROSTER_REMOVE_ENTRY"] = {
    text = "Remove %s from the roster?",
    button1 = "Remove",
    button2 = "Cancel",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function(_, nickname)
        local ok, err = PRT.Roster:RemoveEntry(nickname)
        if not ok and err then
            PrintError(err)
        end
        RefreshDependentViews()
    end,
}

--------------------------------------------------------------------------------
-- Import picker
--------------------------------------------------------------------------------

local function ImportFromDay(day)
    if InCombat() then
        PrintError("The roster cannot be changed during combat.")
        return
    end

    local dayRecord = (PurplexityRaidToolsAttendanceDB or {})[day]
    if not dayRecord then
        return
    end

    local result, err = PRT.Roster:ImportFromRecord(dayRecord)
    if not result then
        PrintError(err or "The roster rejected that import.")
        return
    end
    importModal:Hide()
    RefreshDependentViews()

    if #result.added == 0 and #result.skipped == 0 then
        PrintMessage("Every character in " .. LongDate(day) .. " is already on the roster.")
        return
    end

    PrintMessage("Imported " .. #result.added .. " character(s) from " .. LongDate(day) .. ".")
    for _, character in ipairs(result.skipped) do
        PrintError("Skipped " .. character .. ": that nickname is already taken.")
    end
end

local function RefreshImportModal()
    local db = PurplexityRaidToolsAttendanceDB or {}

    local days = {}
    for day in pairs(db) do
        days[#days + 1] = day
    end
    table.sort(days, function(a, b)
        return a > b
    end)

    for index, day in ipairs(days) do
        local row = importModal.rows[index]
        if not row then
            row = CreateFrame("Button", nil, importModal.scrollChild, "UIPanelButtonTemplate")
            row:SetHeight(IMPORT_ROW_HEIGHT)
            row:SetPoint("LEFT", 0, 0)
            row:SetPoint("RIGHT", 0, 0)
            importModal.rows[index] = row
        end

        local count = 0
        for _ in pairs(db[day]) do
            count = count + 1
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(index - 1) * IMPORT_ROW_HEIGHT)
        row:SetPoint("RIGHT", importModal.scrollChild, "RIGHT", 0, 0)
        row:SetText(LongDate(day) .. " (" .. count .. ")")
        row:SetScript("OnClick", function()
            ImportFromDay(day)
        end)
        row:Show()
    end

    for index = #days + 1, #importModal.rows do
        importModal.rows[index]:Hide()
    end

    importModal.scrollChild:SetHeight(math.max(1, #days * IMPORT_ROW_HEIGHT))
    if #days == 0 then
        importModal.emptyText:Show()
    else
        importModal.emptyText:Hide()
    end
end

local function EnsureImportModal()
    if importModal then
        return
    end

    importModal = CreateFrame("Frame", "PRT_RosterImportModal", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(importModal)
    ButtonFrameTemplate_HideButtonBar(importModal)
    importModal.Inset:Hide()
    importModal:SetSize(IMPORT_MODAL_WIDTH, 320)
    importModal:SetPoint("CENTER")
    importModal:SetTitle("Import from Record")
    importModal:SetFrameStrata("DIALOG")
    importModal:SetToplevel(true)
    importModal:SetMovable(true)
    importModal:SetClampedToScreen(true)
    importModal:EnableMouse(true)
    importModal:RegisterForDrag("LeftButton")
    importModal:SetScript("OnDragStart", importModal.StartMoving)
    importModal:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    importModal:Hide()

    table.insert(UISpecialFrames, "PRT_RosterImportModal")

    local hint = importModal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -32)
    hint:SetPoint("RIGHT", -16, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("Adds one entry per character not already on the roster.")

    local scrollFrame = CreateFrame("ScrollFrame", nil, importModal, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -54)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 16)

    importModal.scrollChild = CreateFrame("Frame", nil, scrollFrame)
    importModal.scrollChild:SetSize(IMPORT_MODAL_WIDTH - 60, 1)
    scrollFrame:SetScrollChild(importModal.scrollChild)

    importModal.emptyText = importModal:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    importModal.emptyText:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 4, -4)
    importModal.emptyText:SetText("No attendance records to import from yet.")

    importModal.rows = {}
end

--------------------------------------------------------------------------------
-- Off-spec picker
--------------------------------------------------------------------------------

local OFF_SPEC_MODAL_WIDTH = 200
local OFF_SPEC_OPTION_HEIGHT = 24

local function EnsureOffSpecModal()
    if offSpecModal then
        return
    end

    offSpecModal = CreateFrame("Frame", "PRT_RosterOffSpecModal", UIParent, "ButtonFrameTemplate")
    ButtonFrameTemplate_HidePortrait(offSpecModal)
    ButtonFrameTemplate_HideButtonBar(offSpecModal)
    offSpecModal.Inset:Hide()
    offSpecModal:SetWidth(OFF_SPEC_MODAL_WIDTH)
    offSpecModal:SetPoint("CENTER")
    offSpecModal:SetTitle("Add Off-Spec")
    offSpecModal:SetFrameStrata("DIALOG")
    offSpecModal:SetToplevel(true)
    offSpecModal:SetMovable(true)
    offSpecModal:SetClampedToScreen(true)
    offSpecModal:EnableMouse(true)
    offSpecModal:RegisterForDrag("LeftButton")
    offSpecModal:SetScript("OnDragStart", offSpecModal.StartMoving)
    offSpecModal:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetUserPlaced(false)
    end)
    offSpecModal:Hide()

    table.insert(UISpecialFrames, "PRT_RosterOffSpecModal")

    offSpecModal.options = {}
end

local function OpenOffSpecModal(character, specs, mainSpecID, offSpecs)
    if InCombat() then
        PrintError("The roster cannot be changed during combat.")
        return
    end

    EnsureOffSpecModal()

    local placed = 0
    for _, spec in ipairs(specs or {}) do
        if spec.id ~= mainSpecID and not HasSpec(offSpecs, spec.id) then
            placed = placed + 1
            local option = offSpecModal.options[placed]
            if not option then
                option = CreateFrame("Button", nil, offSpecModal, "UIPanelButtonTemplate")
                option:SetHeight(OFF_SPEC_OPTION_HEIGHT - 2)
                offSpecModal.options[placed] = option
            end

            option:ClearAllPoints()
            option:SetPoint("TOPLEFT", 16, -32 - (placed - 1) * OFF_SPEC_OPTION_HEIGHT)
            option:SetPoint("RIGHT", -16, 0)

            local specID = spec.id
            option:SetText(spec.name)
            option:SetScript("OnClick", function()
                PRT.Roster:AddOffSpec(character, specID)
                offSpecModal:Hide()
                RosterUI:Refresh()
            end)
            option:Show()
        end
    end

    for index = placed + 1, #offSpecModal.options do
        offSpecModal.options[index]:Hide()
    end

    offSpecModal:SetHeight(32 + placed * OFF_SPEC_OPTION_HEIGHT + 14)
    offSpecModal:Show()
end

--------------------------------------------------------------------------------
-- Entry list
--------------------------------------------------------------------------------

local function CreateHeaderRow(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(HEADER_ROW_HEIGHT)
    header:EnableMouse(true)

    header:SetScript("OnEnter", function(self)
        if dragState and self.ownerNickname then
            ShowDragHighlight(self, self.ownerNickname)
        end
    end)

    header:SetScript("OnLeave", function()
        if dragState then
            HideDragHighlight()
        end
    end)

    header.nickname = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.nickname:SetPoint("LEFT", NAME_COLUMN, 0)
    header.nickname:SetJustifyH("LEFT")

    header.remove = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    header.remove:SetSize(70, 20)
    header.remove:SetPoint("RIGHT", -4, 0)
    header.remove:SetText("Remove")

    header.edit = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    header.edit:SetSize(60, 20)
    header.edit:SetPoint("RIGHT", header.remove, "LEFT", -4, 0)
    header.edit:SetText("Edit")

    return header
end

local function FillHeaderRow(header, entry)
    header.nickname:SetText(entry.nickname)
    header.ownerNickname = entry.nickname

    local nickname = entry.nickname
    local characters = {}
    for index, character in ipairs(entry.characters) do
        characters[index] = character
    end

    header.edit:SetScript("OnClick", function()
        OpenEntryModal(nickname, characters)
    end)
    header.remove:SetScript("OnClick", function()
        StaticPopup_Show("PRT_ROSTER_REMOVE_ENTRY", nickname, nil, nickname)
    end)

    local enabled = not InCombat()
    header.edit:SetEnabled(enabled)
    header.remove:SetEnabled(enabled)

    header:Show()
end

local function CreateCharacterRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(CHARACTER_ROW_HEIGHT)
    row:EnableMouse(true)
    row:RegisterForDrag("LeftButton")

    row:SetScript("OnDragStart", function(self)
        if InCombat() or not self.character or not self.ownerNickname then
            return
        end
        dragState = {
            character = self.character,
            sourceNickname = self.ownerNickname,
            sourceRow = self,
        }
        self:SetAlpha(0.4)

        EnsureDragCursor()
        dragCursor.text:SetText(self.character)
        dragCursor:Show()
    end)

    row:SetScript("OnDragStop", function()
        CompleteDrag()
    end)

    row:SetScript("OnEnter", function(self)
        if dragState and self.ownerNickname then
            ShowDragHighlight(self, self.ownerNickname)
        end
    end)

    row:SetScript("OnLeave", function()
        if dragState then
            HideDragHighlight()
        end
    end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", NAME_COLUMN + 12, 0)
    row.name:SetWidth(MAIN_SPEC_COLUMN - NAME_COLUMN - 20)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.mainSpec = CreateFrame("Button", nil, row)
    row.mainSpec:SetSize(MAIN_SPEC_WIDTH, 20)
    row.mainSpec:SetPoint("LEFT", MAIN_SPEC_COLUMN, 0)
    row.mainSpec:SetNormalFontObject(GameFontHighlightSmall)
    row.mainSpec:SetHighlightFontObject(GameFontNormalSmall)
    row.mainSpec:SetDisabledFontObject(GameFontDisableSmall)
    row.mainSpec:SetText("No main spec")
    local mainSpecText = row.mainSpec:GetFontString()
    mainSpecText:ClearAllPoints()
    mainSpecText:SetPoint("LEFT", 0, 0)
    row.mainSpec:SetScript("OnClick", function()
        MenuUtil.CreateContextMenu(row.mainSpec, function(_, rootDescription)
            for _, spec in ipairs(row.specs or {}) do
                rootDescription:CreateRadio(
                    spec.name,
                    function()
                        return row.mainSpecID == spec.id
                    end,
                    function()
                        PRT.Roster:SetMainSpec(row.character, spec.id)
                        RefreshListAfterMenuCloses()
                    end
                )
            end
        end)
    end)

    row.addOffSpec = CreateFrame("Button", nil, row)
    row.addOffSpec:SetSize(16, 14)
    row.addOffSpec:SetPoint("LEFT", OFF_SPEC_COLUMN, 0)
    row.addOffSpec:SetNormalFontObject(GameFontHighlightSmall)
    row.addOffSpec:SetHighlightFontObject(GameFontNormalSmall)
    row.addOffSpec:SetDisabledFontObject(GameFontDisableSmall)
    row.addOffSpec:SetText("+")
    row.addOffSpec:SetScript("OnClick", function()
        OpenOffSpecModal(row.character, row.specs, row.mainSpecID, row.offSpecs)
    end)

    row.unknownClass = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.unknownClass:SetPoint("LEFT", OFF_SPEC_COLUMN, 0)
    row.unknownClass:SetText("Class unknown until seen in a group or the guild")

    row.tags = {}

    return row
end

local function FillTags(row, specsByID)
    local placed = 0
    local offset = OFF_SPEC_COLUMN

    for _, specID in ipairs(row.offSpecs or {}) do
        placed = placed + 1
        local tag = row.tags[placed]
        if not tag then
            tag = CreateFrame("Button", nil, row)
            tag:SetHeight(TAG_HEIGHT)
            tag:SetNormalFontObject(GameFontHighlightSmall)
            tag:SetHighlightFontObject(GameFontNormalSmall)
            tag:SetScript("OnEnter", function(self)
                if not self.specName then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.specName)
                GameTooltip:AddLine("Click to remove", 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            tag:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row.tags[placed] = tag
        end

        local spec = specsByID[specID]
        tag.specName = spec and spec.name or nil
        if spec and spec.icon then
            tag:SetText("|T" .. spec.icon .. ":24:24|t")
        else
            tag:SetText(spec and spec.name or tostring(specID))
        end
        tag:SetWidth(tag:GetFontString():GetStringWidth())
        tag:ClearAllPoints()
        tag:SetPoint("LEFT", offset, 0)
        tag:SetScript("OnClick", function()
            PRT.Roster:RemoveOffSpec(row.character, specID)
            RosterUI:Refresh()
        end)
        tag:SetEnabled(not InCombat())
        tag:Show()

        offset = offset + tag:GetWidth() + 3
    end

    for index = placed + 1, #row.tags do
        row.tags[index]:Hide()
    end

    row.addOffSpec:ClearAllPoints()
    row.addOffSpec:SetPoint("LEFT", offset, 0)
end

local function FillCharacterRow(row, character, record, nickname)
    row.character = character
    row.ownerNickname = nickname
    row.mainSpecID = record.mainSpec
    row.offSpecs = record.offSpecs

    row.name:SetText(ClassColoredName(character, record.class))

    if not record.class then
        row.specs = nil
        row.mainSpec:SetEnabled(false)
        row.mainSpec:SetText("No main spec")
        row.addOffSpec:Hide()
        row.unknownClass:Show()
        for _, tag in ipairs(row.tags) do
            tag:Hide()
        end
        row:Show()
        return
    end

    row.specs = PRT.Roster:GetSpecsForCharacter(character)
    local specsByID = SpecsByID(row.specs)
    local mainSpec = specsByID[record.mainSpec]
    row.unknownClass:Hide()
    row.mainSpec:SetEnabled(not InCombat())

    local mainSpecLabel = "|cFF808080No main spec|r"
    if mainSpec then
        local className = LOCALIZED_CLASS_NAMES_MALE[record.class] or record.class
        mainSpecLabel = ClassColoredName(mainSpec.name .. " " .. className, record.class)
        if mainSpec.icon then
            mainSpecLabel = "|T" .. mainSpec.icon .. ":24:24|t " .. mainSpecLabel
        end
    end
    row.mainSpec:SetText(mainSpecLabel)

    local remaining = 0
    for _, spec in ipairs(row.specs) do
        if spec.id ~= row.mainSpecID and not HasSpec(row.offSpecs, spec.id) then
            remaining = remaining + 1
        end
    end
    row.addOffSpec:SetEnabled(not InCombat())
    row.addOffSpec:SetShown(remaining > 0)

    FillTags(row, specsByID)
    row:Show()
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

PRT:RegisterTab("Roster", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container:Hide()
    listContainer = container

    local addButton = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    addButton:SetSize(100, 22)
    addButton:SetPoint("TOPLEFT", 20, -10)
    addButton:SetText("Add Player")
    addButton:SetScript("OnClick", function()
        OpenEntryModal(nil, nil)
    end)

    local importButton = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    importButton:SetSize(140, 22)
    importButton:SetPoint("LEFT", addButton, "RIGHT", 6, 0)
    importButton:SetText("Import from Record")
    importButton:SetScript("OnClick", function()
        EnsureImportModal()
        RefreshImportModal()
        importModal:Show()
    end)

    local syncButton = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    syncButton:SetSize(100, 22)
    syncButton:SetPoint("LEFT", importButton, "RIGHT", 6, 0)
    syncButton:SetText("Sync Roster")
    syncButton:SetScript("OnClick", function()
        if not PRT.AttendanceWiring:CanPushToRaid() then
            PrintError("Only a raid leader or assistant can sync the roster.")
            RosterUI:Refresh()
            return
        end
        PRT.AttendanceSync:PushRoster()
        PrintMessage("Pushed your roster to the raid.")
    end)

    local header = CreateFrame("Frame", nil, container)
    header:SetHeight(20)
    header:SetPoint("TOPLEFT", 20, -40)
    header:SetPoint("RIGHT", container, "RIGHT", -26, 0)

    local function AddHeading(text, offset)
        local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", offset, 0)
        label:SetText(text)
    end

    AddHeading("Name", NAME_COLUMN)
    AddHeading("Main Spec", MAIN_SPEC_COLUMN)
    AddHeading("Off Specs", OFF_SPEC_COLUMN)

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -26, 106)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(container:GetWidth() - 60, LIST_HEIGHT)
    scrollFrame:SetScrollChild(scrollChild)

    local emptyLabel = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyLabel:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 4, -4)
    emptyLabel:SetText("No players on the roster. Add one, or import from an attendance record.")

    local autoSyncCheckbox = PRT.Components.GetCheckbox(
        container, "Automatically Sync From Leader",
        function(checked)
            AttendanceSettings().autoSyncFromLeader = checked and true or false
            PRT:ApplySettings("attendance")
        end
    )
    autoSyncCheckbox:SetPoint("BOTTOMLEFT", 0, 38)

    local confirmCheckbox = PRT.Components.GetCheckbox(
        container, "Confirm Before Syncing",
        function(checked)
            AttendanceSettings().confirmBeforeSyncing = checked and true or false
            PRT:ApplySettings("attendance")
        end
    )
    confirmCheckbox:SetPoint("BOTTOMLEFT", 0, 8)

    local nicknameCheckbox
    nicknameCheckbox = PRT.Components.GetCheckbox(
        container, "Roster Nicknames",
        function(checked)
            local ok, err = PRT.RosterNicknames:SetEnabled(checked)
            if not ok then
                PrintError(err)
                nicknameCheckbox:SetValue(PRT.RosterNicknames:IsEnabled())
            end
        end
    )
    nicknameCheckbox:SetPoint("BOTTOMLEFT", 0, 68)

    local headerRows, characterRows, stripes = {}, {}, {}

    RefreshList = function()
        CancelDrag()
        memberBounds = {}

        local entries = AlphabeticalEntries()
        local placedHeaders, placedCharacters, placedStripes, yOffset = 0, 0, 0, 0

        for entryIndex, entry in ipairs(entries) do
            local entryTop = yOffset

            placedHeaders = placedHeaders + 1
            local header = headerRows[placedHeaders]
            if not header then
                header = CreateHeaderRow(scrollChild)
                headerRows[placedHeaders] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 0, -yOffset)
            header:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
            FillHeaderRow(header, entry)
            yOffset = yOffset + HEADER_ROW_HEIGHT

            for _, character in ipairs(entry.characters) do
                placedCharacters = placedCharacters + 1
                local row = characterRows[placedCharacters]
                if not row then
                    row = CreateCharacterRow(scrollChild)
                    characterRows[placedCharacters] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -yOffset)
                row:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
                FillCharacterRow(row, character, entry.characterData[character], entry.nickname)
                yOffset = yOffset + CHARACTER_ROW_HEIGHT
            end

            memberBounds[entry.nickname] = {
                top = entryTop,
                height = yOffset - entryTop,
            }

            if entryIndex % 2 == 1 then
                placedStripes = placedStripes + 1
                local stripe = stripes[placedStripes]
                if not stripe then
                    stripe = scrollChild:CreateTexture(nil, "BACKGROUND")
                    stripe:SetColorTexture(0, 0, 0, 0.35)
                    stripes[placedStripes] = stripe
                end
                stripe:ClearAllPoints()
                stripe:SetPoint("TOPLEFT", 0, -(entryTop - ENTRY_SPACING / 2))
                stripe:SetPoint("RIGHT", scrollChild, "RIGHT", 0, 0)
                stripe:SetHeight(yOffset - entryTop + ENTRY_SPACING)
                stripe:Show()
            end

            yOffset = yOffset + ENTRY_SPACING
        end

        for index = placedHeaders + 1, #headerRows do
            headerRows[index]:Hide()
        end
        for index = placedCharacters + 1, #characterRows do
            characterRows[index]:Hide()
        end
        for index = placedStripes + 1, #stripes do
            stripes[index]:Hide()
        end

        scrollChild:SetHeight(math.max(LIST_HEIGHT, yOffset))

        if #entries == 0 then
            emptyLabel:Show()
        else
            emptyLabel:Hide()
        end

        syncButton:SetEnabled(PRT.AttendanceWiring:CanPushToRaid())

        local editable = not InCombat()
        addButton:SetEnabled(editable)
        importButton:SetEnabled(editable)
        nicknameCheckbox:SetEnabled(editable)
        nicknameCheckbox:SetValue(PRT.RosterNicknames:IsEnabled())

        local settings = AttendanceSettings()
        autoSyncCheckbox:SetValue(settings.autoSyncFromLeader)
        confirmCheckbox:SetValue(settings.confirmBeforeSyncing)
    end

    container:SetScript("OnShow", function()
        RefreshList()
    end)

    local combatFrame = CreateFrame("Frame", nil, container)
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            CancelDrag()
            if entryModal then entryModal:Hide() end
            if importModal then importModal:Hide() end
            if offSpecModal then offSpecModal:Hide() end
        end
        RosterUI:Refresh()
    end)

    return container
end)

--- A hidden roster is rebuilt by its own OnShow, so an incoming sync that lands
--- while the officer is somewhere else costs nothing here.
function RosterUI:Refresh()
    if not RefreshList or not listContainer or not listContainer:IsVisible() then
        return
    end
    RefreshList()
end
