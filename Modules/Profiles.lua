-- Profiles: Config tab and dialogs for managing settings profiles
local PRT = PurplexityRaidTools

--------------------------------------------------------------------------------
-- Config UI
--------------------------------------------------------------------------------

PRT:RegisterTab("Profiles", function(parent)
    local container = CreateFrame("Frame", nil, parent)
    container:SetAllPoints()
    container:Hide()

    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(container:GetWidth() - 40)
    scrollChild:SetHeight(200)
    scrollFrame:SetScrollChild(scrollChild)

    local yOffset = 0
    local ROW_HEIGHT = 24

    -- Profile Section
    local profileHeader = PRT.Components.GetHeader(scrollChild, "Profile")
    profileHeader:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - 28

    local profileDropdown = PRT.Components.GetBasicDropdown(
        scrollChild,
        "Active Profile:",
        function()
            local items = {}
            for _, name in ipairs(PRT.Profiles:GetNames()) do
                table.insert(items, { name = name, value = name })
            end
            return items
        end,
        function(value)
            return PRT.Profiles:GetCurrentName() == value
        end,
        function(value)
            PRT.Profiles:Switch(value)
        end
    )
    profileDropdown:SetPoint("TOPLEFT", 0, yOffset)
    yOffset = yOffset - ROW_HEIGHT

    -- Create/Clone/Delete buttons
    local buttonHolder = CreateFrame("Frame", nil, scrollChild)
    buttonHolder:SetPoint("TOPLEFT", 20, yOffset)
    buttonHolder:SetSize(400, 30)

    local createButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    createButton:SetSize(80, 22)
    createButton:SetPoint("LEFT", 0, 0)
    createButton:SetText("New")
    createButton:SetScript("OnClick", function()
        StaticPopup_Show("PRT_CREATE_PROFILE")
    end)

    local cloneButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    cloneButton:SetSize(80, 22)
    cloneButton:SetPoint("LEFT", createButton, "RIGHT", 5, 0)
    cloneButton:SetText("Clone")
    cloneButton:SetScript("OnClick", function()
        StaticPopup_Show("PRT_CLONE_PROFILE")
    end)

    local deleteButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    deleteButton:SetSize(80, 22)
    deleteButton:SetPoint("LEFT", cloneButton, "RIGHT", 5, 0)
    deleteButton:SetText("Delete")
    deleteButton:SetScript("OnClick", function()
        local currentName = PRT.Profiles:GetCurrentName()
        if currentName == "Default" then
            print("|cFFFF0000PurplexityRaidTools:|r Cannot delete the Default profile.")
            return
        end
        StaticPopup_Show("PRT_DELETE_PROFILE", currentName)
    end)

    local renameButton = CreateFrame("Button", nil, buttonHolder, "UIPanelButtonTemplate")
    renameButton:SetSize(80, 22)
    renameButton:SetPoint("LEFT", deleteButton, "RIGHT", 5, 0)
    renameButton:SetText("Rename")
    renameButton:SetScript("OnClick", function()
        local currentName = PRT.Profiles:GetCurrentName()
        StaticPopup_Show("PRT_RENAME_PROFILE", currentName)
    end)

    return container
end, { bottom = true })

--------------------------------------------------------------------------------
-- Profile Dialogs
--------------------------------------------------------------------------------

StaticPopupDialogs["PRT_CREATE_PROFILE"] = {
    text = "Enter a name for the new profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        if name and name ~= "" then
            if PRT.Profiles:Create(name) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Created and switched to profile: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        if name and name ~= "" then
            if PRT.Profiles:Create(name) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Created and switched to profile: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PRT_CLONE_PROFILE"] = {
    text = "Enter a name for the cloned profile:",
    button1 = "Clone",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local name = self.editBox:GetText()
        local currentName = PRT.Profiles:GetCurrentName()
        if name and name ~= "" then
            if PRT.Profiles:Create(name, currentName) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Cloned profile to: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local name = self:GetText()
        local currentName = PRT.Profiles:GetCurrentName()
        if name and name ~= "" then
            if PRT.Profiles:Create(name, currentName) then
                PRT.Profiles:Switch(name)
                print("|cFF00FF00PurplexityRaidTools:|r Cloned profile to: " .. name)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Profile already exists: " .. name)
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["PRT_DELETE_PROFILE"] = {
    text = "Are you sure you want to delete the profile '%s'?",
    button1 = "Delete",
    button2 = "Cancel",
    OnAccept = function(self, data)
        local currentName = PRT.Profiles:GetCurrentName()
        PRT.Profiles:Switch("Default")
        if PRT.Profiles:Delete(currentName) then
            print("|cFF00FF00PurplexityRaidTools:|r Deleted profile: " .. currentName)
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

StaticPopupDialogs["PRT_RENAME_PROFILE"] = {
    text = "Enter a new name for profile '%s':",
    button1 = "Rename",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local newName = self.editBox:GetText()
        local oldName = PRT.Profiles:GetCurrentName()
        if newName and newName ~= "" then
            if PRT.Profiles:Rename(oldName, newName) then
                print("|cFF00FF00PurplexityRaidTools:|r Renamed profile to: " .. newName)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Could not rename profile. Name may already exist.")
            end
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        local newName = self:GetText()
        local oldName = PRT.Profiles:GetCurrentName()
        if newName and newName ~= "" then
            if PRT.Profiles:Rename(oldName, newName) then
                print("|cFF00FF00PurplexityRaidTools:|r Renamed profile to: " .. newName)
            else
                print("|cFFFF0000PurplexityRaidTools:|r Could not rename profile. Name may already exist.")
            end
        end
        parent:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
