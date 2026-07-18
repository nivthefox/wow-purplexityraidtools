-- tests/wow_stubs.lua
-- WoW API stubs for headless unit testing.
--
-- DO NOT stub CreateFrame or C_Timer here. Pure-logic modules must not
-- depend on UI/frame objects; leaving them nil causes accidental UI
-- dependencies to fail loudly and immediately rather than silently.
--
-- Tests can override any stub by assigning to the global directly before
-- the code-under-test runs, then restoring afterward if needed.

--------------------------------------------------------------------------------
-- Controllable clock
--------------------------------------------------------------------------------

WowStubs = { clock = 0 }

function GetTime()
    return WowStubs.clock
end

--------------------------------------------------------------------------------
-- PurplexityRaidTools namespace
--------------------------------------------------------------------------------

PurplexityRaidTools = {
    defaults  = {},
    Components = {},
    modules   = {},
}

local PRT = PurplexityRaidTools

function PRT:RegisterModule(name, tbl)
    self.modules = self.modules or {}
    self.modules[name] = tbl
end

function PRT:RegisterTab(name, fn)
    -- no-op in tests
end

function PRT:RegisterApplyCallback(name, fn)
    -- no-op in tests
end

function PRT:GetSetting(key)
    return self.defaults[key]
end

--------------------------------------------------------------------------------
-- Fake profile store
--------------------------------------------------------------------------------

PurplexityRaidTools.Profiles = {
    current = {},
    GetCurrent = function(self)
        return self.current
    end,
    GetCurrentName = function()
        return "Test"
    end,
}

--------------------------------------------------------------------------------
-- String utilities
--------------------------------------------------------------------------------

-- strsplit(sep, str [, pieces]) -> multiple return values
-- Matches WoW semantics: sep is a set of single-character delimiters, empty
-- fields are preserved ("a,,b" -> "a", "", "b"), and when pieces is given the
-- final piece contains the unsplit remainder of the string.
function strsplit(sep, str, pieces)
    local results = {}
    local escaped = sep:gsub("(%W)", "%%%1")
    local pattern = "([^" .. escaped .. "]*)([" .. escaped .. "]?)"
    local pos = 1
    while true do
        if pieces and #results == pieces - 1 then
            table.insert(results, str:sub(pos))
            break
        end
        local field, delim = str:match(pattern, pos)
        table.insert(results, field)
        if delim == "" then
            break
        end
        pos = pos + #field + #delim
    end
    return unpack(results)
end

-- strjoin(sep, ...) -> string
function strjoin(sep, ...)
    local args = { ... }
    return table.concat(args, sep)
end

-- strtrim(str) -> string  (trims leading and trailing whitespace)
function strtrim(str)
    return str:match("^%s*(.-)%s*$")
end

function strlower(str)
    return str:lower()
end

function strupper(str)
    return str:upper()
end

--------------------------------------------------------------------------------
-- Global aliases for WoW-idiomatic Lua
--------------------------------------------------------------------------------

format   = string.format
strmatch = string.match
tinsert  = table.insert
tremove  = table.remove

-- wipe(t) empties a table in-place and returns it
function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

-- tContains(t, v) returns true if any value in t equals v
function tContains(t, v)
    for _, val in pairs(t) do
        if val == v then
            return true
        end
    end
    return false
end

-- CopyTable(t) performs a deep copy
function CopyTable(t)
    if type(t) ~= "table" then
        return t
    end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = CopyTable(v)
    end
    return copy
end

--------------------------------------------------------------------------------
-- Unit / group stubs (overridable)
--------------------------------------------------------------------------------

function UnitName(unit)
    return unit, nil  -- name, realm
end

function UnitClass(unit)
    return "Warrior", "WARRIOR"  -- localised, token
end

function IsInGroup()
    return false
end

function IsInRaid()
    return false
end

-- Ambiguate(name, mode) strips "-Realm" for mode "none" or "short"
function Ambiguate(name, mode)
    if mode == "none" or mode == "short" then
        return name:match("^([^%-]+)") or name
    end
    return name
end
