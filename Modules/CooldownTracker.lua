local PRT = PurplexityRaidTools
local CooldownTracker = {}
PRT.CooldownTracker = CooldownTracker

local DURATION_TOLERANCE = 0.25
local DURATION_CONFIDENT_DIFF = 0.50
local EVIDENCE_WINDOW = 0.05
local RALLY_INCREASE_LOW = 0.13
local RALLY_INCREASE_HIGH = 0.17
local RALLY_END_TOLERANCE = 0.03
local DEVOTION_AURA_ID = 465
local PAIN_SUPP_CHARGE_TALENT = 373035
local AURA_MASTERY_ID = 31821
local RALLYING_CRY_ID = 97462

local DURATION_FIXED = 1
local DURATION_LTE   = 2
local DURATION_GTE   = 3

local TARGET_OTHERS = 2
local TARGET_ANY    = 3

local TRACKED_ABILITIES = {
    [33206]  = {
        baseCooldown = 180, activeDuration = 8, method = "external", baseCharges = 1,
        BIG = true, EXTERNAL = true, RAIDINCOMBAT = true,
        durationMode = DURATION_FIXED, targets = TARGET_ANY,
    },
    [47788]  = {
        baseCooldown = 180, activeDuration = 10, method = "external", baseCharges = 1,
        BIG = true, EXTERNAL = true, RAIDINCOMBAT = true,
        durationMode = DURATION_FIXED, targets = TARGET_ANY,
    },
    [102342] = {
        baseCooldown = 90, activeDuration = 12, method = "external", baseCharges = 1,
        BIG = true, EXTERNAL = true, RAIDINCOMBAT = true,
        durationMode = DURATION_FIXED, targets = TARGET_ANY,
    },
    [6940]   = {
        baseCooldown = 120, activeDuration = 12, method = "external", baseCharges = 1,
        BIG = true, EXTERNAL = true, RAIDINCOMBAT = true,
        durationMode = DURATION_LTE, targets = TARGET_OTHERS,
    },
    [357170] = {
        baseCooldown = 60, activeDuration = 8, method = "external", baseCharges = 1,
        BIG = true, EXTERNAL = true, RAIDINCOMBAT = true,
        durationMode = DURATION_FIXED, targets = TARGET_ANY,
    },
    [53480]  = {
        baseCooldown = 60, activeDuration = 12, method = "external", baseCharges = 1,
        BIG = true, EXTERNAL = true, RAIDINCOMBAT = true,
        durationMode = DURATION_FIXED, targets = TARGET_ANY,
    },
    [AURA_MASTERY_ID] = {
        baseCooldown = 180, activeDuration = 8, method = "auraMastery", baseCharges = 1,
    },
    [RALLYING_CRY_ID] = {
        baseCooldown = 180, activeDuration = 10, method = "rallyingCry", baseCharges = 1,
    },
}

local abilityState = {}
local rosterAbilities = {}
local rosterOrder = {}
local chargeOverrides = {}
local pendingAuras = {}
local devotionAuraMap = {}
local auraMasteryActive = {}
local baseMaxHP = 0
local rallyActive = false
local rallyStartTime = 0
local rallyAttributedGUID = nil
local castEvidence = {}
local myGUID = nil
local inCombat = false
local eventFrame = nil


local function chargeCountFor(guid, spellId)
    if chargeOverrides[guid] and chargeOverrides[guid][spellId] then
        return chargeOverrides[guid][spellId]
    end
    local ability = TRACKED_ABILITIES[spellId]
    return ability and ability.baseCharges or 1
end

local function initAbilityState(guid, spellId)
    if not abilityState[guid] then
        abilityState[guid] = {}
    end
    local charges = chargeCountFor(guid, spellId)
    abilityState[guid][spellId] = {
        state = "ready",
        castTime = 0,
        activeEndTime = 0,
        cooldownEndTime = 0,
        chargeCount = charges,
        chargeTimers = {},
        availableCharges = charges,
    }
end

local function ensureAbilityState(guid, spellId)
    if not abilityState[guid] or not abilityState[guid][spellId] then
        initAbilityState(guid, spellId)
    end
    return abilityState[guid][spellId]
end


local function countAvailableCharges(info)
    if info.chargeCount <= 1 then return end
    local now = GetTime()
    local available = info.chargeCount
    for i = 1, #info.chargeTimers do
        if info.chargeTimers[i] > now then
            available = available - 1
        end
    end
    info.availableCharges = available
end

local function latestChargeTimer(info)
    local latest = 0
    for i = 1, #info.chargeTimers do
        if info.chargeTimers[i] > latest then
            latest = info.chargeTimers[i]
        end
    end
    return latest
end

local function soonestChargeTimer(info)
    local now = GetTime()
    local soonest = math.huge
    for i = 1, #info.chargeTimers do
        if info.chargeTimers[i] > now and info.chargeTimers[i] < soonest then
            soonest = info.chargeTimers[i]
        end
    end
    return soonest
end

local function pushChargeTimer(info, ability)
    local now = GetTime()
    local rechargeEnd = math.max(latestChargeTimer(info) + ability.baseCooldown, now + ability.baseCooldown)
    table.insert(info.chargeTimers, rechargeEnd)
    countAvailableCharges(info)
end


local function markReady(guid, spellId)
    local info = abilityState[guid] and abilityState[guid][spellId]
    if not info then return end
    info.state = "ready"
    info.castTime = 0
    info.activeEndTime = 0
    info.cooldownEndTime = 0
end

local function markCooldown(guid, spellId)
    local info = abilityState[guid] and abilityState[guid][spellId]
    if not info then return end
    if info.state ~= "active" then return end

    local ability = TRACKED_ABILITIES[spellId]
    if not ability then return end

    if info.chargeCount > 1 then
        countAvailableCharges(info)
        if info.availableCharges > 0 then
            info.state = "ready"
            return
        end
    end

    info.state = "cooldown"
end

local function markActive(guid, spellId)
    local ability = TRACKED_ABILITIES[spellId]
    if not ability then return end

    local info = ensureAbilityState(guid, spellId)
    local now = GetTime()

    if info.chargeCount > 1 then
        pushChargeTimer(info, ability)
    end

    info.state = "active"
    info.castTime = now
    info.activeEndTime = now + ability.activeDuration
    info.cooldownEndTime = now + ability.baseCooldown
end

local function isAvailable(guid, spellId)
    local info = ensureAbilityState(guid, spellId)
    if info.chargeCount > 1 then
        countAvailableCharges(info)
        return info.availableCharges > 0
    end
    return info.state == "ready"
end

local function firstAvailableCaster(spellId)
    for _, entry in ipairs(rosterOrder) do
        if entry.spellId == spellId and isAvailable(entry.guid, spellId) then
            return entry.guid
        end
    end
    return nil
end

local function expireStaleStates()
    local now = GetTime()
    for guid, abilities in pairs(abilityState) do
        for spellId, info in pairs(abilities) do
            if info.state == "active" and now >= info.activeEndTime then
                markCooldown(guid, spellId)
            end

            if info.state == "cooldown" then
                local expired = false
                if info.chargeCount > 1 then
                    countAvailableCharges(info)
                    expired = info.availableCharges > 0
                else
                    expired = now >= info.cooldownEndTime
                end
                if expired then
                    markReady(guid, spellId)
                end
            end
        end
    end
end


local function readAuraFlags(unit, auraInstanceId)
    local function hasFlag(filter)
        return not C_UnitAuras.IsAuraFilteredOutByInstanceID(unit, auraInstanceId, filter)
    end
    return {
        BIG          = hasFlag("HELPFUL|BIG_DEFENSIVE"),
        EXTERNAL     = hasFlag("HELPFUL|EXTERNAL_DEFENSIVE"),
        RAIDINCOMBAT = hasFlag("HELPFUL|RAID_IN_COMBAT"),
    }
end

local function flagsMatch(auraFlags, ability)
    return auraFlags.BIG == ability.BIG
       and auraFlags.EXTERNAL == ability.EXTERNAL
       and auraFlags.RAIDINCOMBAT == ability.RAIDINCOMBAT
end

local function durationOutOfRange(measuredDuration, ability, isExpired)
    if not measuredDuration then
        return false, 0
    end
    local diff = math.abs(measuredDuration - ability.activeDuration)
    local mode = isExpired and ability.durationMode or DURATION_LTE

    if mode == DURATION_FIXED and diff > DURATION_TOLERANCE then
        return true, diff
    end
    if mode == DURATION_LTE and diff > DURATION_TOLERANCE and measuredDuration > ability.activeDuration then
        return true, diff
    end
    if mode == DURATION_GTE and diff > DURATION_TOLERANCE and measuredDuration < ability.activeDuration then
        return true, diff
    end
    return false, diff
end

local function canTargetUnit(ability, casterGUID, targetGUID)
    if ability.targets == TARGET_OTHERS and casterGUID == targetGUID then
        return false
    end
    return true
end

local function castEvidenceDiff(guid, spellId, eventTime)
    if guid ~= myGUID then
        return math.huge
    end
    local castTime = castEvidence[spellId]
    if not castTime then
        return math.huge
    end
    return math.abs(eventTime - castTime)
end

local function buildCandidate(entry, auraFlags, targetGUID, eventTime, measuredDuration, isExpired)
    local ability = TRACKED_ABILITIES[entry.spellId]
    if not ability then return nil end
    if ability.method ~= "external" then return nil end
    if not flagsMatch(auraFlags, ability) then return nil end
    if not isAvailable(entry.guid, entry.spellId) then return nil end

    local outOfRange, durDiff = durationOutOfRange(measuredDuration, ability, isExpired)
    if outOfRange then return nil end

    if not canTargetUnit(ability, entry.guid, targetGUID) then return nil end

    return {
        spellId = entry.spellId,
        casterGUID = entry.guid,
        castTimeDiff = castEvidenceDiff(entry.guid, entry.spellId, eventTime),
        durationDiff = isExpired and durDiff or 0,
    }
end

local function findCandidates(auraFlags, targetGUID, eventTime, measuredDuration, isExpired)
    local candidates = {}
    for _, entry in ipairs(rosterOrder) do
        local candidate = buildCandidate(entry, auraFlags, targetGUID, eventTime, measuredDuration, isExpired)
        if candidate then
            table.insert(candidates, candidate)
        end
    end
    return candidates
end


local function resolveIfSingle(candidates)
    if #candidates ~= 1 then
        return nil
    end
    return candidates[1]
end

local function resolveByClosestCast(candidates)
    if #candidates < 2 then return nil end

    table.sort(candidates, function(a, b) return a.castTimeDiff < b.castTimeDiff end)
    local best = candidates[1]
    local runnerUp = candidates[2]

    if best.castTimeDiff == 0 and runnerUp.castTimeDiff > 0 then
        return best
    end
    return nil
end

local function resolveByClosestDuration(candidates)
    if #candidates < 2 then return nil end

    table.sort(candidates, function(a, b) return a.durationDiff < b.durationDiff end)
    local best = candidates[1]
    local runnerUp = candidates[2]

    if (runnerUp.durationDiff - best.durationDiff) >= DURATION_CONFIDENT_DIFF then
        return best
    end
    return nil
end

local function resolveMatch(candidates)
    if #candidates == 0 then
        return nil
    end
    return resolveIfSingle(candidates)
        or resolveByClosestCast(candidates)
        or resolveByClosestDuration(candidates)
end


local function identify(pending)
    local candidates = findCandidates(
        pending.auraFlags,
        pending.targetGUID,
        pending.startTime,
        pending.measuredDuration,
        pending.expired
    )
    return resolveMatch(candidates)
end

local function clearPriorAttribution(pending, match)
    if not pending.attributedGUID then return end
    if not pending.attributedSpellId then return end

    local sameGUID = pending.attributedGUID == match.casterGUID
    local sameSpell = pending.attributedSpellId == match.spellId
    if sameGUID and sameSpell then return end

    markReady(pending.attributedGUID, pending.attributedSpellId)
end

local function attribute(pending, match)
    clearPriorAttribution(pending, match)

    pending.attributedGUID = match.casterGUID
    pending.attributedSpellId = match.spellId
    pending.certain = true

    local info = ensureAbilityState(match.casterGUID, match.spellId)
    if info.state == "ready" then
        markActive(match.casterGUID, match.spellId)
    end
end

local function attributeUncertain(pending, match)
    pending.attributedSpellId = match.spellId
    pending.attributedGUID = match.casterGUID
    markActive(match.casterGUID, match.spellId)
end

local function tryIdentifyAndAttribute(pending)
    local match = identify(pending)
    if not match then return end
    attribute(pending, match)
end

local function tryDeferredIdentify(pending, auraInstanceId)
    C_Timer.After(EVIDENCE_WINDOW + 0.01, function()
        local p = pendingAuras[auraInstanceId]
        if not p then return end
        if p.certain then return end

        local match = identify(p)
        if not match then return end

        if resolveIfSingle(findCandidates(p.auraFlags, p.targetGUID, p.startTime, p.measuredDuration, p.expired)) then
            attribute(p, match)
            return
        end

        if not p.attributedGUID then
            attributeUncertain(p, match)
        end
    end)
end


local function onDefensiveGained(unit, auraInstanceId)
    local auraFlags = readAuraFlags(unit, auraInstanceId)
    if not auraFlags.BIG and not auraFlags.EXTERNAL then
        return
    end

    local pending = {
        auraInstanceId = auraInstanceId,
        targetUnit = unit,
        targetGUID = UnitGUID(unit),
        startTime = GetTime(),
        auraFlags = auraFlags,
        measuredDuration = nil,
        expired = false,
        attributedSpellId = nil,
        attributedGUID = nil,
        certain = false,
    }
    pendingAuras[auraInstanceId] = pending

    local match = identify(pending)
    if match then
        if resolveIfSingle(findCandidates(pending.auraFlags, pending.targetGUID, pending.startTime, nil, false)) then
            attribute(pending, match)
        else
            attributeUncertain(pending, match)
        end
    end

    tryDeferredIdentify(pending, auraInstanceId)
end

local function onDefensiveLost(auraInstanceId)
    local pending = pendingAuras[auraInstanceId]
    if not pending then return end

    pending.measuredDuration = GetTime() - pending.startTime
    pending.expired = true

    if not pending.certain then
        tryIdentifyAndAttribute(pending)
    end

    if pending.attributedGUID and pending.attributedSpellId then
        markCooldown(pending.attributedGUID, pending.attributedSpellId)
    end

    pendingAuras[auraInstanceId] = nil
end


local function scanDevotionAuras()
    devotionAuraMap = {}
    local seenPaladins = {}

    for unit in PRT:IterateGroup() do
        local i = 1
        while true do
            local auraData = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
            if not auraData then break end

            if auraData.spellId == DEVOTION_AURA_ID and auraData.sourceUnit then
                local paladinGUID = UnitGUID(auraData.sourceUnit)
                if paladinGUID and not seenPaladins[paladinGUID] then
                    seenPaladins[paladinGUID] = true
                    devotionAuraMap[auraData.auraInstanceID] = paladinGUID
                end
            end
            i = i + 1
        end
    end
end

local function onDevotionAuraChanged(auraInstanceId)
    local paladinGUID = devotionAuraMap[auraInstanceId]
    if not paladinGUID then return end
    if not rosterAbilities[paladinGUID] then return end
    if not rosterAbilities[paladinGUID][AURA_MASTERY_ID] then return end

    if auraMasteryActive[paladinGUID] then
        markCooldown(paladinGUID, AURA_MASTERY_ID)
        auraMasteryActive[paladinGUID] = nil
    else
        auraMasteryActive[paladinGUID] = auraInstanceId
        markActive(paladinGUID, AURA_MASTERY_ID)
    end
end


local function updateBaseMaxHP()
    if rallyActive then return end
    baseMaxHP = UnitHealthMax("player")
end

local function detectRallyStart(ratio)
    local increase = ratio - 1.0
    if increase < RALLY_INCREASE_LOW then return end
    if increase > RALLY_INCREASE_HIGH then return end

    rallyActive = true
    rallyStartTime = GetTime()
    rallyAttributedGUID = firstAvailableCaster(RALLYING_CRY_ID)
    if rallyAttributedGUID then
        markActive(rallyAttributedGUID, RALLYING_CRY_ID)
    end
end

local function detectRallyEnd(ratio)
    local diff = math.abs(ratio - 1.0)
    if diff > RALLY_END_TOLERANCE then return end

    rallyActive = false
    if rallyAttributedGUID then
        markCooldown(rallyAttributedGUID, RALLYING_CRY_ID)
        rallyAttributedGUID = nil
    end
end

local function onMaxHealthChanged(unit)
    if unit ~= "player" then return end
    if baseMaxHP <= 0 then return end

    local ratio = UnitHealthMax("player") / baseMaxHP

    if rallyActive then
        detectRallyEnd(ratio)
    else
        detectRallyStart(ratio)
    end
end


local function processAddedAuras(unit, updateInfo)
    if not updateInfo.addedAuras then return end
    for _, auraData in ipairs(updateInfo.addedAuras) do
        if auraData.auraInstanceID then
            onDefensiveGained(unit, auraData.auraInstanceID)
        end
    end
end

local function processUpdatedAuras(unit, updateInfo)
    if not updateInfo.updatedAuraInstanceIDs then return end
    for _, instanceId in ipairs(updateInfo.updatedAuraInstanceIDs) do
        onDevotionAuraChanged(instanceId)
    end
end

local function processRemovedAuras(updateInfo)
    if not updateInfo.removedAuraInstanceIDs then return end
    for _, instanceId in ipairs(updateInfo.removedAuraInstanceIDs) do
        onDefensiveLost(instanceId)
    end
end

local function onUnitAura(unit, updateInfo)
    if not updateInfo then return end
    processAddedAuras(unit, updateInfo)
    processUpdatedAuras(unit, updateInfo)
    processRemovedAuras(updateInfo)
end

local function onSpellcastSucceeded(unit, _, spellId)
    if unit ~= "player" then return end
    if not TRACKED_ABILITIES[spellId] then return end
    castEvidence[spellId] = GetTime()
end

local function onCombatEnd()
    inCombat = false
    scanDevotionAuras()
    updateBaseMaxHP()
    auraMasteryActive = {}
end

local function onRosterUpdate()
    if inCombat then return end
    scanDevotionAuras()
    updateBaseMaxHP()
end

local EVENT_HANDLERS = {
    UNIT_AURA = function(unit, updateInfo) onUnitAura(unit, updateInfo) end,
    UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellId) onSpellcastSucceeded(unit, _, spellId) end,
    UNIT_MAXHEALTH = function(unit) onMaxHealthChanged(unit) end,
    PLAYER_REGEN_DISABLED = function() inCombat = true end,
    PLAYER_REGEN_ENABLED = function() onCombatEnd() end,
    GROUP_ROSTER_UPDATE = function() onRosterUpdate() end,
}

local function OnEvent(_, event, ...)
    local handler = EVENT_HANDLERS[event]
    if handler then
        handler(...)
    end
end


function CooldownTracker:Enable()
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
    end

    eventFrame:SetScript("OnEvent", OnEvent)
    for event in pairs(EVENT_HANDLERS) do
        eventFrame:RegisterEvent(event)
    end

    myGUID = UnitGUID("player")
    updateBaseMaxHP()

    if not InCombatLockdown() then
        scanDevotionAuras()
    end
end

function CooldownTracker:Disable()
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
    end

    abilityState = {}
    rosterAbilities = {}
    rosterOrder = {}
    chargeOverrides = {}
    pendingAuras = {}
    devotionAuraMap = {}
    auraMasteryActive = {}
    castEvidence = {}
    myGUID = nil
    rallyActive = false
    rallyAttributedGUID = nil
end

function CooldownTracker:OnRosterChanged(rosterCooldowns, talents)
    local newRoster = {}
    local newOrder = {}
    for _, entry in ipairs(rosterCooldowns) do
        if TRACKED_ABILITIES[entry.spellId] and entry.guid then
            if not newRoster[entry.guid] then
                newRoster[entry.guid] = {}
            end
            newRoster[entry.guid][entry.spellId] = true
            table.insert(newOrder, { guid = entry.guid, spellId = entry.spellId })
        end
    end

    local newOverrides = {}
    for guid, abilities in pairs(newRoster) do
        local hasPainSuppTalent = abilities[33206]
            and talents
            and talents[guid]
            and talents[guid][PAIN_SUPP_CHARGE_TALENT]

        if hasPainSuppTalent then
            if not newOverrides[guid] then
                newOverrides[guid] = {}
            end
            newOverrides[guid][33206] = 2
        end
    end

    for guid in pairs(abilityState) do
        if not newRoster[guid] then
            abilityState[guid] = nil
        end
    end

    chargeOverrides = newOverrides
    for guid, abilities in pairs(newRoster) do
        for spellId in pairs(abilities) do
            if not abilityState[guid] or not abilityState[guid][spellId] then
                initAbilityState(guid, spellId)
            end
        end
    end

    rosterAbilities = newRoster
    rosterOrder = newOrder

    if not inCombat then
        scanDevotionAuras()
    end
end

function CooldownTracker:IsTrackable(spellId)
    return TRACKED_ABILITIES[spellId] ~= nil
end

local function getActiveState(info, now, spellId)
    if now >= info.activeEndTime then
        return nil
    end
    local ability = TRACKED_ABILITIES[spellId]
    local remaining = math.max(0, info.activeEndTime - now)
    return "active", remaining, ability and ability.activeDuration or 0
end

local function getCooldownState(info, guid, spellId, now)
    local ability = TRACKED_ABILITIES[spellId]
    if not ability then
        return "ready", 0, 0
    end

    if info.chargeCount > 1 then
        countAvailableCharges(info)
        if info.availableCharges > 0 then
            markReady(guid, spellId)
            return "ready", 0, 0
        end
        local soonest = soonestChargeTimer(info)
        if soonest == math.huge then
            markReady(guid, spellId)
            return "ready", 0, 0
        end
        return "cooldown", soonest - now, ability.baseCooldown
    end

    if now >= info.cooldownEndTime then
        markReady(guid, spellId)
        return "ready", 0, 0
    end

    local remaining = math.max(0, info.cooldownEndTime - now)
    local barDuration = ability.baseCooldown - ability.activeDuration
    return "cooldown", remaining, barDuration
end

function CooldownTracker:GetState(guid, spellId)
    local info = abilityState[guid] and abilityState[guid][spellId]
    if not info then
        return "ready", 0, 0
    end

    local now = GetTime()

    if info.chargeCount > 1 then
        countAvailableCharges(info)
    end

    if info.state == "active" then
        local state, remaining, total = getActiveState(info, now, spellId)
        if state then
            return state, remaining, total
        end
        markCooldown(guid, spellId)
    end

    if info.state == "cooldown" then
        return getCooldownState(info, guid, spellId, now)
    end

    return "ready", 0, 0
end
