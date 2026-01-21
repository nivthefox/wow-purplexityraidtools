-- PurplexityRaidTools Config Frame
-- Modern configuration UI

local PRT = PurplexityRaidTools

local FRAME_WIDTH = 480
local FRAME_HEIGHT = 750
local ROW_HEIGHT = 24
local SECTION_SPACING = 20

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
    checkBox:SetPoint("LEFT", holder, "CENTER", -15, 0)
    checkBox:SetText(label)
    checkBox:SetNormalFontObject(GameFontHighlight)
    checkBox:GetFontString():SetPoint("RIGHT", holder, "CENTER", -30, 0)
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
    dropdown:SetPoint("LEFT", frame, "CENTER", -20, 0)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", frame, "CENTER", -40, 0)
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
    holder.Label:SetPoint("RIGHT", holder, "CENTER", -40, 0)
    holder.Label:SetText(labelText)

    -- Input box on the right
    local editBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    editBox:SetSize(50, 20)
    editBox:SetPoint("RIGHT", -5, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(not isDecimal)
    editBox:SetMaxLetters(6)

    -- Slider in the middle
    holder.Slider = CreateFrame("Slider", nil, holder, "MinimalSliderWithSteppersTemplate")
    holder.Slider:SetPoint("LEFT", holder, "CENTER", -20, 0)
    holder.Slider:SetPoint("RIGHT", editBox, "LEFT", -10, 0)
    holder.Slider:SetHeight(20)

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

    holder:SetScript("OnMouseWheel", function(_, delta)
        if holder.Slider.Slider:IsEnabled() then
            holder.Slider:SetValue(holder.Slider.Slider:GetValue() + delta * step)
        end
    end)

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
    label:SetPoint("RIGHT", holder, "CENTER", -40, 0)
    label:SetJustifyH("RIGHT")
    label:SetText(labelText)

    local swatch = CreateFrame("Button", nil, holder, "ColorSwatchTemplate")
    swatch:SetPoint("LEFT", holder, "CENTER", -15, 0)

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
-- Tab System
--------------------------------------------------------------------------------

local tabs = {}
local tabContainers = {}
local currentTab = 1

local function SelectTab(index)
    for i, tab in ipairs(tabs) do
        if i == index then
            PanelTemplates_SelectTab(tab)
            tabContainers[i]:Show()
        else
            PanelTemplates_DeselectTab(tab)
            tabContainers[i]:Hide()
        end
    end
    currentTab = index
end

-- Export tab system for modules
PRT.RegisterTab = function(self, name, setupFunc)
    local container = setupFunc(ConfigFrame)
    table.insert(tabContainers, container)

    local tab = Components.GetTab(ConfigFrame, name)
    if #tabs == 0 then
        tab:SetPoint("TOPLEFT", ConfigFrame, "TOPLEFT", 10, -25)
    else
        tab:SetPoint("LEFT", tabs[#tabs], "RIGHT", 0, 0)
    end
    local tabIndex = #tabs + 1
    tab:SetScript("OnClick", function() SelectTab(tabIndex) end)
    table.insert(tabs, tab)
end

-- Select first tab when shown
ConfigFrame:SetScript("OnShow", function()
    if #tabs > 0 then
        SelectTab(currentTab)
    end
end)

--------------------------------------------------------------------------------
-- Placeholder content (shown when no modules registered)
--------------------------------------------------------------------------------

local placeholder = CreateFrame("Frame", nil, ConfigFrame)
placeholder:SetPoint("TOPLEFT", 8, -60)
placeholder:SetPoint("BOTTOMRIGHT", -8, 8)

local placeholderText = placeholder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
placeholderText:SetPoint("CENTER")
placeholderText:SetText("No modules loaded.\n\nModules will appear here as tabs.")

placeholder:SetScript("OnShow", function()
    if #tabs > 0 then
        placeholder:Hide()
    end
end)

ConfigFrame:HookScript("OnShow", function()
    if #tabs > 0 then
        placeholder:Hide()
    else
        placeholder:Show()
    end
end)
