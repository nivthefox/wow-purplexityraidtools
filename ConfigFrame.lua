-- PurplexityRaidTools Config Frame
-- Modern configuration UI

local PRT = PurplexityRaidTools

local FRAME_WIDTH = 880
local FRAME_HEIGHT = 675
local ROW_HEIGHT = 32
local SECTION_SPACING = 20
local SIDEBAR_WIDTH = 125
local LABEL_WIDTH = 200
local CONTROL_MAX_WIDTH = 350

--------------------------------------------------------------------------------
-- Component Helpers
--------------------------------------------------------------------------------

local Components = {}

-- Create a checkbox with label
function Components.GetCheckbox(parent, label, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    local checkBox = CreateFrame("CheckButton", nil, holder, "SettingsCheckboxTemplate")
    checkBox:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 15, 0)
    checkBox:SetText(label)
    checkBox:SetNormalFontObject(GameFontHighlight)
    checkBox:GetFontString():SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 30, 0)
    checkBox:GetFontString():SetPoint("LEFT", holder, 20, 0)
    checkBox:GetFontString():SetJustifyH("RIGHT")

    function holder:SetValue(value)
        checkBox:SetChecked(value)
    end

    function holder:GetValue()
        return checkBox:GetChecked()
    end

    holder:SetScript("OnEnter", function()
        if checkBox.OnEnter then checkBox:OnEnter() end
    end)

    holder:SetScript("OnLeave", function()
        if checkBox.OnLeave then checkBox:OnLeave() end
    end)

    holder:SetScript("OnMouseUp", function()
        checkBox:Click()
    end)

    checkBox:SetScript("OnClick", function()
        if callback then callback(checkBox:GetChecked()) end
    end)

    return holder
end

-- Create a basic dropdown
function Components.GetBasicDropdown(parent, labelText, getItems, isSelectedCallback, onSelectionCallback)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(ROW_HEIGHT)
    frame:SetPoint("LEFT", 20, 0)
    frame:SetPoint("RIGHT", -20, 0)

    local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(200)
    dropdown:SetPoint("LEFT", frame, "LEFT", LABEL_WIDTH - 20, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", frame, "LEFT", LABEL_WIDTH - 40, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)

    dropdown:SetupMenu(function(_, rootDescription)
        local items = getItems()
        for _, item in ipairs(items) do
            rootDescription:CreateRadio(
                item.name,
                function() return isSelectedCallback(item.value) end,
                function() onSelectionCallback(item.value) end
            )
        end
    end)

    function frame:SetValue()
        dropdown:GenerateMenu()
    end

    frame.Label = label
    frame.DropDown = dropdown

    return frame
end

-- Create a slider with +/- steppers AND an input box
function Components.GetSliderWithInput(parent, labelText, min, max, step, isDecimal, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    holder.Label = holder:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    holder.Label:SetJustifyH("RIGHT")
    holder.Label:SetPoint("LEFT", 0, 0)
    holder.Label:SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 40, 0)
    holder.Label:SetText(labelText)

    -- Input box on the right
    local editBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    editBox:SetSize(50, 20)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(not isDecimal)
    editBox:SetMaxLetters(6)

    -- Slider in the middle
    holder.Slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
    holder.Slider:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 20, 0)
    holder.Slider:SetPoint("RIGHT", editBox, "LEFT", -10, 0)
    holder.Slider:SetHeight(20)

    do
        local START, RIGHT_INSET = LABEL_WIDTH - 20, 5
        local function UpdateSliderWidth(_, w)
            w = w or holder:GetWidth()
            local rightX = math.min(START + CONTROL_MAX_WIDTH, math.max(START + 50, w - RIGHT_INSET))
            editBox:SetPoint("RIGHT", holder, "LEFT", rightX, 0)
        end
        holder:SetScript("OnSizeChanged", UpdateSliderWidth)
        UpdateSliderWidth(holder, holder:GetWidth())
    end

    local numSteps = math.floor((max - min) / step)
    holder.Slider:Init(min, min, max, numSteps, {})

    local updatingFromSlider = false
    local updatingFromInput = false

    holder.Slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if updatingFromInput then return end
        updatingFromSlider = true
        if isDecimal then
            editBox:SetText(string.format("%.2f", value))
        else
            editBox:SetText(tostring(math.floor(value)))
        end
        updatingFromSlider = false
        if callback then callback(value) end
    end)

    local function ApplyInputValue()
        if updatingFromSlider then return end
        local text = editBox:GetText()
        local value = tonumber(text)
        if value then
            value = math.max(min, math.min(max, value))
            updatingFromInput = true
            holder.Slider:SetValue(value)
            updatingFromInput = false
            if callback then callback(value) end
        end
    end

    editBox:SetScript("OnEnterPressed", function(self)
        ApplyInputValue()
        self:ClearFocus()
    end)

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    editBox:SetScript("OnEditFocusLost", function()
        ApplyInputValue()
    end)

    function holder:GetValue()
        return holder.Slider.Slider:GetValue()
    end

    function holder:SetValue(value)
        updatingFromSlider = true
        holder.Slider:SetValue(value)
        if isDecimal then
            editBox:SetText(string.format("%.2f", value))
        else
            editBox:SetText(tostring(math.floor(value)))
        end
        updatingFromSlider = false
    end

    holder.EditBox = editBox

    return holder
end

-- Create a color picker
function Components.GetColorPicker(parent, labelText, hasAlpha, callback)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(ROW_HEIGHT)
    holder:SetPoint("LEFT", 20, 0)
    holder:SetPoint("RIGHT", -20, 0)

    local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", holder, "LEFT", LABEL_WIDTH - 40, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)

    local swatch = CreateFrame("Button", nil, holder, "ColorSwatchTemplate")
    swatch:SetPoint("LEFT", holder, "LEFT", LABEL_WIDTH - 15, 0)

    function holder:SetValue(color)
        swatch.currentColor = CopyTable(color)
        swatch:SetColor(CreateColor(color.r, color.g, color.b))
    end

    swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    swatch:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            local info = {}
            info.r = swatch.currentColor.r
            info.g = swatch.currentColor.g
            info.b = swatch.currentColor.b
            info.opacity = swatch.currentColor.a
            info.hasOpacity = hasAlpha

            info.swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = hasAlpha and ColorPickerFrame:GetColorAlpha() or nil
                swatch.currentColor = { r = r, g = g, b = b, a = a }
                swatch:SetColor(CreateColor(r, g, b))
                if callback then callback(swatch.currentColor) end
            end

            info.cancelFunc = function(previousValues)
                swatch.currentColor = previousValues
                swatch:SetColor(CreateColor(previousValues.r, previousValues.g, previousValues.b))
                if callback then callback(previousValues) end
            end

            info.previousValues = CopyTable(swatch.currentColor)

            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            -- Right click resets to white
            swatch.currentColor = { r = 1, g = 1, b = 1, a = hasAlpha and 1 or nil }
            swatch:SetColor(CreateColor(1, 1, 1))
            if callback then callback(swatch.currentColor) end
        end
    end)

    holder:SetScript("OnEnter", function()
        if swatch:GetScript("OnEnter") then swatch:GetScript("OnEnter")(swatch) end
    end)

    holder:SetScript("OnLeave", function()
        if swatch:GetScript("OnLeave") then swatch:GetScript("OnLeave")(swatch) end
    end)

    holder:SetScript("OnMouseUp", function(_, mouseButton)
        swatch:Click(mouseButton)
    end)

    return holder
end

-- Create a section header
function Components.GetHeader(parent, text)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetPoint("LEFT", 10, 0)
    holder:SetPoint("RIGHT", -10, 0)
    holder:SetHeight(28)

    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    holder.text:SetText(text)
    holder.text:SetPoint("LEFT", 10, 0)

    return holder
end

-- Create a tab button
function Components.GetTab(parent, text)
    local tab = CreateFrame("Button", nil, parent, "PanelTopTabButtonTemplate")
    tab:SetText(text)
    tab:SetScript("OnShow", function(self)
        PanelTemplates_TabResize(self, 15, nil, 70)
        PanelTemplates_DeselectTab(self)
    end)
    tab:GetScript("OnShow")(tab)
    return tab
end

-- Create a left-side sidebar tab button
function Components.GetSidebarTab(parent, text)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(SIDEBAR_WIDTH - 8, 28)

    btn.selectedBg = btn:CreateTexture(nil, "BACKGROUND")
    btn.selectedBg:SetAllPoints()
    btn.selectedBg:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    btn.selectedBg:Hide()

    btn.highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    btn.highlight:SetAllPoints()
    btn.highlight:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", 8, 0)
    btn.text:SetText(text)

    function btn:SetSelected(selected)
        if selected then
            btn.selectedBg:Show()
            btn.text:SetFontObject("GameFontHighlight")
        else
            btn.selectedBg:Hide()
            btn.text:SetFontObject("GameFontNormal")
        end
    end

    return btn
end

-- Create a group of top sub-tabs inside a sidebar tab's content area.
-- defs: array of { name = "Tab Name", setup = function(panel) ... end }
-- Each setup function builds its content inside the panel it is given.
-- Returns the outer container (suitable as a RegisterTab container).
local SUBTAB_HEIGHT = 24

function Components.GetSubTabGroup(parent, defs)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container:Hide()

    local subTabs = {}
    local currentIndex = 1

    local function SelectSubTab(index)
        for i, st in ipairs(subTabs) do
            if i == index then
                PanelTemplates_SelectTab(st.tab)
                st.panel:Show()
            else
                PanelTemplates_DeselectTab(st.tab)
                st.panel:Hide()
            end
        end
        currentIndex = index
    end

    for i, def in ipairs(defs) do
        local panel = CreateFrame("Frame", nil, container)
        panel:SetPoint("TOPLEFT", 0, -(SUBTAB_HEIGHT + 10))
        panel:SetPoint("BOTTOMRIGHT", 0, 0)
        panel:Hide()

        local tab = Components.GetTab(container, def.name)
        if i == 1 then
            tab:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        else
            tab:SetPoint("LEFT", subTabs[i - 1].tab, "RIGHT", 0, 0)
        end
        tab:SetScript("OnClick", function() SelectSubTab(i) end)

        table.insert(subTabs, { tab = tab, panel = panel })
        def.setup(panel)
    end

    container:SetScript("OnShow", function()
        SelectSubTab(currentIndex)
    end)

    return container
end

-- Export components for modules to use
PRT.Components = Components

--------------------------------------------------------------------------------
-- Main Config Frame
--------------------------------------------------------------------------------

local ConfigFrame = CreateFrame("Frame", "PurplexityRaidToolsConfigFrame", UIParent, "ButtonFrameTemplate")
ConfigFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
ConfigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
ConfigFrame:SetToplevel(true)
ConfigFrame:Hide()

-- Customize ButtonFrameTemplate
ButtonFrameTemplate_HidePortrait(ConfigFrame)
ButtonFrameTemplate_HideButtonBar(ConfigFrame)
ConfigFrame.Inset:Hide()
ConfigFrame:SetTitle("PurplexityRaidTools")

-- Make movable
ConfigFrame:SetMovable(true)
ConfigFrame:SetClampedToScreen(true)
ConfigFrame:EnableMouse(true)
ConfigFrame:RegisterForDrag("LeftButton")
ConfigFrame:SetScript("OnDragStart", ConfigFrame.StartMoving)
ConfigFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false)
end)

-- Add to special frames so Escape closes it
table.insert(UISpecialFrames, "PurplexityRaidToolsConfigFrame")

--------------------------------------------------------------------------------
-- Sidebar Tab System
--------------------------------------------------------------------------------

local Sidebar = CreateFrame("Frame", nil, ConfigFrame)
Sidebar:SetWidth(SIDEBAR_WIDTH)
Sidebar:SetPoint("TOPLEFT", 8, -28)
Sidebar:SetPoint("BOTTOMLEFT", 8, 8)

local sidebarBg = Sidebar:CreateTexture(nil, "BACKGROUND")
sidebarBg:SetAllPoints()
sidebarBg:SetColorTexture(0.05, 0.05, 0.05, 0.8)

local ContentArea = CreateFrame("Frame", nil, ConfigFrame)
ContentArea:SetPoint("TOPLEFT", Sidebar, "TOPRIGHT", 4, 0)
ContentArea:SetPoint("BOTTOMRIGHT", -8, 8)

local tabEntries = {}
local bottomEntries = {}
local currentEntry = nil

local bottomSeparator = Sidebar:CreateTexture(nil, "ARTWORK")
bottomSeparator:SetColorTexture(0.3, 0.3, 0.3, 0.8)
bottomSeparator:SetHeight(1)
bottomSeparator:Hide()

local function ApplySelection(entry, list)
    for _, e in ipairs(list) do
        if e == entry then
            e.button:SetSelected(true)
            e.container:Show()
        else
            e.button:SetSelected(false)
            e.container:Hide()
        end
    end
end

local function SelectTab(entry)
    ApplySelection(entry, tabEntries)
    ApplySelection(entry, bottomEntries)
    currentEntry = entry
end

local function LayoutSidebarTabs()
    for i, e in ipairs(tabEntries) do
        e.button:ClearAllPoints()
        if i == 1 then
            e.button:SetPoint("TOPLEFT", Sidebar, "TOPLEFT", 4, -8)
        else
            e.button:SetPoint("TOPLEFT", tabEntries[i - 1].button, "BOTTOMLEFT", 0, -2)
        end
    end

    -- Bottom entries stack upward from the bottom of the sidebar
    for i, e in ipairs(bottomEntries) do
        e.button:ClearAllPoints()
        if i == 1 then
            e.button:SetPoint("BOTTOMLEFT", Sidebar, "BOTTOMLEFT", 4, 8)
        else
            e.button:SetPoint("BOTTOMLEFT", bottomEntries[i - 1].button, "TOPLEFT", 0, 2)
        end
    end

    if #bottomEntries > 0 then
        local topButton = bottomEntries[#bottomEntries].button
        bottomSeparator:ClearAllPoints()
        bottomSeparator:SetPoint("BOTTOMLEFT", topButton, "TOPLEFT", 0, 5)
        bottomSeparator:SetPoint("BOTTOMRIGHT", topButton, "TOPRIGHT", 0, 5)
        bottomSeparator:Show()
    else
        bottomSeparator:Hide()
    end
end

-- Export tab system for modules (tabs are kept in alphabetical order).
-- Pass opts.bottom = true to pin a tab to the bottom of the sidebar,
-- separated from the main group.
PRT.RegisterTab = function(self, name, setupFunc, opts)
    local entry = {
        name = name,
        container = setupFunc(ContentArea),
        button = Components.GetSidebarTab(Sidebar, name),
    }
    entry.button:SetScript("OnClick", function() SelectTab(entry) end)

    if opts and opts.bottom then
        table.insert(bottomEntries, entry)
    else
        local insertAt = #tabEntries + 1
        for i, e in ipairs(tabEntries) do
            if name < e.name then
                insertAt = i
                break
            end
        end
        table.insert(tabEntries, insertAt, entry)
    end
    LayoutSidebarTabs()
end

-- Select first tab when shown
ConfigFrame:SetScript("OnShow", function()
    if #tabEntries > 0 or #bottomEntries > 0 then
        SelectTab(currentEntry or tabEntries[1] or bottomEntries[1])
    end
end)

--------------------------------------------------------------------------------
-- Placeholder content (shown when no modules registered)
--------------------------------------------------------------------------------

local placeholder = CreateFrame("Frame", nil, ContentArea)
placeholder:SetAllPoints()

local placeholderText = placeholder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
placeholderText:SetPoint("CENTER")
placeholderText:SetText("No modules loaded.\n\nModules will appear here as tabs.")

placeholder:SetScript("OnShow", function()
    if #tabEntries > 0 or #bottomEntries > 0 then
        placeholder:Hide()
    end
end)

ConfigFrame:HookScript("OnShow", function()
    if #tabEntries > 0 or #bottomEntries > 0 then
        placeholder:Hide()
    else
        placeholder:Show()
    end
end)
