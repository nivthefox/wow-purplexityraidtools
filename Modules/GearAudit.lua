local PRT = PurplexityRaidTools
local GearAudit = {}
PRT.GearAudit = GearAudit

local SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
local ENCHANT_SLOTS = { [1] = true, [3] = true, [5] = true, [7] = true, [8] = true,
    [11] = true, [12] = true }
local WEAPON_TYPES = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true,
    INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true }
local SLOT_NAMES = { "Head", "Neck", "Shoulders", "Shirt", "Chest", "Waist", "Legs",
    "Feet", "Wrists", "Hands", "Ring 1", "Ring 2", "Trinket 1", "Trinket 2", "Back",
    "Main hand", "Off hand" }

function GearAudit.Capture(unit)
    local equipment = {}
    if not GetInventoryItemLink then
        return equipment
    end
    for _, slot in ipairs(SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            equipment[slot] = link
        elseif GetInventoryItemID and GetInventoryItemTexture
            and not GetInventoryItemID(unit, slot) and not GetInventoryItemTexture(unit, slot)
            and (UnitIsUnit(unit, "player") or slot == 17) then
            equipment[slot] = false
        end
    end
    return equipment
end

local function NewResult()
    return { status = "complete", missing = {}, unknown = {} }
end

local function RecordUnknown(result, slot)
    result.status = "unknown"
    table.insert(result.unknown, slot)
end

local function RecordMissing(result, slot, count)
    if result.status ~= "unknown" then
        result.status = "missing"
    end
    table.insert(result.missing, { slot = slot, count = count })
end

local function RequiresEnchant(slot, link)
    if ENCHANT_SLOTS[slot] then
        return true
    end
    if slot ~= 16 and slot ~= 17 then
        return false
    end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not equipLoc or equipLoc == "" then
        return nil
    end
    return WEAPON_TYPES[equipLoc] == true
end

local function AuditEnchant(result, slot, link)
    local required = RequiresEnchant(slot, link)
    if required == false then
        return
    end
    local enchant = link:match("item:%d+:([^:]*):")
    if required == nil or enchant == nil or (enchant ~= "" and not tonumber(enchant)) then
        RecordUnknown(result, slot)
    elseif enchant == "" or tonumber(enchant) == 0 then
        RecordMissing(result, slot, 1)
    end
end

local function AuditGems(result, slot, link)
    local stats = C_Item.GetItemStats(link)
    if type(stats) ~= "table" then
        RecordUnknown(result, slot)
        return false
    end
    local sockets = 0
    for stat, count in pairs(stats) do
        if stat:match("^EMPTY_SOCKET_") then
            sockets = sockets + count
        end
    end
    local missing = 0
    for index = 1, sockets do
        local gemID = C_Item.GetItemGemID(link, index)
        if not gemID or gemID == 0 then
            missing = missing + 1
        end
    end
    if missing > 0 then
        RecordMissing(result, slot, missing)
    end
    return true
end

function GearAudit.Evaluate(equipment)
    local audit = { enchants = NewResult(), gems = NewResult() }
    local pending = {}
    for _, slot in ipairs(SLOTS) do
        local link = equipment and equipment[slot]
        if link == nil then
            RecordUnknown(audit.gems, slot)
            if ENCHANT_SLOTS[slot] or slot == 16 or slot == 17 then
                RecordUnknown(audit.enchants, slot)
            end
        elseif link ~= false then
            local itemID = tonumber(link:match("item:(%d+):"))
            if not itemID or not C_Item.IsItemDataCachedByID(itemID) then
                RecordUnknown(audit.gems, slot)
                if ENCHANT_SLOTS[slot] or slot == 16 or slot == 17 then
                    RecordUnknown(audit.enchants, slot)
                end
                if itemID then
                    pending[itemID] = true
                end
            else
                AuditEnchant(audit.enchants, slot, link)
                if not AuditGems(audit.gems, slot, link) then
                    pending[itemID] = true
                end
            end
        end
    end
    return audit, pending
end

function GearAudit.GetDetails(result)
    if not result then
        return "Equipment has not been inspected yet."
    end
    local details = {}
    for _, missing in ipairs(result.missing) do
        local text = SLOT_NAMES[missing.slot]
        if missing.count > 1 then
            text = text .. " (" .. missing.count .. ")"
        end
        table.insert(details, text)
    end
    local text = #details > 0 and ("Missing: " .. table.concat(details, ", ") .. ".") or ""
    if #result.unknown > 0 then
        local unknown = {}
        for _, slot in ipairs(result.unknown) do
            table.insert(unknown, SLOT_NAMES[slot])
        end
        return text .. (#text > 0 and "\n" or "") .. "Unknown: " .. table.concat(unknown, ", ") .. "."
    end
    return #text > 0 and text or "All required enhancements are present."
end
