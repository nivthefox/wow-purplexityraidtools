import assert from 'node:assert/strict';
import test from 'node:test';

import { LAIRS_PHASE_DECIDERS } from '../encounters/Lairs.mjs';
import { THE_VENOMOUS_ABYSS_PHASE_DECIDERS } from '../encounters/TheVenomousAbyss.mjs';
import { decidePhases, getPhaseDecider } from '../phase-deciders.mjs';

function fight(encounterID, startTime = 1000, endTime = 31000) {
    return {
        id: 10,
        encounterID,
        difficulty: 5,
        kill: true,
        startTime,
        endTime,
        enemyNPCs: [],
    };
}

function decide(encounterID, value, events = []) {
    return decidePhases({
        encounterID,
        decider: getPhaseDecider(encounterID),
        fight: value,
        events,
    });
}

test('approved one-phase encounters always span one canonical phase', () => {
    const encounters = [
        [3379, 'Nymrissa Wavecaller'],
        [3420, 'Sszorak'],
        [3421, 'The Twin Fangs'],
        [3445, 'Entombed Sentinels'],
        [3455, 'Vashnik the Malignant'],
        [3497, 'The Lost Explorers'],
    ];
    for (const [encounterID, name] of encounters) {
        const value = fight(encounterID);
        value.phaseTransitions = [
            { id: 1, startTime: 1000 },
            { id: 2, startTime: 9000 },
            { id: 1, startTime: 17000 },
        ];
        assert.deepEqual(decide(encounterID, value, [{
            fight: 10,
            timestamp: 5000,
            type: 'cast',
            abilityGameID: 9999,
            sourceID: 99,
        }]), [{
            id: 1,
            name,
            isIntermission: false,
            startTime: 1000,
            endTime: 31000,
        }]);
    }
});

test('Nymrissa is registered as a Lair rather than a Venomous Abyss encounter', () => {
    assert.equal(LAIRS_PHASE_DECIDERS.has(3379), true);
    assert.equal(THE_VENOMOUS_ABYSS_PHASE_DECIDERS.has(3379), false);
});

test('Nekzali uses its own Ritual of Awakening and Uncoiling casts as actual boundaries', () => {
    const value = fight(3470, 5000, 45000);
    value.enemyNPCs = [
        { id: 70, gameID: 263050 },
        { id: 71, gameID: 259927 },
    ];
    const events = [
        { fight: 10, timestamp: 30000, type: 'cast', abilityGameID: 1292315, sourceID: 71 },
        { fight: 10, timestamp: 15000, type: 'cast', abilityGameID: 1295124, sourceID: 70 },
        { fight: 11, timestamp: 14000, type: 'cast', abilityGameID: 1295124, sourceID: 71 },
        { fight: 10, timestamp: 12000, type: 'begincast', abilityGameID: 1295124, sourceID: 71 },
        { fight: 10, timestamp: 14000, type: 'cast', abilityGameID: 1295124, sourceID: 71 },
        { fight: 10, timestamp: 31000, type: 'cast', abilityGameID: 1292315, sourceID: 71 },
    ];
    assert.deepEqual(decide(3470, value, events), [
        {
            id: 1,
            name: 'Stage One: Soulcoiler Initiation',
            isIntermission: false,
            startTime: 5000,
            endTime: 14000,
        },
        {
            id: 2,
            name: 'Intermission: Ritual of Awakening',
            isIntermission: true,
            startTime: 14000,
            endTime: 30000,
        },
        {
            id: 3,
            name: 'Stage Two: Uncoiling',
            isIntermission: false,
            startTime: 30000,
            endTime: 45000,
        },
    ]);
});

test('Nekzali rejects kills without both ordered boss transition casts', () => {
    const value = fight(3470);
    value.enemyNPCs = [{ id: 71, gameID: 259927 }];
    const ritual = { fight: 10, timestamp: 14000, type: 'cast', abilityGameID: 1295124, sourceID: 71 };
    assert.equal(decide(3470, value, [ritual]), null);
    assert.equal(decide(3470, value, [
        ritual,
        { fight: 10, timestamp: 12000, type: 'cast', abilityGameID: 1292315, sourceID: 71 },
    ]), null);
});

test('The Coiled Altar uses Zuljan death and Ghastly Regeneration buff boundaries', () => {
    const value = fight(3429, 5000, 65000);
    value.enemyNPCs = [
        { id: 80, gameID: 257911 },
        { id: 81, gameID: 259854 },
    ];
    const events = [
        { fight: 10, timestamp: 50000, type: 'removebuff', abilityGameID: 1304033, sourceID: 80 },
        { fight: 10, timestamp: 15000, type: 'death', abilityGameID: 1, sourceID: 90, targetID: 99 },
        { fight: 10, timestamp: 35000, type: 'applybuff', abilityGameID: 1304033, sourceID: 80 },
        { fight: 11, timestamp: 14000, type: 'death', abilityGameID: 1, sourceID: 90, targetID: 80 },
        { fight: 10, timestamp: 20000, type: 'death', abilityGameID: 1, sourceID: 90, targetID: 80 },
    ];
    assert.deepEqual(decide(3429, value, events), [
        {
            id: 1,
            name: "Stage One: Serpent's Bargain",
            isIntermission: false,
            startTime: 5000,
            endTime: 20000,
        },
        {
            id: 2,
            name: "Stage Two: Usurper's Reprisal",
            isIntermission: false,
            startTime: 20000,
            endTime: 35000,
        },
        {
            id: 3,
            name: 'Intermission: The Claimed Vessel',
            isIntermission: true,
            startTime: 35000,
            endTime: 50000,
        },
        {
            id: 4,
            name: 'Stage Three: Coiled Union',
            isIntermission: false,
            startTime: 50000,
            endTime: 65000,
        },
    ]);
});

test('The Coiled Altar rejects kills without the complete ordered transition sequence', () => {
    const value = fight(3429);
    value.enemyNPCs = [{ id: 80, gameID: 257911 }];
    const death = { fight: 10, timestamp: 10000, type: 'death', abilityGameID: 1, sourceID: 90, targetID: 80 };
    const applied = { fight: 10, timestamp: 20000, type: 'applybuff', abilityGameID: 1304033, sourceID: 80 };
    assert.equal(decide(3429, value, [death, applied]), null);
    assert.equal(decide(3429, value, [
        death,
        { ...applied, type: 'removebuff', timestamp: 15000 },
        applied,
    ]), null);
});

test("Ula'tek uses Hatching Doom, the second boss Call of the Serpent, and a 53-second intermission", () => {
    const value = fight(3492, 5000, 450000);
    value.enemyNPCs = [
        { id: 90, gameID: 257758 },
        { id: 91, gameID: 259555 },
    ];
    const events = [
        { fight: 10, timestamp: 315000, type: 'begincast', abilityGameID: 1304012, sourceID: 90 },
        { fight: 10, timestamp: 165002, type: 'begincast', abilityGameID: 1306862, sourceID: 0 },
        { fight: 10, timestamp: 67000, type: 'begincast', abilityGameID: 1304012, sourceID: 90 },
        { fight: 10, timestamp: 165000, type: 'begincast', abilityGameID: 1306862, sourceID: 0 },
        { fight: 11, timestamp: 60000, type: 'begincast', abilityGameID: 1304012, sourceID: 90 },
        { fight: 10, timestamp: 200000, type: 'begincast', abilityGameID: 1304012, sourceID: 91 },
    ];
    assert.deepEqual(decide(3492, value, events), [
        {
            id: 1,
            name: 'Stage One: Fury of the Serpent Mother',
            isIntermission: false,
            startTime: 5000,
            endTime: 165000,
        },
        {
            id: 2,
            name: 'Stage Two: Children of the Doomscale',
            isIntermission: false,
            startTime: 165000,
            endTime: 315000,
        },
        {
            id: 3,
            name: 'Intermission: The Shattering',
            isIntermission: true,
            startTime: 315000,
            endTime: 368000,
        },
        {
            id: 4,
            name: "Stage Three: Ula'tek's Ascension",
            isIntermission: false,
            startTime: 368000,
            endTime: 450000,
        },
    ]);
});

test("Ula'tek rejects kills without the complete ordered Normal transition evidence", () => {
    const value = fight(3492, 5000, 350000);
    value.enemyNPCs = [{ id: 90, gameID: 257758 }];
    const hatchingDoom = {
        fight: 10,
        timestamp: 165000,
        type: 'begincast',
        abilityGameID: 1306862,
        sourceID: 0,
    };
    const firstCall = {
        fight: 10,
        timestamp: 67000,
        type: 'begincast',
        abilityGameID: 1304012,
        sourceID: 90,
    };
    assert.equal(decide(3492, value, [hatchingDoom, firstCall]), null);
    assert.equal(decide(3492, value, [
        hatchingDoom,
        firstCall,
        { ...firstCall, timestamp: 315000 },
    ]), null);
    assert.equal(decide(3492, value, [
        { ...hatchingDoom, type: 'cast' },
        firstCall,
        { ...firstCall, timestamp: 250000 },
    ]), null);
});

test('shared validation rejects gaps and out-of-fight boundaries', () => {
    const value = fight(9001);
    assert.throws(() => decidePhases({
        encounterID: 9001,
        decider: () => [
            { id: 1, name: 'One', isIntermission: false, startTime: 1000, endTime: 12000 },
            { id: 2, name: 'Two', isIntermission: false, startTime: 13000, endTime: 31000 },
        ],
        fight: value,
        events: [],
    }), /not contiguous/);
});
