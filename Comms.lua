-- Comms: shared broadcast transport built on AceComm/LibSerialize/LibDeflate.
--
-- Headless-load safety: AceComm-3.0 and ChatThrottleLib call CreateFrame at load
-- and cannot run under the headless test harness. This file therefore looks up
-- AceComm silently (LibStub("AceComm-3.0", true)) and gates the embed/RegisterComm
-- behind its presence, so the module loads cleanly without it.

local PRT = PurplexityRaidTools

local PREFIX = "PRTools"
local VERSION = 1

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

local Comms = {}
PRT.Comms = Comms

Comms.handlers = {}

-- Injectable transport: defaults to the AceComm sender when present (set below);
-- tests replace this with a capturing function.
Comms.sendFunc = nil

--------------------------------------------------------------------------------
-- Encode / Decode
--------------------------------------------------------------------------------

function Comms:Encode(tbl)
    tbl.v = VERSION
    local serialized = LibSerialize:Serialize(tbl)
    local compressed = LibDeflate:CompressDeflate(serialized)
    return LibDeflate:EncodeForWoWAddonChannel(compressed)
end

-- Returns (true, table) on success, or (false, nil) for any non-string, empty,
-- corrupted, truncated, or wrong-version input. Never throws.
function Comms:Decode(str)
    if type(str) ~= "string" or str == "" then
        return false, nil
    end

    local decoded = LibDeflate:DecodeForWoWAddonChannel(str)
    if not decoded then
        return false, nil
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return false, nil
    end

    local ok, result = LibSerialize:Deserialize(decompressed)
    if not ok or type(result) ~= "table" then
        return false, nil
    end

    if result.v ~= VERSION then
        return false, nil
    end

    return true, result
end

--------------------------------------------------------------------------------
-- Handler registration and dispatch
--------------------------------------------------------------------------------

function Comms:RegisterHandler(msgType, fn)
    self.handlers[msgType] = fn
end

function Comms:Dispatch(encodedStr, sender)
    local ok, payload = self:Decode(encodedStr)
    if not ok then
        return
    end

    local handler = self.handlers[payload.type]
    if handler then
        handler(payload.data, sender)
    end
end

--------------------------------------------------------------------------------
-- Send via injected transport
--------------------------------------------------------------------------------

function Comms:Send(msgType, data, channel)
    local encoded = self:Encode({ type = msgType, data = data })
    if self.sendFunc then
        self.sendFunc(encoded, channel)
    end
end

--------------------------------------------------------------------------------
-- Privileged-sender check (spec 10.2.1)
--------------------------------------------------------------------------------

-- A sender is privileged when, in a raid, they are the raid leader or a raid
-- assistant; or, in a non-raid party, they are the party leader. The WoW
-- group-leader APIs key on the ambiguated (realm-stripped) unit name, so strip
-- the realm FIRST and pass the bare name to those APIs.
function Comms:IsSenderPrivileged(sender)
    local name = Ambiguate(sender, "short")

    if IsInRaid() then
        return UnitIsGroupLeader(name) or UnitIsGroupAssistant(name)
    elseif IsInGroup() then
        return UnitIsGroupLeader(name)
    end

    return false
end

--------------------------------------------------------------------------------
-- In-game AceComm wiring (gated behind AceComm's presence)
--------------------------------------------------------------------------------

-- Silent lookup: absent under the headless harness, present in-game.
local AceComm = LibStub("AceComm-3.0", true)
if AceComm then
    AceComm:Embed(Comms)

    Comms.sendFunc = function(encoded, channel)
        Comms:SendCommMessage(PREFIX, encoded, channel)
    end

    Comms:RegisterComm(PREFIX, function(_, message, _, sender)
        Comms:Dispatch(message, sender)
    end)
end
