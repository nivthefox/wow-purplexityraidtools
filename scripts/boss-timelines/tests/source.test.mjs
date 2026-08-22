import assert from 'node:assert/strict';
import test from 'node:test';

import { mergeBossModules, parseBossModule } from '../lua-source.mjs';

test('BigWigs extraction includes active numeric bars and excludes non-bars and comments', () => {
    const source = `
local mod = BigWigs:NewBoss("Synthetic", 99, 4001)
mod:SetEncounterID(5001)
function mod:OnEngage()
    self:Bar(6001, 10)
    self:CDBar(6002, 20)
    self:CastBar(6003, 3)
    self:Message(6004)
    self:Aura(6005)
    -- self:Bar(6006, 10)
end
`;
    const module = parseBossModule(source, 'bigwigs');
    assert.equal(module.journalID, 4001);
    assert.equal(module.encounterID, 5001);
    assert.deepEqual([...module.timerIDs], [6001, 6002, 6003]);
});

test('BigWigs extraction includes equivalent returned timer records', () => {
    const source = `
local mod = BigWigs:NewBoss("Synthetic", 99, 4001)
mod:SetEncounterID(5001)
local function nextBar()
    local barInfo = self:SyntheticTimer()
    self:CDBar(barInfo.key, barInfo.duration)
end
function mod:SyntheticTimer()
    return { key = 6007 }
end
`;
    assert.deepEqual([...parseBossModule(source, 'bigwigs').timerIDs], [6007]);
});

test('source-like text inside strings does not create a boss module', () => {
    const source = `local pattern = "BigWigs:NewBoss(\\"Synthetic\\", 99, 4001)"`;
    assert.equal(parseBossModule(source, 'bigwigs'), null);
});

test('DBM extraction includes ability timer objects and excludes encounter-level objects', () => {
    const source = `
local mod = DBM:NewMod(4001, "Synthetic")
mod:SetEncounterID(5001)
local timerA = mod:NewCDTimer(20, 6001)
local timerB = mod:NewVarTimer(10, 20, 6002)
local timerC = mod:NewStageTimer(10, 6003)
local timerD = mod:NewBerserkTimer(6004)
local timerUnused = mod:NewCDTimer(20, 6006)
local timerTimeline = mod:NewCDCountTimer("d20.5", 6007)
local timerTimelineFallback = mod:NewCDTimer(20, 6008)
local warn = mod:NewSpecialWarningSpell(6005)
timerA:Start()
timerB:Start()
timerC:Start()
timerD:Start()
timerTimeline:TLStart(20.5, 100)
timerTimelineFallback:SetTimeline(101, true)
`;
    const module = parseBossModule(source, 'dbm');
    assert.deepEqual([...module.timerIDs], [6001, 6002, 6007, 6008]);
});

test('source parser fails closed on conflicting and unterminated structures', () => {
    const conflicting = `
local mod = BigWigs:NewBoss("Synthetic", 99, 4001)
mod:SetEncounterID(5001)
mod:SetEncounterID(5002)
`;
    assert.throws(() => parseBossModule(conflicting, 'bigwigs'), /conflicting/);
    assert.throws(() => parseBossModule('local mod = BigWigs:NewBoss("x", 1, 2', 'bigwigs'), /Unterminated/);
});

test('boss-mod union retains one encounter and both timer sets', () => {
    const merged = mergeBossModules([
        { bossMod: 'bigwigs', journalID: 4001, encounterID: 5001, timerIDs: new Set([6001]) },
        { bossMod: 'dbm', journalID: 4001, encounterID: 5001, timerIDs: new Set([6001, 6002]) },
    ]);
    assert.deepEqual([...merged.get(4001).bigwigs], [6001]);
    assert.deepEqual([...merged.get(4001).dbm], [6001, 6002]);
});
