import assert from 'node:assert/strict';
import test from 'node:test';

import { discoverCurrentTier, raidZones, selectDistinctCandidates } from '../discovery.mjs';

function code(index) {
    return `synthetic-${String.fromCodePoint(65 + index)}`;
}

function candidate(index, duration, startTime = index) {
    return {
        duration,
        startTime,
        report: { code: code(index), fightID: index + 100 },
    };
}

test('candidate selection deduplicates, ignores response order, and applies deterministic tie breakers', () => {
    const values = [
        candidate(2, 5000, 100),
        candidate(0, 6000, 100),
        candidate(1, 5000, 200),
        candidate(0, 5500, 90),
    ];
    assert.deepEqual(selectDistinctCandidates(values), [values[1], values[2], values[0]]);
});

test('candidate selection keeps more than thirty candidates for eligibility backfill', () => {
    const values = Array.from({ length: 35 }, (_, index) => candidate(index, 1000 + index));
    assert.equal(selectDistinctCandidates(values).length, 35);
});

test('raid discovery excludes frozen and non-raid zones', () => {
    const zones = [
        { id: 1, frozen: false, difficulties: [{ id: 5 }], encounters: [{ id: 10, journalID: 20 }] },
        { id: 2, frozen: true, difficulties: [{ id: 5 }], encounters: [{ id: 11, journalID: 21 }] },
        { id: 3, frozen: false, difficulties: [{ id: 10 }], encounters: [{ id: 12, journalID: 22 }] },
    ];
    assert.deepEqual(raidZones(zones), [zones[0]]);
});

test('current tier includes every encounter from every raid zone active within seven days', async () => {
    const zones = [
        {
            id: 1,
            frozen: false,
            difficulties: [{ id: 4 }, { id: 5 }],
            encounters: [{ id: 10, journalID: 20 }, { id: 11, journalID: 21 }],
        },
        {
            id: 2,
            frozen: false,
            difficulties: [{ id: 5 }],
            encounters: [{ id: 12, journalID: 22 }],
        },
    ];
    const calls = [];
    const buildTime = 200000000;
    const twoDaysAgo = buildTime - (2 * 24 * 60 * 60 * 1000);
    const client = {
        discoverZones: async () => zones,
        candidateKills: async (encounterID, difficulty, startTime, endTime) => {
            calls.push({ encounterID, difficulty, startTime, endTime });
            if (encounterID === 10 || encounterID === 12) {
                return [candidate(encounterID, 1000, twoDaysAgo)];
            }
            return [];
        },
    };
    const result = await discoverCurrentTier(client, buildTime);
    assert.equal(result.length, 2);
    assert.deepEqual(result[0].encounters, zones[0].encounters);
    assert.equal(result[0].combinations.get(10).get(4)[0].startTime, twoDaysAgo);
    assert.deepEqual(calls[0], {
        encounterID: 10,
        difficulty: 4,
        startTime: buildTime - 604800000,
        endTime: buildTime,
    });
});

test('no activity within seven days fails instead of erasing the current database', async () => {
    const client = {
        discoverZones: async () => [{
            id: 1,
            frozen: false,
            difficulties: [{ id: 5 }],
            encounters: [{ id: 10, journalID: 20 }],
        }],
        candidateKills: async () => [],
    };
    await assert.rejects(() => discoverCurrentTier(client, 100000000), /No current raid tier/);
});
