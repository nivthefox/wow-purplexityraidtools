import assert from 'node:assert/strict';
import test from 'node:test';

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
