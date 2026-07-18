-- tests/run_tests.lua
-- Headless test runner for PurplexityRaidTools pure-logic modules.
--
-- Invocation (from addon root):
--   luajit tests/run_tests.lua
--   C:\Users\kevin\AppData\Local\Programs\LuaJIT\bin\luajit.exe tests/run_tests.lua
--
-- Each tests/test_*.lua file must return a table of the form:
--   { ["test name"] = function() ... end }
-- Tests pass by returning normally; they fail by calling error().
-- Global assert helpers are injected before any test file is loaded.

--------------------------------------------------------------------------------
-- Determine paths
--------------------------------------------------------------------------------

-- arg[0] is the script path as passed on the command line
-- (e.g. "tests/run_tests.lua" when run from the addon root).
local scriptPath = arg[0] or "tests/run_tests.lua"
-- Strip the filename to get the tests directory.
local testsDir = scriptPath:match("^(.*)[/\\][^/\\]+$") or "."

local addonRoot = testsDir:match("^(.*)[/\\][^/\\]+$") or "."

--------------------------------------------------------------------------------
-- Small table serializer (used in failure messages)
--------------------------------------------------------------------------------

local function serialize(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "nil" then
        return "nil"
    elseif t == "boolean" then
        return tostring(v)
    elseif t == "number" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        if depth > 4 then
            return "{...}"
        end
        local parts = {}
        -- array portion
        local maxN = 0
        for i, _ in ipairs(v) do
            maxN = i
        end
        for i = 1, maxN do
            parts[#parts + 1] = serialize(v[i], depth + 1)
        end
        -- hash portion
        for k, val in pairs(v) do
            if type(k) ~= "number" or k < 1 or k > maxN then
                parts[#parts + 1] = string.format("[%s]=%s",
                    serialize(k, depth + 1), serialize(val, depth + 1))
            end
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return "<" .. t .. ">"
    end
end

--------------------------------------------------------------------------------
-- Assert helpers (injected as globals before test files load)
--------------------------------------------------------------------------------

function assertEquals(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%sexpected %s, got %s",
            msg and (msg .. ": ") or "",
            serialize(expected),
            serialize(actual)), 2)
    end
end

function assertNear(actual, expected, eps, msg)
    if math.abs(actual - expected) > eps then
        error(string.format("%sexpected %s near %s (eps %s), got %s",
            msg and (msg .. ": ") or "",
            serialize(expected),
            serialize(expected),
            serialize(eps),
            serialize(actual)), 2)
    end
end

function assertTrue(v, msg)
    if not v then
        error(string.format("%sexpected true, got %s",
            msg and (msg .. ": ") or "",
            serialize(v)), 2)
    end
end

function assertFalse(v, msg)
    if v then
        error(string.format("%sexpected false, got %s",
            msg and (msg .. ": ") or "",
            serialize(v)), 2)
    end
end

function assertNil(v, msg)
    if v ~= nil then
        error(string.format("%sexpected nil, got %s",
            msg and (msg .. ": ") or "",
            serialize(v)), 2)
    end
end

function assertNotNil(v, msg)
    if v == nil then
        error(string.format("%sexpected non-nil value%s",
            msg and (msg .. ": ") or "",
            ""), 2)
    end
end

-- assertTableEquals: deep equality.
-- Array portions are compared order-sensitively; hash keys are order-insensitive.
local function tableEquals(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    -- Check all keys in a exist and match in b
    for k, v in pairs(a) do
        if not tableEquals(v, b[k]) then
            return false
        end
    end
    -- Check b has no extra keys
    for k, _ in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

function assertTableEquals(actual, expected, msg)
    if not tableEquals(actual, expected) then
        error(string.format("%sexpected %s, got %s",
            msg and (msg .. ": ") or "",
            serialize(expected),
            serialize(actual)), 2)
    end
end

function assertError(fn, msg)
    local ok = pcall(fn)
    if ok then
        error(string.format("%sexpected an error but none was raised",
            msg and (msg .. ": ") or ""), 2)
    end
end

--------------------------------------------------------------------------------
-- Load stubs
--------------------------------------------------------------------------------

local stubsPath = testsDir .. "/wow_stubs.lua"
local ok, err = pcall(dofile, stubsPath)
if not ok then
    io.stderr:write("FATAL: could not load wow_stubs.lua: " .. tostring(err) .. "\n")
    os.exit(1)
end

--------------------------------------------------------------------------------
-- Discover test files
--------------------------------------------------------------------------------

local function discoverTestFiles(dir)
    local files = {}
    -- Try Windows dir first, fall back to POSIX ls
    local cmd
    local handle = io.popen('dir /b "' .. dir .. '" 2>nul')
    if handle then
        local output = handle:read("*a")
        handle:close()
        if output and output ~= "" then
            for name in output:gmatch("[^\r\n]+") do
                if name:match("^test_.*%.lua$") then
                    files[#files + 1] = name
                end
            end
        end
    end
    -- Fall back to ls if nothing found
    if #files == 0 then
        handle = io.popen('ls "' .. dir .. '"')
        if handle then
            local output = handle:read("*a")
            handle:close()
            for name in output:gmatch("[^\r\n]+") do
                if name:match("^test_.*%.lua$") then
                    files[#files + 1] = name
                end
            end
        end
    end
    table.sort(files)
    return files
end

local testFiles = discoverTestFiles(testsDir)

--------------------------------------------------------------------------------
-- Run tests
--------------------------------------------------------------------------------

local totalPassed = 0
local totalFailed = 0

for _, filename in ipairs(testFiles) do
    local filepath = testsDir .. "/" .. filename
    local chunk, loadErr = loadfile(filepath)
    if not chunk then
        print(string.format("FAIL %s: (load error) %s", filename, tostring(loadErr)))
        totalFailed = totalFailed + 1
    else
        local runOk, result = pcall(chunk)
        if not runOk then
            print(string.format("FAIL %s: (runtime error) %s", filename, tostring(result)))
            totalFailed = totalFailed + 1
        elseif type(result) ~= "table" then
            print(string.format("FAIL %s: test file did not return a table", filename))
            totalFailed = totalFailed + 1
        else
            -- Collect and sort test names
            local names = {}
            for name, _ in pairs(result) do
                names[#names + 1] = name
            end
            table.sort(names)

            for _, name in ipairs(names) do
                local fn = result[name]
                local testOk, testErr = pcall(fn)
                if testOk then
                    print(string.format("PASS %s:%s", filename, name))
                    totalPassed = totalPassed + 1
                else
                    print(string.format("FAIL %s:%s\n  %s", filename, name, tostring(testErr)))
                    totalFailed = totalFailed + 1
                end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Summary
--------------------------------------------------------------------------------

print(string.format("\n%d passed, %d failed", totalPassed, totalFailed))

if totalFailed > 0 then
    os.exit(1)
else
    os.exit(0)
end
