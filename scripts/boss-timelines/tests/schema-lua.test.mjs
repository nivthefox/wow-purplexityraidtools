import assert from 'node:assert/strict';
import test from 'node:test';

import { parseDatabase, serializeDatabase } from '../lua-data.mjs';
import { validateDatabase } from '../schema.mjs';

function database() {
    return {
        schemaVersion: 1,
        encounters: {
            2001: {
                difficulties: {
                    16: {
                        phases: [
                            {
                                phaseID: 1,
                                name: 'Phase "One"',
                                isIntermission: false,
                                occurrences: [
                                    { spellID: 3001, time: 12, observations: 3 },
                                    { spellID: 3002, time: 12, observations: 30 },
                                ],
                            },
                            { phaseID: 1, name: 'Phase "One"', isIntermission: false, occurrences: [] },
                        ],
                    },
                },
            },
        },
    };
}

test('database serialization is deterministic and round trips the closed shape', () => {
    const first = serializeDatabase(database());
    const second = serializeDatabase(parseDatabase(first));
    assert.equal(second, first);
    assert.deepEqual(parseDatabase(first), database());
});

test('the initial empty encounter map round trips as a map rather than an array', () => {
    const empty = { schemaVersion: 1, encounters: {} };
    assert.deepEqual(parseDatabase(serializeDatabase(empty)), empty);
});

test('database validation rejects unknown fields and invalid ranges at every level', () => {
    const cases = [
        () => ({ ...database(), provenance: {} }),
        () => ({ ...database(), schemaVersion: 2 }),
        () => ({ ...database(), encounters: { 0: database().encounters[2001] } }),
        () => ({ ...database(), encounters: { 2001: { ...database().encounters[2001], name: 'Boss' } } }),
        () => ({ ...database(), encounters: { 2001: { difficulties: { 2: database().encounters[2001].difficulties[16] } } } }),
        () => ({ ...database(), encounters: { 2001: { difficulties: { 16: { phases: [] } } } } }),
        () => {
            const value = database();
            value.encounters[2001].difficulties[16].phases[0].rawEvents = [];
            return value;
        },
        () => {
            const value = database();
            value.encounters[2001].difficulties[16].phases[0].occurrences[0].observations = 2;
            return value;
        },
        () => {
            const value = database();
            value.encounters[2001].difficulties[16].phases[0].occurrences.reverse();
            value.encounters[2001].difficulties[16].phases[0].occurrences[0].time = 13;
            return value;
        },
    ];
    for (const createInvalid of cases) {
        assert.throws(() => validateDatabase(createInvalid()), /Invalid boss timeline database/);
    }
});

test('semantically identical numeric maps serialize in ascending key order', () => {
    const value = database();
    value.encounters = {
        3000: value.encounters[2001],
        1000: value.encounters[2001],
    };
    const serialized = serializeDatabase(value);
    assert.ok(serialized.indexOf('[1000]') < serialized.indexOf('[3000]'));
});

test('generated output cannot carry secret or sampled-log canaries outside the schema', () => {
    const canaries = ['credential-canary', 'token-canary', 'sampled-log-canary'];
    const serialized = serializeDatabase(database());
    for (const canary of canaries) {
        assert.equal(serialized.includes(canary), false);
    }
    const value = database();
    value.sample = canaries;
    assert.throws(() => serializeDatabase(value), /expected exactly/);
});
