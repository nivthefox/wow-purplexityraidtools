import assert from 'node:assert/strict';
import test from 'node:test';

import { buildDifficulty, evaluateFight, normalizeFight } from '../timeline.mjs';

const modules = { bigwigs: new Set([7001, 7999]), dbm: new Set([7002]) };
const aliases = { bigwigs: new Map([[7999, 7003]]), dbm: new Map() };

function phaseDefinitions() {
    return [{
        encounterID: 5001,
        phases: [
            { id: 1, name: 'Opening', isIntermission: false },
            { id: 2, name: 'Intermission', isIntermission: true },
        ],
    }];
}

function fight(id, startTime = 1000) {
    return {
        id,
        encounterID: 5001,
        difficulty: 5,
        kill: true,
        startTime,
        endTime: startTime + 30000,
        phaseTransitions: [
            { id: 1, startTime },
            { id: 2, startTime: startTime + 10000 },
            { id: 1, startTime: startTime + 20000 },
        ],
    };
}

function normalize(id, events, startTime = 1000) {
    return normalizeFight({
        fight: fight(id, startTime),
        phaseDefinitions: phaseDefinitions(),
        events,
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    });
}

test('normalization is phase relative, repeats semantic phases, and assigns boundary casts to the new phase', () => {
    const first = normalize(1, [
        { fight: 1, timestamp: 2000, type: 'begincast', abilityGameID: 7001 },
        { fight: 1, timestamp: 11000, type: 'cast', abilityGameID: 7002 },
        { fight: 1, timestamp: 21000, type: 'begincast', abilityGameID: 7003 },
    ]);
    const second = normalize(2, [
        { fight: 2, timestamp: 52000, type: 'begincast', abilityGameID: 7001 },
        { fight: 2, timestamp: 61000, type: 'cast', abilityGameID: 7002 },
        { fight: 2, timestamp: 71000, type: 'begincast', abilityGameID: 7003 },
    ], 51000);
    assert.equal(first.signature, JSON.stringify([1, 2, 1]));
    assert.deepEqual(first.phaseEvents, second.phaseEvents);
    assert.equal(first.phaseEvents[1][0].offset, 0);
});

test('invalid phase sequences and mismatched fights are excluded entirely', () => {
    const invalid = fight(1);
    invalid.phaseTransitions = [{ id: 1, startTime: 1001 }];
    assert.equal(normalizeFight({
        fight: invalid,
        phaseDefinitions: phaseDefinitions(),
        events: [],
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    }), null);
    invalid.kill = false;
    assert.equal(normalizeFight({
        fight: invalid,
        phaseDefinitions: phaseDefinitions(),
        events: [],
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    }), null);

    const wrongEncounter = fight(2);
    wrongEncounter.encounterID = 5002;
    assert.equal(normalizeFight({
        fight: wrongEncounter,
        phaseDefinitions: phaseDefinitions(),
        events: [],
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    }), null);

    const wrongDifficulty = fight(3);
    wrongDifficulty.difficulty = 4;
    assert.equal(normalizeFight({
        fight: wrongDifficulty,
        phaseDefinitions: phaseDefinitions(),
        events: [],
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    }), null);
});

test('fight evaluation identifies the normalization rule that rejected a fight', () => {
    const cases = [
        {
            reason: 'not-a-kill',
            mutate: (value) => {
                value.kill = false;
            },
        },
        {
            reason: 'encounter-mismatch',
            mutate: (value) => {
                value.encounterID = 5002;
            },
        },
        {
            reason: 'difficulty-mismatch',
            mutate: (value) => {
                value.difficulty = 4;
            },
        },
        {
            reason: 'invalid-phase-transitions',
            mutate: (value) => {
                value.phaseTransitions = [{ id: 1, startTime: value.startTime + 1 }];
            },
        },
    ];
    for (const scenario of cases) {
        const value = fight(1);
        scenario.mutate?.(value);
        const evaluation = evaluateFight({
            fight: value,
            phaseDefinitions: scenario.phaseDefinitions ?? phaseDefinitions(),
            events: [],
            encounterID: 5001,
            difficulty: 5,
            modules,
            aliases,
        });
        assert.deepEqual(evaluation, { rejectionReason: scenario.reason });
    }
});

test('missing phase definitions use transition IDs or a single-phase fallback', () => {
    const multiPhase = evaluateFight({
        fight: fight(1),
        phaseDefinitions: [],
        events: [],
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    }).normalizedFight;
    assert.deepEqual(multiPhase.phases.map((phase) => ({
        id: phase.id,
        name: phase.name,
        isIntermission: phase.isIntermission,
    })), [
        { id: 1, name: 'Phase 1', isIntermission: false },
        { id: 2, name: 'Phase 2', isIntermission: false },
        { id: 1, name: 'Phase 1', isIntermission: false },
    ]);

    const singlePhaseFight = fight(2);
    singlePhaseFight.phaseTransitions = [];
    const singlePhase = evaluateFight({
        fight: singlePhaseFight,
        phaseDefinitions: [],
        events: [],
        encounterID: 5001,
        difficulty: 5,
        modules,
        aliases,
    }).normalizedFight;
    assert.deepEqual(singlePhase.phases, [{
        id: 1,
        name: 'Phase 1',
        isIntermission: false,
        startTime: 1000,
        endTime: 31000,
    }]);
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
        { fight: 1, timestamp: 2000, type: 'cast', abilityGameID: 7001 },
        { fight: 1, timestamp: 2000, type: 'cast', abilityGameID: 7001 },
        { fight: 1, timestamp: 2900, type: 'cast', abilityGameID: 7001 },
        { fight: 1, timestamp: 4100, type: 'cast', abilityGameID: 7001 },
        { fight: 1, timestamp: 5000, type: 'applydebuff', abilityGameID: 7002 },
        { fight: 1, timestamp: 6000, type: 'cast', abilityGameID: 7998 },
    ];
    assert.deepEqual(normalize(1, events).phaseEvents[0].map((event) => event.offset), [1000, 3100]);
});

test('occurrence timing prefers qualifying begincast, falls back to cast, omits missing values, and rounds medians', () => {
    const offsets = [2500, 3500, 4500, 5500];
    const fights = offsets.map((offset, index) => normalize(index + 1, [
        { fight: index + 1, timestamp: 1000 + offset, type: 'begincast', abilityGameID: 7001 },
        { fight: index + 1, timestamp: 1000 + offset + 500, type: 'cast', abilityGameID: 7001 },
        { fight: index + 1, timestamp: 1000 + 9000, type: 'cast', abilityGameID: 7002 },
    ]));
    fights[3].phaseEvents[0] = fights[3].phaseEvents[0].filter((event) => event.spellID !== 7002);
    const difficulty = buildDifficulty(fights);
    assert.deepEqual(difficulty.phases[0].occurrences, [
        { spellID: 7001, time: 4, observations: 4 },
        { spellID: 7002, time: 9, observations: 3 },
    ]);
});
