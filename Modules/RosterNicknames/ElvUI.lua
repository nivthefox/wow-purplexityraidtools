local PRT = PurplexityRaidTools
local Adapter = {}

local function GetEngine()
    return type(ElvUI) == "table" and ElvUI[1] or nil
end

local function NormalName(engine, unit)
    local resolver = engine.TagFunctions and engine.TagFunctions.UnitName
    if type(resolver) == "function" then
        return resolver(unit)
    end
    return nil
end

local function TagValue(engine, unit, maximum)
    local nickname = PRT.RosterNicknames:ResolveUnit(unit)
    if not nickname then
        return NormalName(engine, unit)
    end
    if maximum then
        return PRT.RosterValidation:TruncateUTF8(nickname, maximum)
    end
    return nickname
end

function Adapter:Initialize()
    if self.registered then
        return true
    end

    local engine = GetEngine()
    if not engine or type(engine.AddTag) ~= "function" or type(engine.AddTagInfo) ~= "function" then
        return false
    end

    engine:AddTag("prt-roster-nickname", "UNIT_NAME_UPDATE GROUP_ROSTER_UPDATE PLAYER_ENTERING_WORLD", function(unit)
        return TagValue(engine, unit)
    end)
    engine:AddTagInfo("prt-roster-nickname", "Purplexity Raid Tools", "PRT roster nickname")

    for length = 1, PRT.RosterValidation.MAX_NICKNAME_LENGTH do
        local tagName = "prt-roster-nickname:" .. length
        local maximum = length
        engine:AddTag(tagName, "UNIT_NAME_UPDATE GROUP_ROSTER_UPDATE PLAYER_ENTERING_WORLD", function(unit)
            return TagValue(engine, unit, maximum)
        end)
        engine:AddTagInfo(tagName, "Purplexity Raid Tools", "PRT roster nickname shortened to " .. length)
    end

    self.engine = engine
    self.registered = true
    return true
end

function Adapter:Refresh()
    local engine = self.engine or GetEngine()
    if not engine or type(engine.GetModule) ~= "function" then
        return
    end
    local unitFrames = engine:GetModule("UnitFrames", true)
    if unitFrames and type(unitFrames.Update_AllFrames) == "function" then
        unitFrames:Update_AllFrames()
    end
end

PRT.RosterNicknames:RegisterAdapter("ElvUI", Adapter)
