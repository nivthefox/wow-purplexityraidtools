import assert from 'node:assert/strict';
import test from 'node:test';

import { getPhaseDecider } from '../phase-deciders.mjs';
import { buildDifficulty, evaluateFight, normalizeFight } from '../timeline.mjs';

const modules = { bigwigs: new Set([7001, 7999]), dbm: new Set([7002]) };
const aliases = { bigwigs: new Map([[7999, 7003]]), dbm: new Map() };

function fight(id, startTime = 1000) {
    return {
        id,
        encounterID: 3470,
        difficulty: 5,
        kill: true,
        startTime,
        endTime: startTime + 40000,
        enemyNPCs: [{ id: 77, gameID: 259927 }],
    };
}

function event(fightID, timestamp, type, abilityGameID, sourceID = 77) {
    return { fight: fightID, timestamp, type, sourceID, abilityGameID };
}

function onePhaseDecider({ fight: value }) {
    return [{
        id: 1,
        name: 'One',
        isIntermission: false,
        startTime: value.startTime,
        endTime: value.endTime,
    }];
}

function normalizeOnePhase(id, events, startTime = 1000) {
    return normalizeFight({
        fight: fight(id, startTime),
        events,
        encounterID: 3470,
        difficulty: 5,
        modules,
        aliases,
        phaseDecider: onePhaseDecider,
    });
}

test('normalization follows per-kill canonical boundaries and assigns boundary casts to the new phase', () => {
    const phaseDecider = getPhaseDecider(3470);
    const first = normalizeFight({
        fight: fight(1),
        events: [
            event(1, 2000, 'begincast', 7001),
            event(1, 11000, 'cast', 1295124),
            event(1, 11000, 'cast', 7002),
            event(1, 21000, 'applybuff', 1290003),
            event(1, 21000, 'begincast', 7003),
        ],
        encounterID: 3470,
        difficulty: 5,
        modules,
        aliases,
        phaseDecider,
    });
    const second = normalizeFight({
        fight: fight(2, 51000),
        events: [
            event(2, 52000, 'begincast', 7001),
            event(2, 66000, 'cast', 1295124),
            event(2, 66000, 'cast', 7002),
            event(2, 81000, 'applybuff', 1290003),
            event(2, 81000, 'begincast', 7003),
        ],
        encounterID: 3470,
        difficulty: 5,
        modules,
        aliases,
        phaseDecider,
    });
    assert.equal(first.signature, JSON.stringify([1, 2, 3]));
    assert.deepEqual(first.phaseEvents, second.phaseEvents);
    assert.equal(first.phaseEvents[1][0].offset, 0);
    assert.equal(first.phaseEvents[2][0].offset, 0);
});

test('mismatched fights are excluded before the phase decider runs', () => {
    const cases = [
        ['not-a-kill', (value) => { value.kill = false; }],
        ['encounter-mismatch', (value) => { value.encounterID = 5002; }],
        ['difficulty-mismatch', (value) => { value.difficulty = 4; }],
    ];
    for (const [reason, mutate] of cases) {
        const value = fight(1);
        mutate(value);
        assert.deepEqual(evaluateFight({
            fight: value,
            events: [],
            encounterID: 3470,
            difficulty: 5,
            modules,
            aliases,
            phaseDecider: () => {
                throw new Error('phase decider should not run');
            },
        }), { rejectionReason: reason });
    }
});

test('a kill without canonical boundaries is rejected and malformed decider output fails loudly', () => {
    assert.deepEqual(evaluateFight({
        fight: fight(1),
        events: [],
        encounterID: 3470,
        difficulty: 5,
        modules,
        aliases,
        phaseDecider: () => null,
    }), { rejectionReason: 'missing-canonical-phase-boundaries' });

    assert.throws(() => normalizeFight({
        fight: fight(1),
        events: [],
        encounterID: 3470,
        difficulty: 5,
        modules,
        aliases,
        phaseDecider: ({ fight: value }) => [{
            id: 1,
            name: 'Broken',
            isIntermission: false,
            startTime: value.startTime + 1,
            endTime: value.endTime,
        }],
    }), /first phase does not start with the fight/);
});

test('occurrence indexes remain aligned across missing observations and exact half seconds round upward', () => {
    const makeFight = (index, events) => ({
        signature: '1',
        phases: [{ id: 1, name: 'One', isIntermission: false }],
        phaseEvents: [events],
        fightID: index,
    });
    const fights = [
        makeFight(1, [
            { spellID: 8001, type: 'begincast', offset: 1000 },
            { spellID: 8001, type: 'cast', offset: 3000 },
            { spellID: 8002, type: 'cast', offset: 1000 },
            { spellID: 8002, type: 'cast', offset: 8000 },
        ]),
        makeFight(2, [
            { spellID: 8001, type: 'begincast', offset: 1100 },
            { spellID: 8001, type: 'cast', offset: 4000 },
            { spellID: 8002, type: 'cast', offset: 1200 },
            { spellID: 8002, type: 'cast', offset: 8200 },
        ]),
        makeFight(3, [
            { spellID: 8001, type: 'cast', offset: 5000 },
            { spellID: 8002, type: 'cast', offset: 1400 },
            { spellID: 8002, type: 'cast', offset: 8400 },
        ]),
        makeFight(4, [
            { spellID: 8001, type: 'cast', offset: 6000 },
            { spellID: 8002, type: 'cast', offset: 1600 },
        ]),
    ];
    assert.deepEqual(buildDifficulty(fights).phases[0].occurrences, [
        { spellID: 8002, time: 1, observations: 4 },
        { spellID: 8001, time: 5, observations: 4 },
        { spellID: 8002, time: 8, observations: 3 },
    ]);
});

test('normalization removes duplicates, clusters one-second repeats, and ignores unqualified events', () => {
    const events = [
        event(1, 2000, 'cast', 7001),
        event(1, 2000, 'cast', 7001),
        event(1, 2900, 'cast', 7001),
        event(1, 4100, 'cast', 7001),
        event(1, 5000, 'applydebuff', 7002),
        event(1, 6000, 'cast', 7998),
    ];
    assert.deepEqual(normalizeOnePhase(1, events).phaseEvents[0].map((value) => value.offset), [1000, 3100]);
});

test('occurrence timing prefers qualifying begincast, falls back to cast, omits missing values, and rounds medians', () => {
    const offsets = [2500, 3500, 4500, 5500];
    const fights = offsets.map((offset, index) => normalizeOnePhase(index + 1, [
        event(index + 1, 1000 + offset, 'begincast', 7001),
        event(index + 1, 1000 + offset + 500, 'cast', 7001),
        event(index + 1, 10000, 'cast', 7002),
    ]));
    fights[3].phaseEvents[0] = fights[3].phaseEvents[0].filter((value) => value.spellID !== 7002);
    assert.deepEqual(buildDifficulty(fights).phases[0].occurrences, [
        { spellID: 7001, time: 4, observations: 4 },
        { spellID: 7002, time: 9, observations: 3 },
    ]);
});
