import assert from 'node:assert/strict';
import test from 'node:test';

import { formatOmission, generateDatabase } from '../generator.mjs';
import { serializeDatabase } from '../lua-data.mjs';

function runtimeCode(index) {
    return `generated-${String.fromCodePoint(65 + (index % 26))}-${Math.floor(index / 26)}`;
}

function candidate(index, duration = 100000 - index) {
    return {
        duration,
        startTime: 1000 + index,
        report: { code: runtimeCode(index), fightID: 1000 + index },
    };
}

function modules(timerIDs = [7001]) {
    return new Map([[4001, {
        journalID: 4001,
        encounterID: 5001,
        bigwigs: new Set(timerIDs),
        dbm: new Set(),
    }]]);
}

function emptyDatabase() {
    return { schemaVersion: 1, encounters: {} };
}

function historicalDatabase() {
    return {
        schemaVersion: 1,
        encounters: {
            9001: {
                difficulties: {
                    16: {
                        phases: [{
                            phaseID: 1,
                            name: 'Historical',
                            isIntermission: false,
                            occurrences: [{ spellID: 9002, time: 9, observations: 3 }],
                        }],
                    },
                },
            },
        },
    };
}

function encounterBytes(source, encounterID) {
    const marker = `[${encounterID}] = {`;
    const start = source.indexOf(marker);
    assert.notEqual(start, -1);
    let depth = 0;
    for (let index = source.indexOf('{', start); index < source.length; index += 1) {
        if (source[index] === '{') {
            depth += 1;
        } else if (source[index] === '}') {
            depth -= 1;
            if (depth === 0) {
                return source.slice(start, index + 2);
            }
        }
    }
    throw new Error('Encounter block did not terminate');
}

function createClient({ rankingsByDifficulty, ineligible = new Set(), noEvents = false, failTimeline = false }) {
    return {
        discoverZones: async () => [{
            id: 3001,
            frozen: false,
            difficulties: [{ id: 5 }, { id: 4 }],
            encounters: [{ id: 2001, journalID: 4001 }],
        }],
        candidateKills: async () => new Map([
            [1, rankingsByDifficulty.get(1) ?? []],
            [3, rankingsByDifficulty.get(3) ?? []],
            [4, rankingsByDifficulty.get(4) ?? []],
            [5, rankingsByDifficulty.get(5) ?? []],
        ]),
        timelineFights: async (reportCode, fightIDs) => {
            if (failTimeline) {
                throw new Error('synthetic API failure');
            }
            const id = fightIDs[0];
            const kill = !ineligible.has(id);
            return {
                phaseDefinitions: [{
                    encounterID: 2001,
                    phases: [{ id: 1, name: 'One', isIntermission: false }],
                }],
                fights: [{
                    id,
                    encounterID: 2001,
                    difficulty: reportCode.includes('difficulty-four') ? 4 : 5,
                    kill,
                    startTime: 0,
                    endTime: 60000,
                    phaseTransitions: [],
                }],
                events: noEvents ? [] : [{ fight: id, timestamp: 12500, type: 'begincast', abilityGameID: 7001 }],
            };
        },
    };
}

test('generation backfills ineligible longest kills to thirty and preserves frozen encounters', async () => {
    const rankings = Array.from({ length: 35 }, (_, index) => candidate(index));
    const ineligible = new Set(rankings.slice(0, 5).map((value) => value.report.fightID));
    const result = await generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map([[5, rankings]]), ineligible }),
        bossModules: modules(),
        existingDatabase: historicalDatabase(),
        buildTime: 100000000,
    });
    assert.deepEqual(result.encounters[9001], historicalDatabase().encounters[9001]);
    assert.equal(
        encounterBytes(serializeDatabase(result), 9001),
        encounterBytes(serializeDatabase(historicalDatabase()), 9001),
    );
    assert.deepEqual(result.encounters[5001].difficulties[16].phases[0].occurrences, [
        { spellID: 7001, time: 13, observations: 30 },
    ]);
});

test('difficulties are generated independently and insufficient new combinations are omitted', async () => {
    const mythic = [candidate(0), candidate(1), candidate(2)];
    const heroic = [candidate(3), candidate(4)];
    const result = await generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map([[5, mythic], [4, heroic]]) }),
        bossModules: modules(),
        existingDatabase: emptyDatabase(),
        buildTime: 100000000,
    });
    assert.deepEqual(Object.keys(result.encounters[5001].difficulties), ['16']);
});

test('an unsupported new encounter is omitted without failing other active encounters', async () => {
    const rankings = [candidate(0), candidate(1), candidate(2)];
    const client = createClient({ rankingsByDifficulty: new Map([[5, rankings]]) });
    const originalDiscover = client.discoverZones;
    client.discoverZones = async () => {
        const zones = await originalDiscover();
        zones[0].encounters.push({ id: 2002, journalID: 4002 });
        return zones;
    };
    const omissions = [];
    const result = await generateDatabase({
        client,
        bossModules: modules(),
        existingDatabase: emptyDatabase(),
        buildTime: 100000000,
        onOmission: (omission) => omissions.push(omission),
    });
    assert.deepEqual(Object.keys(result.encounters), ['5001']);
    assert.deepEqual(omissions.filter((omission) => omission.reason === 'missing-boss-module'), [
        { encounterID: 2002, journalID: 4002, reason: 'missing-boss-module' },
    ]);
    assert.equal(
        formatOmission(omissions.find((omission) => omission.reason === 'missing-boss-module')),
        'Boss timeline omitted encounter 2002 (journal 4002): neither boss mod has a matching module.',
    );
});

test('new encounter omissions report insufficient candidates, invalid kills, and missing abilities', async () => {
    const rankings = [candidate(0), candidate(1), candidate(2)];
    const scenarios = [
        {
            client: createClient({ rankingsByDifficulty: new Map([[5, rankings.slice(0, 2)]]) }),
            reason: 'insufficient-candidates',
            expected: { candidateCount: 2 },
            message: 'Boss timeline omitted encounter 5001, Mythic difficulty (WoW 16, WCL 5): found 2 page-one candidates; at least 3 are required.',
        },
        {
            client: createClient({
                rankingsByDifficulty: new Map([[5, rankings]]),
                ineligible: new Set(rankings.map((value) => value.report.fightID)),
            }),
            reason: 'insufficient-valid-kills',
            expected: {
                candidateCount: 3,
                validKillCount: 0,
                rejectionCounts: { 'not-a-kill': 3 },
            },
            message: 'Boss timeline omitted encounter 5001, Mythic difficulty (WoW 16, WCL 5): validated 0 of 3 page-one candidates; at least 3 valid kills are required. Rejections: not marked as a kill=3.',
        },
        {
            client: createClient({ rankingsByDifficulty: new Map([[5, rankings]]), noEvents: true }),
            reason: 'no-qualifying-abilities',
            expected: { candidateCount: 3, validKillCount: 3 },
            message: 'Boss timeline omitted encounter 5001, Mythic difficulty (WoW 16, WCL 5): 3 valid kills produced no qualifying boss abilities.',
        },
    ];
    for (const scenario of scenarios) {
        const omissions = [];
        await generateDatabase({
            client: scenario.client,
            bossModules: modules(),
            existingDatabase: emptyDatabase(),
            buildTime: 100000000,
            onOmission: (omission) => omissions.push(omission),
        });
        const omission = omissions.find((value) => value.wowDifficulty === 16);
        assert.equal(omission.reason, scenario.reason);
        assert.equal(omission.encounterID, 5001);
        for (const [key, value] of Object.entries(scenario.expected)) {
            assert.deepEqual(omission[key], value);
        }
        assert.equal(formatOmission(omission), scenario.message);
    }
});

test('invalid kill diagnostics account for every candidate by rejection rule', async () => {
    const rankings = Array.from({ length: 8 }, (_, index) => candidate(index));
    const client = createClient({ rankingsByDifficulty: new Map([[5, rankings]]) });
    const timelineFights = client.timelineFights;
    client.timelineFights = async (...argumentsList) => {
        const report = await timelineFights(...argumentsList);
        const index = report.fights[0].id - 1000;
        if (index === 1) {
            report.fights = [];
        } else if (index === 2) {
            report.fights[0].kill = false;
        } else if (index === 3) {
            report.fights[0].encounterID = 2002;
        } else if (index === 4) {
            report.fights[0].difficulty = 4;
        } else if (index === 5) {
            report.phaseDefinitions = [];
        } else if (index === 6) {
            report.phaseDefinitions[0].phases.push({ id: 2, name: 'Two', isIntermission: false });
            report.fights[0].phaseTransitions = [{ id: 1, startTime: 0 }];
        } else if (index === 7) {
            report.phaseDefinitions[0].phases[0].name = 'Different';
        }
        return report;
    };
    const omissions = [];
    await generateDatabase({
        client,
        bossModules: modules(),
        existingDatabase: emptyDatabase(),
        buildTime: 100000000,
        onOmission: (omission) => omissions.push(omission),
    });
    const omission = omissions.find((value) => value.wowDifficulty === 16);
    assert.equal(omission.validKillCount, 1);
    assert.deepEqual(omission.rejectionCounts, {
        'missing-timeline-fight': 1,
        'not-a-kill': 1,
        'encounter-mismatch': 1,
        'difficulty-mismatch': 1,
        'invalid-phase-definitions': 1,
        'invalid-phase-transitions': 1,
        'inconsistent-phase-sequence': 1,
    });
    assert.equal(
        formatOmission(omission),
        'Boss timeline omitted encounter 5001, Mythic difficulty (WoW 16, WCL 5): validated 1 of 8 page-one candidates; at least 3 valid kills are required. Rejections: missing from timeline response=1, not marked as a kill=1, encounter mismatch=1, difficulty mismatch=1, invalid phase definitions=1, invalid phase transitions=1, inconsistent phase sequence=1.',
    );
});

test('generation falls back to the runtime encounter ID when WCL has no journal ID', async () => {
    const rankings = [candidate(0), candidate(1), candidate(2)];
    const client = createClient({ rankingsByDifficulty: new Map([[5, rankings]]) });
    const originalTimelineFights = client.timelineFights;
    client.discoverZones = async () => [{
        id: 3001,
        frozen: false,
        difficulties: [{ id: 5 }],
        encounters: [{ id: 5001, journalID: 0 }],
    }];
    client.timelineFights = async (...argumentsList) => {
        const report = await originalTimelineFights(...argumentsList);
        report.phaseDefinitions[0].encounterID = 5001;
        report.fights[0].encounterID = 5001;
        return report;
    };
    const result = await generateDatabase({
        client,
        bossModules: modules(),
        existingDatabase: emptyDatabase(),
        buildTime: 100000000,
    });
    assert.deepEqual(Object.keys(result.encounters), ['5001']);
});

test('loss of evidence or qualifying abilities for existing data fails without mutating input', async () => {
    const existing = historicalDatabase();
    existing.encounters[5001] = {
        difficulties: {
            16: {
                phases: [{
                    phaseID: 1,
                    name: 'One',
                    isIntermission: false,
                    occurrences: [{ spellID: 7001, time: 13, observations: 3 }],
                }],
            },
        },
    };
    const before = serializeDatabase(existing);
    await assert.rejects(() => generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map([[5, [candidate(0), candidate(1)]]]) }),
        bossModules: modules(),
        existingDatabase: existing,
        buildTime: 100000000,
    }), /minimum evidence/);
    assert.equal(serializeDatabase(existing), before);

    await assert.rejects(() => generateDatabase({
        client: createClient({
            rankingsByDifficulty: new Map([[5, [candidate(0), candidate(1), candidate(2)]]]),
            noEvents: true,
        }),
        bossModules: modules(),
        existingDatabase: existing,
        buildTime: 100000000,
    }), /no qualifying abilities/);
    assert.equal(serializeDatabase(existing), before);
});

test('upstream failure is atomic and deterministic response reordering produces identical bytes', async () => {
    const rankings = [candidate(0), candidate(1), candidate(2), candidate(3)];
    const existing = historicalDatabase();
    const before = serializeDatabase(existing);
    await assert.rejects(() => generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map([[5, rankings]]), failTimeline: true }),
        bossModules: modules(),
        existingDatabase: existing,
        buildTime: 100000000,
    }), /synthetic API failure/);
    assert.equal(serializeDatabase(existing), before);

    const first = await generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map([[5, rankings]]) }),
        bossModules: modules(),
        existingDatabase: existing,
        buildTime: 100000000,
    });
    const second = await generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map([[5, [...rankings].reverse()]]) }),
        bossModules: modules(),
        existingDatabase: existing,
        buildTime: 200000000,
    });
    assert.equal(serializeDatabase(first), serializeDatabase(second));
});

test('invalid explicit alias mappings fail before accepting generated output', async () => {
    await assert.rejects(() => generateDatabase({
        client: createClient({ rankingsByDifficulty: new Map() }),
        bossModules: modules(),
        existingDatabase: emptyDatabase(),
        buildTime: 100000000,
        aliases: { bigwigs: new Map([['not-a-number', 7001]]), dbm: new Map() },
    }), /aliases are malformed/);
});
