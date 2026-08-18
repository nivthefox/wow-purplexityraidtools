local PRT = PurplexityRaidTools
local Adapter = {}

local function GetPartyMemberFramePool()
    local pool = PartyFrame and PartyFrame.PartyMemberFramePool
    if not pool or type(pool.EnumerateActive) ~= "function" then
        return nil
    end
    return pool
end

local function UnitForPartyMemberFrame(frame)
    local pool = GetPartyMemberFramePool()
    if not pool then
        return nil
    end

    for memberFrame in pool:EnumerateActive() do
        if memberFrame == frame then
            local unit = type(frame.GetUnit) == "function" and frame:GetUnit() or frame.unit
            if type(unit) == "string" and string.match(unit, "^party%d+$") then
                return unit
            end
            return nil
        end
    end
    return nil
end

local function UnitForFrame(frame)
    if not frame then
        return nil
    end
    if frame == PlayerFrame then
        return "player"
    end
    if frame == TargetFrame then
        return "target"
    end
    if frame == TargetFrameToT then
        return "targettarget"
    end
    if frame == FocusFrame then
        return "focus"
    end
    local partyUnit = UnitForPartyMemberFrame(frame)
    if partyUnit then
        return partyUnit, true
    end
    return nil
end

local function CompactUnitIsSupported(frame)
    local unit = frame and frame.unit
    if type(unit) ~= "string" then
        return false
    end
    if string.match(unit, "^party%d+$") or string.match(unit, "^raid%d+$") then
        return true
    end
    return unit == "player" and frame == CompactPartyFrameMember1
end

function Adapter:ApplyUnitFrame(frame)
    local unit = UnitForFrame(frame)
    if not unit or not frame.name or type(frame.name.SetText) ~= "function" then
        return
    end

    local nickname = PRT.RosterNicknames:ResolveUnit(unit)
    if nickname then
        frame.name:SetText(nickname)
    end
end

function Adapter:ApplyCompactFrame(frame)
    if not CompactUnitIsSupported(frame) or not frame.name
        or type(frame.name.SetText) ~= "function" then
        return
    end

    local nickname = PRT.RosterNicknames:ResolveUnit(frame.unit)
    if nickname then
        frame.name:SetText(nickname)
    end
end

local function RefreshUnitFrame(frame)
    local unit, isParty = UnitForFrame(frame)
    if not unit or not frame.name or type(frame.name.SetText) ~= "function"
        or type(GetUnitName) ~= "function" then
        return
    end

    local name = GetUnitName(unit, isParty == true)
    if not name then
        return
    end

    frame.name:SetText(name)
    Adapter:ApplyUnitFrame(frame)
end

function Adapter:Initialize()
    if self.registered or type(hooksecurefunc) ~= "function" then
        return self.registered == true
    end

    if not self.unitUpdateHooked and type(UnitFrame_Update) == "function" then
        hooksecurefunc("UnitFrame_Update", function(frame)
            self:ApplyUnitFrame(frame)
        end)
        self.unitUpdateHooked = true
    end
    if not self.unitEventHooked and type(UnitFrame_OnEvent) == "function" then
        hooksecurefunc("UnitFrame_OnEvent", function(frame)
            self:ApplyUnitFrame(frame)
        end)
        self.unitEventHooked = true
    end
    if not self.compactHooked and type(CompactUnitFrame_UpdateName) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            self:ApplyCompactFrame(frame)
        end)
        self.compactHooked = true
    end

    self.registered = self.unitUpdateHooked and self.unitEventHooked and self.compactHooked
    return self.registered == true
end

function Adapter:Refresh()
    RefreshUnitFrame(PlayerFrame)
    RefreshUnitFrame(TargetFrame)
    RefreshUnitFrame(TargetFrameToT)
    RefreshUnitFrame(FocusFrame)

    local partyMemberFramePool = GetPartyMemberFramePool()
    if partyMemberFramePool then
        for frame in partyMemberFramePool:EnumerateActive() do
            RefreshUnitFrame(frame)
        end
    end

    if type(CompactUnitFrame_UpdateName) ~= "function" then
        return
    end
    for index = 1, 5 do
        local frame = _G["CompactPartyFrameMember" .. index]
        if frame then CompactUnitFrame_UpdateName(frame) end
    end
    if CompactRaidFrameContainer and type(CompactRaidFrameContainer.ApplyToFrames) == "function" then
        CompactRaidFrameContainer:ApplyToFrames("normal", function(frame)
            CompactUnitFrame_UpdateName(frame)
        end)
    elseif CompactRaidFrameContainer and type(CompactRaidFrameContainer_ApplyToFrames) == "function" then
        CompactRaidFrameContainer_ApplyToFrames(CompactRaidFrameContainer, "normal", CompactUnitFrame_UpdateName)
    end
end

PRT.RosterNicknames:RegisterAdapter("Blizzard", Adapter)
