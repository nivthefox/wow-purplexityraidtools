-- NotesConfig: Notes config tab UI.
local PRT = PurplexityRaidTools
local NotesConfig = {}
PRT.NotesConfig = NotesConfig

local TOOLTIP_NO_PRIVILEGE = "Requires raid leader or assistant."
local TOOLTIP_COMBAT = "Cannot send during combat."
local TOOLTIP_NO_SELECTION = "No note selected."
local ERROR_NAME_REQUIRED = "Name is required."
local ERROR_NAME_TAKEN = "A note with that name already exists."

local LIST_HEIGHT = 180
local LIST_ROW_HEIGHT = 20
local ACTIVE_COLOR = { r = 0.4, g = 0.8, b = 1 }
local SELECTED_COLOR = { r = 0.3, g = 0.3, b = 0.5 }

local OUTLINE_OPTIONS = {
    { name = "None",          value = "NONE" },
    { name = "Outline",       value = "OUTLINE" },
    { name = "Thick Outline", value = "THICKOUTLINE" },
    { name = "Monochrome",    value = "MONOCHROME" },
}

local HIDE_MODE_OPTIONS = {
    { name = "Immediately", value = "Immediately" },
    { name = "Fade",        value = "Fade" },
    { name = "Never",       value = "Never" },
}

local GROW_OPTIONS = {
    { name = "Up",   value = "Up" },
    { name = "Down", value = "Down" },
}

local CONTENT_CHECKBOXES = {
    { label = "Open World",        path = { "contentTypes", "openWorld" } },
    { label = "Dungeon (Normal)",  path = { "contentTypes", "dungeon", "normal" } },
    { label = "Dungeon (Heroic)",  path = { "contentTypes", "dungeon", "heroic" } },
    { label = "Dungeon (Mythic)",  path = { "contentTypes", "dungeon", "mythic" } },
    { label = "Dungeon (Mythic+)", path = { "contentTypes", "dungeon", "mythicPlus" } },
    { label = "Raid (LFR)",        path = { "contentTypes", "raid", "lfr" } },
    { label = "Raid (Normal)",     path = { "contentTypes", "raid", "normal" } },
    { label = "Raid (Heroic)",     path = { "contentTypes", "raid", "heroic" } },
    { label = "Raid (Mythic)",     path = { "contentTypes", "raid", "mythic" } },
    { label = "Scenario (Normal)", path = { "contentTypes", "scenario", "normal" } },
    { label = "Scenario (Heroic)", path = { "contentTypes", "scenario", "heroic" } },
}

local function GetSettings()
    return PRT:GetSetting("notes")
end

local function ReadPath(settings, path)
    if #path == 2 then
        return settings[path[1]][path[2]]
    end
    return settings[path[1]][path[2]][path[3]]
end

local function WritePath(settings, path, value)
    if #path == 2 then
        settings[path[1]][path[2]] = value
        return
    end
    settings[path[1]][path[2]][path[3]] = value
end

local function ListFonts()
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if not LSM then
        return {}
    end
    local names = LSM:List("font")
    local items = {}
    for _, name in ipairs(names) do
        items[#items + 1] = { name = name, value = name }
    end
    return items
end

local function SortedNoteNames()
    local settings = GetSettings()
    local names = {}
    for name in pairs(settings.savedNotes or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

--------------------------------------------------------------------------------
-- Static popups
--------------------------------------------------------------------------------

StaticPopupDialogs["PRT_NOTES_DELETE"] = {
    text = "Delete note \"%s\"?",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    OnAccept = function()
        if NotesConfig.OnDeleteNote then
            NotesConfig.OnDeleteNote()
        end
    end,
}

local function OnEditorSaved(savedName)
    if NotesConfig._refreshAfterSave then
        NotesConfig._refreshAfterSave(savedName)
    end
end

--------------------------------------------------------------------------------
-- Tab
--------------------------------------------------------------------------------

PRT:RegisterTab("Notes", function(parent)
    local ROW_HEIGHT = 28

    --------------------------------------------------------------------
    -- Sub-tab: Notes (note management + test buttons)
    --------------------------------------------------------------------

    local function SetupNotes(panel)
        local childWidth = panel:GetWidth()
        local yOffset = -10

        local selectedNote

        local refreshGates
        local refreshList
        local RefreshTestNoteButton

        local function CurrentActiveName()
            return (PRT.Notes:GetActiveNote())
        end

        local function IsNotesFrameShown()
            local frame = _G.PRT_NotesFrame
            return frame ~= nil and frame:IsShown()
        end

        local function PushIfActive(name)
            if name ~= CurrentActiveName() then
                return
            end
            PRT.Notes:OnActiveNoteChanged()
        end

        local listFrame = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        listFrame:SetPoint("TOPLEFT", 20, yOffset)
        listFrame:SetSize(childWidth - 48, LIST_HEIGHT)
        listFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        listFrame:SetBackdropColor(0, 0, 0, 0.5)

        local listScroll = CreateFrame("ScrollFrame", nil, listFrame, "UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT", 6, -6)
        listScroll:SetPoint("BOTTOMRIGHT", -26, 6)

        local listChild = CreateFrame("Frame", nil, listScroll)
        listChild:SetSize(childWidth - 80, LIST_HEIGHT)
        listScroll:SetScrollChild(listChild)

        local listRows = {}

        local function SelectNote(name)
            selectedNote = name
            refreshList()
            refreshGates()
        end

        refreshList = function()
            local names = SortedNoteNames()
            local activeName = CurrentActiveName()

            if selectedNote and not GetSettings().savedNotes[selectedNote] then
                selectedNote = nil
            end

            for i, name in ipairs(names) do
                local row = listRows[i]
                if not row then
                    row = CreateFrame("Button", nil, listChild)
                    row:SetHeight(LIST_ROW_HEIGHT)
                    row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
                    row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)

                    row.highlight = row:CreateTexture(nil, "BACKGROUND")
                    row.highlight:SetAllPoints()
                    row.highlight:SetColorTexture(SELECTED_COLOR.r, SELECTED_COLOR.g, SELECTED_COLOR.b, 0.6)
                    row.highlight:Hide()

                    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    row.label:SetPoint("LEFT", 6, 0)
                    row.label:SetPoint("RIGHT", -6, 0)
                    row.label:SetJustifyH("LEFT")

                    row:SetScript("OnClick", function(self)
                        SelectNote(self.noteName)
                    end)

                    listRows[i] = row
                end

                row.noteName = name
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -(i - 1) * LIST_ROW_HEIGHT)
                row:SetPoint("RIGHT", listChild, "RIGHT", 0, 0)

                local isActive = (name == activeName)
                local labelText = name
                if isActive then
                    labelText = name .. " (active)"
                    row.label:SetTextColor(ACTIVE_COLOR.r, ACTIVE_COLOR.g, ACTIVE_COLOR.b)
                else
                    row.label:SetTextColor(1, 1, 1)
                end
                row.label:SetText(labelText)

                if name == selectedNote then
                    row.highlight:Show()
                else
                    row.highlight:Hide()
                end

                row:Show()
            end

            for i = #names + 1, #listRows do
                listRows[i]:Hide()
            end

            listChild:SetHeight(math.max(LIST_HEIGHT, #names * LIST_ROW_HEIGHT))
        end

        yOffset = yOffset - LIST_HEIGHT - 8

        NotesConfig._refreshAfterSave = function(savedName)
            selectedNote = savedName
            refreshList()
            refreshGates()
            PushIfActive(savedName)
        end

        local buttonRow = CreateFrame("Frame", nil, panel)
        buttonRow:SetPoint("TOPLEFT", 20, yOffset)
        buttonRow:SetSize(childWidth - 48, 24)

        local function MakeButton(label, width, anchor, fromRight)
            local button = CreateFrame("Button", nil, buttonRow, "UIPanelButtonTemplate")
            button:SetSize(width, 22)
            if fromRight then
                if anchor then
                    button:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
                else
                    button:SetPoint("RIGHT", 0, 0)
                end
            else
                if anchor then
                    button:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
                else
                    button:SetPoint("LEFT", 0, 0)
                end
            end
            button:SetText(label)
            return button
        end

        local newButton = MakeButton("New", 60)
        local editButton = MakeButton("Edit", 60, newButton)
        local annotateButton = MakeButton("Annotate", 70, editButton)
        local deleteButton = MakeButton("Delete", 60, annotateButton)

        local testButton = MakeButton("Test", 60, nil, true)
        local showHideButton = MakeButton("Show", 60, testButton, true)
        local clearButton = MakeButton("Clear", 60, showHideButton, true)
        local sendButton = MakeButton("Send", 70, clearButton, true)
        local activateButton = MakeButton("Activate", 70, clearButton, true)

        yOffset = yOffset - 30

        local buttonError = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        buttonError:SetPoint("TOPLEFT", 20, yOffset)
        buttonError:SetWidth(childWidth - 48)
        buttonError:SetJustifyH("LEFT")
        buttonError:SetTextColor(1, 0.3, 0.3, 1)
        buttonError:SetText("")

        yOffset = yOffset - 22

        newButton:SetScript("OnClick", function()
            buttonError:SetText("")
            PRT.NotesEditor:Open(nil, "")
        end)

        editButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            local text = GetSettings().savedNotes[selectedNote]
            buttonError:SetText("")
            PRT.NotesEditor:Open(selectedNote, text or "", "edit")
        end)

        annotateButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            local text = GetSettings().savedNotes[selectedNote]
            buttonError:SetText("")
            PRT.NotesEditor:Open(selectedNote, text or "", "annotate")
        end)

        activateButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            buttonError:SetText("")
            PRT.Notes:ActivateNote(selectedNote, "self")
            PRT.NotesFrame:Show()
            refreshList()
            refreshGates()
        end)

        deleteButton:SetScript("OnClick", function()
            if not selectedNote then
                return
            end
            buttonError:SetText("")
            StaticPopup_Show("PRT_NOTES_DELETE", selectedNote)
        end)

        sendButton:SetScript("OnClick", function()
            local ok, reason = PRT.Notes:BroadcastNote(selectedNote)
            buttonError:SetText(not ok and reason or "")
            refreshList()
            refreshGates()
        end)

        clearButton:SetScript("OnClick", function()
            local ok, reason = PRT.Notes:BroadcastClear()
            buttonError:SetText(not ok and reason or "")
            refreshList()
            refreshGates()
        end)

        showHideButton:SetScript("OnClick", function()
            buttonError:SetText("")
            if not selectedNote then
                PRT.NotesFrame:Toggle()
                refreshGates()
                return
            end
            if IsNotesFrameShown() then
                PRT.NotesFrame:Hide()
                refreshGates()
                return
            end
            PRT.Notes:ActivateNote(selectedNote, "self")
            PRT.NotesFrame:Show()
            refreshGates()
        end)

        local function PrivilegeCombatReason()
            if IsInGroup() and not PRT.Comms:IsSenderPrivileged(UnitName("player")) then
                return TOOLTIP_NO_PRIVILEGE
            end
            if InCombatLockdown() then
                return TOOLTIP_COMBAT
            end
            return nil
        end

        local function ApplyGate(button, reason)
            if reason then
                button:Disable()
                button.disabledReason = reason
            else
                button:Enable()
                button.disabledReason = nil
            end
        end

        local function HookTooltip(button)
            button:SetScript("OnEnter", function(self)
                if not self.disabledReason then
                    return
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.disabledReason, 1, 0.3, 0.3, true)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        HookTooltip(sendButton)
        HookTooltip(clearButton)
        HookTooltip(editButton)
        HookTooltip(annotateButton)
        HookTooltip(deleteButton)
        HookTooltip(activateButton)

        refreshGates = function()
            local isPrivileged = not IsInGroup() or PRT.Comms:IsSenderPrivileged(UnitName("player"))
            local inCombat = InCombatLockdown and InCombatLockdown()

            if isPrivileged then
                sendButton:Show()
                activateButton:Hide()
                local sendReason
                if inCombat then
                    sendReason = TOOLTIP_COMBAT
                elseif not selectedNote then
                    sendReason = TOOLTIP_NO_SELECTION
                end
                ApplyGate(sendButton, sendReason)
            else
                sendButton:Hide()
                activateButton:Show()
                local activateReason
                if not selectedNote then
                    activateReason = TOOLTIP_NO_SELECTION
                elseif PRT.Notes:GetActiveNoteSource() == "broadcast" then
                    activateReason = "The raid leader has set an active note."
                end
                ApplyGate(activateButton, activateReason)
            end

            local clearReason
            if isPrivileged then
                if inCombat then clearReason = TOOLTIP_COMBAT end
            else
                clearReason = TOOLTIP_NO_PRIVILEGE
            end
            ApplyGate(clearButton, clearReason)
            ApplyGate(editButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)
            ApplyGate(annotateButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)
            ApplyGate(deleteButton, not selectedNote and TOOLTIP_NO_SELECTION or nil)

            if IsNotesFrameShown() then
                showHideButton:SetText("Hide")
            else
                showHideButton:SetText("Show")
            end

            if RefreshTestNoteButton then
                RefreshTestNoteButton()
            end
        end

        testButton:SetScript("OnClick", function()
            if PRT.Notes:IsTestRunning() then
                PRT.Notes:TestStop()
            else
                PRT.Notes:TestStart()
            end
            refreshGates()
        end)
        HookTooltip(testButton)

        PRT.Notes.onTestStopped = function()
            refreshGates()
        end

        RefreshTestNoteButton = function()
            if PRT.Notes:IsTestRunning() then
                testButton:SetText("Stop")
                testButton:Enable()
                testButton.disabledReason = nil
            else
                testButton:SetText("Test")
                local activeName = CurrentActiveName()
                if activeName then
                    testButton:Enable()
                    testButton.disabledReason = nil
                else
                    testButton:Disable()
                    testButton.disabledReason = "No active note."
                end
            end
        end

        NotesConfig.OnDeleteNote = function()
            if not selectedNote then
                return
            end
            PRT.Notes:DeleteNote(selectedNote)
            selectedNote = nil
            refreshList()
            refreshGates()
        end

        local gateFrame = CreateFrame("Frame")
        gateFrame:SetScript("OnEvent", function()
            if panel:IsShown() then
                refreshList()
                refreshGates()
            end
        end)

        panel:SetScript("OnShow", function()
            gateFrame:RegisterEvent("PARTY_LEADER_CHANGED")
            gateFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
            gateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            gateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            refreshList()
            RefreshTestNoteButton()
            refreshGates()
        end)

        panel:SetScript("OnHide", function()
            gateFrame:UnregisterAllEvents()
        end)
    end

    --------------------------------------------------------------------
    -- Sub-tab: Display (display settings + Show In)
    --------------------------------------------------------------------

    local function SetupDisplay(panel)
        local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 0, 0)
        scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(panel:GetWidth() - 40)
        scrollChild:SetHeight(700)
        scrollFrame:SetScrollChild(scrollChild)

        local yOffset = -10

        local showMineCheckbox = PRT.Components.GetCheckbox(scrollChild, "Show only my assignments", function(value)
            GetSettings().display.showOnlyMine = value
            PRT:ApplySettings("notes")
        end)
        showMineCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local hideExpiredCheckbox = PRT.Components.GetCheckbox(scrollChild, "Hide expired reminders", function(value)
            GetSettings().display.hideExpired = value
            PRT:ApplySettings("notes")
        end)
        hideExpiredCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local lockedCheckbox = PRT.Components.GetCheckbox(scrollChild, "Locked", function(value)
            GetSettings().locked = value
            PRT:ApplySettings("notes")
        end)
        lockedCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local hideModeDropdown = PRT.Components.GetBasicDropdown(scrollChild, "Hide",
            function() return HIDE_MODE_OPTIONS end,
            function(value) return GetSettings().display.hideMode == value end,
            function(value)
                GetSettings().display.hideMode = value
                PRT:ApplySettings("notes")
            end)
        hideModeDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local fontDropdown = PRT.Components.GetBasicDropdown(scrollChild, "Font Face",
            ListFonts,
            function(value) return GetSettings().display.fontFace == value end,
            function(value)
                GetSettings().display.fontFace = value
                PRT:ApplySettings("notes")
            end)
        fontDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local fontSizeSlider = PRT.Components.GetSliderWithInput(scrollChild, "Font Size", 6, 32, 1, false, function(value)
            GetSettings().display.fontSize = value
            PRT:ApplySettings("notes")
        end)
        fontSizeSlider:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local outlineDropdown = PRT.Components.GetBasicDropdown(scrollChild, "Font Outline",
            function() return OUTLINE_OPTIONS end,
            function(value) return GetSettings().display.fontOutline == value end,
            function(value)
                GetSettings().display.fontOutline = value
                PRT:ApplySettings("notes")
            end)
        outlineDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local textColorPicker = PRT.Components.GetColorPicker(scrollChild, "Countdown Color", false, function(color)
            local c = GetSettings().display.countdownColor
            c.r, c.g, c.b = color.r, color.g, color.b
            PRT:ApplySettings("notes")
        end)
        textColorPicker:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local bgColorPicker = PRT.Components.GetColorPicker(scrollChild, "Background Color", false, function(color)
            local c = GetSettings().display.backgroundColor
            c.r, c.g, c.b = color.r, color.g, color.b
            PRT:ApplySettings("notes")
        end)
        bgColorPicker:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local bgOpacitySlider = PRT.Components.GetSliderWithInput(scrollChild, "Background Opacity", 0, 1, 0.05, true, function(value)
            GetSettings().display.backgroundOpacity = value
            PRT:ApplySettings("notes")
        end)
        bgOpacitySlider:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        yOffset = yOffset - 6
        local contentHeader = PRT.Components.GetHeader(scrollChild, "Show In")
        contentHeader:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - 30

        for _, info in ipairs(CONTENT_CHECKBOXES) do
            local checkbox = PRT.Components.GetCheckbox(scrollChild, info.label, function(value)
                WritePath(GetSettings(), info.path, value)
                PRT:ApplySettings("notes")
            end)
            checkbox:SetPoint("TOPLEFT", 0, yOffset)
            info.widget = checkbox
            yOffset = yOffset - ROW_HEIGHT
        end

        scrollChild:SetHeight(math.abs(yOffset) + 20)

        panel:SetScript("OnShow", function()
            local settings = GetSettings()
            showMineCheckbox:SetValue(settings.display.showOnlyMine)
            hideExpiredCheckbox:SetValue(settings.display.hideExpired)
            lockedCheckbox:SetValue(settings.locked)
            hideModeDropdown:SetValue()
            fontDropdown:SetValue()
            fontSizeSlider:SetValue(settings.display.fontSize)
            outlineDropdown:SetValue()
            textColorPicker:SetValue(settings.display.countdownColor)
            bgColorPicker:SetValue(settings.display.backgroundColor)
            bgOpacitySlider:SetValue(settings.display.backgroundOpacity)

            for _, info in ipairs(CONTENT_CHECKBOXES) do
                info.widget:SetValue(ReadPath(settings, info.path))
            end
        end)
    end

    --------------------------------------------------------------------
    -- Sub-tab: Popups
    --------------------------------------------------------------------

    local function SetupPopups(panel)
        local yOffset = -10

        local popupsCheckbox = PRT.Components.GetCheckbox(panel, "Enable popups", function(value)
            GetSettings().popups.enabled = value
            PRT:ApplySettings("notes")
        end)
        popupsCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local popupScaleSlider = PRT.Components.GetSliderWithInput(panel, "Popup Scale", 0.5, 2, 0.05, true, function(value)
            GetSettings().popups.scale = value
            PRT:ApplySettings("notes")
        end)
        popupScaleSlider:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local growDropdown = PRT.Components.GetBasicDropdown(panel, "Grow Direction",
            function() return GROW_OPTIONS end,
            function(value) return GetSettings().popups.growDirection == value end,
            function(value)
                GetSettings().popups.growDirection = value
                PRT:ApplySettings("notes")
            end)
        growDropdown:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local ttsCheckbox = PRT.Components.GetCheckbox(panel, "Enable TTS", function(value)
            GetSettings().popups.ttsEnabled = value
            PRT:ApplySettings("notes")
        end)
        ttsCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT

        local soundsCheckbox = PRT.Components.GetCheckbox(panel, "Enable sounds", function(value)
            GetSettings().popups.soundsEnabled = value
            PRT:ApplySettings("notes")
        end)
        soundsCheckbox:SetPoint("TOPLEFT", 0, yOffset)
        yOffset = yOffset - ROW_HEIGHT - 8

        local testPopupsButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        testPopupsButton:SetSize(120, 22)
        testPopupsButton:SetPoint("TOPLEFT", 0, yOffset)
        testPopupsButton:SetText("Test Popups")
        testPopupsButton:SetScript("OnClick", function()
            PRT.NotesPopups:Test()
        end)

        panel:SetScript("OnShow", function()
            local settings = GetSettings()
            popupsCheckbox:SetValue(settings.popups.enabled)
            popupScaleSlider:SetValue(settings.popups.scale)
            growDropdown:SetValue()
            ttsCheckbox:SetValue(settings.popups.ttsEnabled)
            soundsCheckbox:SetValue(settings.popups.soundsEnabled)
            if settings.popups.enabled then
                testPopupsButton:Enable()
            else
                testPopupsButton:Disable()
            end
        end)
    end

    return PRT.Components.GetSubTabGroup(parent, {
        { name = "Notes", setup = SetupNotes },
        { name = "Display", setup = SetupDisplay },
        { name = "Popups", setup = SetupPopups },
    })
end)

--------------------------------------------------------------------------------
-- Apply callback
--------------------------------------------------------------------------------

PRT:RegisterApplyCallback("notes", function()
    PRT.NotesFrame:ApplySettings()
    PRT.NotesPopups:ApplySettings()
end)
