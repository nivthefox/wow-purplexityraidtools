local PRT = PurplexityRaidTools

dofile("Modules/Attendance/AttendanceUI.lua")

local AttendanceUI = PRT.AttendanceUI
local tests = {}

tests["the manual status options include a distinct Standby choice"] = function()
    local options = AttendanceUI:GetStatusOptions()

    assertTableEquals(options, {
        { status = 3, name = "Present", letter = "P" },
        { status = 4, name = "Standby", letter = "S" },
        { status = 2, name = "Late", letter = "L" },
        { status = 1, name = "Absent", letter = "A" },
        { status = 0, name = "Missing", letter = "M" },
    })
end

return tests
