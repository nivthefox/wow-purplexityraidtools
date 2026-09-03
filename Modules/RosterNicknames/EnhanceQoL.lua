local PRT = PurplexityRaidTools
local Adapter = {}

local function IsSecret(value)
    return type(issecretvalue) == "function" and issecretvalue(value)
end

local function GetGroupFrames()
    local enhanceQoL = type(EnhanceQoL) == "table" and EnhanceQoL or nil
    local aura = enhanceQoL and enhanceQoL.Aura
    local unitFrames = aura and aura.UF
    local groupFrames = unitFrames and unitFrames.GroupFrames
    if type(groupFrames) ~= "table"
        or type(groupFrames.UpdateName) ~= "function"
        or type(groupFrames.RefreshNames) ~= "function"
    then
        return nil
    end
    return groupFrames, aura.UFHelper
end

local function GetUnit(frame)
    if not frame then
        return nil
    end

    local unit
    if type(frame.GetAttribute) == "function" then
        unit = frame:GetAttribute("unit")
    end
    if unit == nil or unit == "" then
        unit = frame._eqolUnit
    end
    if IsSecret(unit) or type(unit) ~= "string" or unit == "" then
        return nil
    end
    return unit
end

local function IsSupportedFrame(frame)
    local kind = frame and frame._eqolGroupKind
    return kind == "party" or kind == "raid"
end

function Adapter:FormatNickname(groupFrames, frame, state, fontString, nickname)
    local config = frame._eqolCfg or {}
    local textConfig = config.text or {}
    local healthConfig = config.health or {}
    local noEllipsis = textConfig.nameNoEllipsis
    if noEllipsis == nil then
        noEllipsis = true
    end
    if not noEllipsis then
        return nickname
    end

    local helper = self.helper
    if type(helper) ~= "table" or type(helper.truncateTextToWidth) ~= "function" then
        return nickname
    end

    local font = textConfig.font or healthConfig.font
    local fontSize = textConfig.fontSize or healthConfig.fontSize or 12
    if type(groupFrames.ScaleContentValue) == "function" then
        fontSize = groupFrames.ScaleContentValue(frame, fontSize, config, 1)
    end
    local fontOutline = textConfig.fontOutline or healthConfig.fontOutline or "OUTLINE"
    local maximumCharacters = tonumber(textConfig.nameMaxChars) or 0
    local maximumWidth
    if maximumCharacters > 0 and type(helper.getNameLimitWidth) == "function" then
        maximumWidth = helper.getNameLimitWidth(font, fontSize, fontOutline, maximumCharacters)
    elseif maximumCharacters <= 0 then
        maximumWidth = state._eqolAutoNameTextWidth
        if not maximumWidth and type(fontString.GetWidth) == "function" then
            maximumWidth = fontString:GetWidth()
        end
    end

    if type(maximumWidth) ~= "number" or maximumWidth <= 0 then
        return nickname
    end
    return helper.truncateTextToWidth(font, fontSize, fontOutline, nickname, maximumWidth)
end

function Adapter:RestoreFrame(groupFrames, frame, state)
    if not self.appliedFrames[frame] then
        return
    end

    self.appliedFrames[frame] = nil
    state._lastName = nil
    self.previousUpdateName(groupFrames, frame)
end

function Adapter:ApplyFrame(groupFrames, frame)
    local state = frame and frame._eqolUFState
    local fontString = state and (state.nameText or state.name)
    if not state or not fontString or type(fontString.SetText) ~= "function" then
        return
    end
    if not IsSupportedFrame(frame)
        or frame._eqolPreview
        or state._wantsName == false
    then
        self:RestoreFrame(groupFrames, frame, state)
        return
    end

    local unit = GetUnit(frame)
    if not unit then
        self:RestoreFrame(groupFrames, frame, state)
        return
    end

    local nickname = PRT.RosterNicknames:ResolveUnit(unit)
    if not nickname then
        self:RestoreFrame(groupFrames, frame, state)
        return
    end

    local displayName = self:FormatNickname(groupFrames, frame, state, fontString, nickname)
    if type(UnitIsConnected) == "function" then
        local connected = UnitIsConnected(unit)
        if not IsSecret(connected) and connected == false then
            displayName = displayName .. " |cffff6666DC|r"
        end
    end
    fontString:SetText(displayName)
    self.appliedFrames[frame] = true
end

function Adapter:Initialize()
    if self.registered then
        return true
    end

    local groupFrames, helper = GetGroupFrames()
    if not groupFrames then
        return false
    end

    self.appliedFrames = self.appliedFrames or setmetatable({}, { __mode = "k" })
    self.previousUpdateName = groupFrames.UpdateName
    self.updateName = self.updateName or function(activeGroupFrames, frame, ...)
        self.previousUpdateName(activeGroupFrames, frame, ...)
        self:ApplyFrame(activeGroupFrames, frame)
    end
    groupFrames.UpdateName = self.updateName
    self.groupFrames = groupFrames
    self.helper = helper
    self.registered = true
    return true
end

function Adapter:Refresh()
    local groupFrames = self.groupFrames
    if not groupFrames or type(groupFrames.RefreshNames) ~= "function" then
        return
    end
    groupFrames:RefreshNames({ skipLayout = true })
end

PRT.RosterNicknames:RegisterAdapter("EnhanceQoL", Adapter)
