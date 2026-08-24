local PRT = PurplexityRaidTools
local Adapter = {}

local function GetNameStatus()
    local grid = type(Grid2) == "table" and Grid2 or nil
    if not grid or type(grid.GetStatusByName) ~= "function" then
        return nil
    end

    local status = grid:GetStatusByName("name")
    if type(status) ~= "table"
        or type(status.GetText) ~= "function"
        or type(status.UpdateDB) ~= "function"
    then
        return nil
    end
    return status
end

function Adapter:Initialize()
    if self.registered then
        return true
    end

    local status = GetNameStatus()
    if not status then
        return false
    end

    self.previousGetText = status.GetText
    self.previousUpdateDB = status.UpdateDB
    self.getText = function(nameStatus, unit)
        local nickname = PRT.RosterNicknames:ResolveUnit(unit)
        if nickname then
            return nickname
        end
        return self.previousGetText(nameStatus, unit)
    end
    self.updateDB = function(nameStatus, ...)
        self.previousUpdateDB(nameStatus, ...)
        if nameStatus.GetText ~= self.getText then
            self.previousGetText = nameStatus.GetText
        end
        nameStatus.GetText = self.getText
    end

    status.GetText = self.getText
    status.UpdateDB = self.updateDB
    self.status = status
    self.registered = true
    return true
end

function Adapter:Refresh()
    local status = self.status or GetNameStatus()
    if status and type(status.UpdateAllUnits) == "function" then
        status:UpdateAllUnits()
    end
end

PRT.RosterNicknames:RegisterAdapter("Grid2", Adapter)
