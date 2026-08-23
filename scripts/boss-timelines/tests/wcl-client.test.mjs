import assert from 'node:assert/strict';
import test from 'node:test';

import {
    CANDIDATE_KILLS_QUERY,
    DISCOVER_ZONES_QUERY,
    SerializedRequestGate,
    TIMELINE_FIGHTS_QUERY,
    WarcraftLogsClient,
    validateCandidateResponse,
    validateTimelineResponse,
    validateZonesResponse,
} from '../wcl-client.mjs';

function response(body, ok = true, status = ok ? 200 : 500, retryAfter = null) {
    return {
        ok,
        status,
        headers: { get: (name) => (name === 'retry-after' ? retryAfter : null) },
        json: async () => body,
    };
}

function runtimeCode() {
    return `runtime-${String.fromCodePoint(88)}`;
}

function candidatePage(rankings = []) {
    return { page: 1, hasMorePages: true, rankings };
}

function candidateResponse(rankingsByDifficulty = new Map()) {
    return {
        data: {
            worldData: {
                encounter: {
                    lfr: candidatePage(rankingsByDifficulty.get(1)),
                    normal: candidatePage(rankingsByDifficulty.get(3)),
                    heroic: candidatePage(rankingsByDifficulty.get(4)),
                    mythic: candidatePage(rankingsByDifficulty.get(5)),
                },
            },
        },
    };
}

function eventStreams(overrides = {}) {
    return {
        casts: { data: [], nextPageTimestamp: null },
        buffs: { data: [], nextPageTimestamp: null },
        deaths: { data: [], nextPageTimestamp: null },
        ...overrides,
    };
}

test('request gate separates starts by one second and never overlaps requests', async () => {
    let clock = 0;
    let active = 0;
    let maxActive = 0;
    const starts = [];
    const gate = new SerializedRequestGate({
        now: () => clock,
        sleep: async (milliseconds) => { clock += milliseconds; },
    });
    const request = async () => {
        starts.push(clock);
        active += 1;
        maxActive = Math.max(maxActive, active);
        await Promise.resolve();
        active -= 1;
    };
    await Promise.all([gate.run(request), gate.run(request), gate.run(request)]);
    assert.deepEqual(starts, [0, 1000, 2000]);
    assert.equal(maxActive, 1);
});

test('zone, candidate, and timeline validators reject malformed consumed fields', () => {
    assert.throws(() => validateZonesResponse({ data: { worldData: { zones: [{ id: 1 }] } } }), /contract/);
    assert.throws(() => validateCandidateResponse({ data: { worldData: { encounter: { fightRankings: {} } } } }), /contract/);
    assert.throws(() => validateTimelineResponse({ data: { reportData: { report: { phases: [], fights: [] } } } }), /contract/);
});

test('zone validation normalizes nullable difficulty and encounter lists', () => {
    const zones = validateZonesResponse({
        data: {
            worldData: {
                zones: [{ id: 1, frozen: true, difficulties: null, encounters: null }],
            },
        },
    });
    assert.deepEqual(zones[0].difficulties, []);
    assert.deepEqual(zones[0].encounters, []);
});

test('zone validation accepts integer metadata outside the selected raid difficulties', () => {
    const zones = validateZonesResponse({
        data: {
            worldData: {
                zones: [{
                    id: 1,
                    frozen: true,
                    difficulties: [{ id: -1 }],
                    encounters: [{ id: 2, journalID: 0 }],
                }],
            },
        },
    });
    assert.equal(zones[0].difficulties[0].id, -1);
    assert.equal(zones[0].encounters[0].journalID, 0);
});

test('timeline validation ignores WCL phase metadata and normalizes nullable enemy lists', () => {
    const report = validateTimelineResponse({
        data: {
            reportData: {
                report: {
                    phases: 'malformed and irrelevant',
                    fights: [{
                        id: 101,
                        encounterID: 10,
                        difficulty: 5,
                        kill: true,
                        startTime: 0,
                        endTime: 10000,
                        phaseTransitions: 'malformed and irrelevant',
                        enemyNPCs: null,
                    }],
                    ...eventStreams(),
                },
            },
        },
    });
    assert.deepEqual(report.fights[0].enemyNPCs, []);
});

test('timeline validation requires cast source identity used by encounter deciders', () => {
    assert.throws(() => validateTimelineResponse({
        data: {
            reportData: {
                report: {
                    fights: [{
                        id: 101,
                        encounterID: 10,
                        difficulty: 5,
                        kill: true,
                        startTime: 0,
                        endTime: 10000,
                        enemyNPCs: [{ id: 71, gameID: 259927 }],
                    }],
                    ...eventStreams({
                        casts: {
                            data: [{ fight: 101, abilityGameID: 20, timestamp: 5000, type: 'cast' }],
                            nextPageTimestamp: null,
                        },
                    }),
                },
            },
        },
    }), /contract/);
});

test('timeline validation accepts WCL actor sentinels without weakening death target identity', () => {
    const report = validateTimelineResponse({
        data: {
            reportData: {
                report: {
                    fights: [{
                        id: 101,
                        encounterID: 10,
                        difficulty: 5,
                        kill: true,
                        startTime: 0,
                        endTime: 10000,
                        enemyNPCs: [{ id: 71, gameID: 257911 }],
                    }],
                    ...eventStreams({
                        casts: {
                            data: [{
                                fight: 101,
                                sourceID: -1,
                                targetID: -1,
                                abilityGameID: 20,
                                timestamp: 1000,
                                type: 'cast',
                            }],
                            nextPageTimestamp: null,
                        },
                        deaths: {
                            data: [{
                                fight: 101,
                                sourceID: -1,
                                targetID: 71,
                                abilityGameID: 0,
                                timestamp: 5000,
                                type: 'death',
                            }],
                            nextPageTimestamp: null,
                        },
                    }),
                },
            },
        },
    });
    assert.equal(report.casts.data[0].sourceID, -1);
    assert.equal(report.deaths.data[0].abilityGameID, 0);
});

test('timeline query requests actor identity without requesting WCL phase metadata', () => {
    assert.match(TIMELINE_FIGHTS_QUERY, /enemyNPCs\s*\{\s*id\s+gameID\s*\}/);
    assert.match(TIMELINE_FIGHTS_QUERY, /casts:\s*events\([\s\S]*dataType:\s*Casts/);
    assert.match(TIMELINE_FIGHTS_QUERY, /buffs:\s*events\([\s\S]*dataType:\s*Buffs/);
    assert.match(TIMELINE_FIGHTS_QUERY, /deaths:\s*events\([\s\S]*dataType:\s*Deaths/);
    assert.doesNotMatch(TIMELINE_FIGHTS_QUERY, /\bphases\b|phaseTransitions/);
});

test('client sends one page-one candidate request per encounter for every difficulty', async () => {
    const requests = [];
    const heroic = [{ duration: 5000, startTime: 1000, report: { code: runtimeCode(), fightID: 101 } }];
    const bodies = [
        { access_token: 'ephemeral' },
        { data: { worldData: { zones: [] } } },
        candidateResponse(new Map([[4, heroic]])),
    ];
    const client = new WarcraftLogsClient({
        clientID: 'client-canary',
        clientSecret: 'secret-canary',
        gate: { run: (request) => request() },
        fetchImpl: async (url, options) => {
            requests.push({ url, options });
            return response(bodies.shift());
        },
    });
    await client.discoverZones();
    const result = await client.candidateKills(10, 100, 200);
    assert.equal(requests.length, 3);
    assert.deepEqual(JSON.parse(requests[1].options.body), { query: DISCOVER_ZONES_QUERY, variables: {} });
    assert.deepEqual(JSON.parse(requests[2].options.body), {
        query: CANDIDATE_KILLS_QUERY,
        variables: { encounterID: 10, region: 'US', dateFilter: 'date.100.200' },
    });
    assert.deepEqual(result.get(4), heroic);
    assert.deepEqual(result.get(1), []);
});

test('timeline requests group fights and independently paginates and deduplicates event streams', async () => {
    const starts = [];
    const reportBody = (streams, reverse = false) => ({
        data: {
            reportData: {
                report: {
                    fights: (reverse ? [102, 101] : [101, 102]).map((id) => ({
                        id,
                        encounterID: id === 101 ? 10 : 11,
                        difficulty: 5,
                        kill: true,
                        startTime: 0,
                        endTime: 10000,
                        enemyNPCs: reverse
                            ? [{ id: 72, gameID: 9002 }, { id: 71, gameID: 9001 }]
                            : [{ id: 71, gameID: 9001 }, { id: 72, gameID: 9002 }],
                    })),
                    ...eventStreams(streams),
                },
            },
        },
    });
    const cast = {
        fight: 101,
        sourceID: 71,
        abilityGameID: 20,
        timestamp: 1000,
        type: 'cast',
    };
    const applied = {
        fight: 101,
        sourceID: 71,
        abilityGameID: 30,
        timestamp: 2000,
        type: 'applybuff',
    };
    const death = {
        fight: 101,
        sourceID: 72,
        targetID: 71,
        abilityGameID: 1,
        timestamp: 3000,
        type: 'death',
    };
    const bodies = [
        { access_token: 'ephemeral' },
        reportBody({
            casts: { data: [cast], nextPageTimestamp: 5000 },
            buffs: { data: [applied], nextPageTimestamp: null },
            deaths: { data: [death], nextPageTimestamp: null },
        }),
        reportBody({
            casts: { data: [{ ...cast, timestamp: 6000 }], nextPageTimestamp: null },
            buffs: { data: [applied], nextPageTimestamp: null },
            deaths: { data: [death], nextPageTimestamp: null },
        }, true),
    ];
    const client = new WarcraftLogsClient({
        clientID: 'client',
        clientSecret: 'secret',
        gate: { run: (request) => request() },
        fetchImpl: async (url, options) => {
            if (url.includes('/api/')) {
                const requestBody = JSON.parse(options.body);
                assert.equal(requestBody.query, TIMELINE_FIGHTS_QUERY);
                starts.push(requestBody.variables);
            }
            return response(bodies.shift());
        },
    });
    const result = await client.timelineFights(runtimeCode(), [101, 102]);
    assert.deepEqual(starts, [
        {
            reportCode: runtimeCode(),
            fightIDs: [101, 102],
            castStartTime: 0,
            buffStartTime: 0,
            deathStartTime: 0,
        },
        {
            reportCode: runtimeCode(),
            fightIDs: [101, 102],
            castStartTime: 5000,
            buffStartTime: 0,
            deathStartTime: 0,
        },
    ]);
    assert.deepEqual(result.events, [cast, applied, death, { ...cast, timestamp: 6000 }]);
});

test('credentials, token, and malformed-response canaries never appear in errors', async () => {
    const canaries = ['client-canary', 'secret-canary', 'token-canary', 'sample-canary'];
    const client = new WarcraftLogsClient({
        clientID: canaries[0],
        clientSecret: canaries[1],
        gate: { run: (request) => request() },
        fetchImpl: async () => response({ access_token: canaries[2], malformed: canaries[3] }),
    });
    let message = '';
    try {
        await client.discoverZones();
    } catch (error) {
        message = error.message;
    }
    for (const canary of canaries) {
        assert.equal(message.includes(canary), false);
    }
});

test('candidate contract failures identify the request without exposing response data', async () => {
    const client = new WarcraftLogsClient({
        clientID: 'client',
        clientSecret: 'secret',
        gate: { run: (request) => request() },
        fetchImpl: async (url) => {
            if (url.includes('/oauth/')) {
                return response({ access_token: 'ephemeral' });
            }
            return response(candidateResponse(new Map([[4, [{ malformed: 'sample-canary' }]]])));
        },
    });
    await assert.rejects(
        () => client.candidateKills(3455, 100, 200),
        (error) => error.message.includes('encounter 3455')
            && error.message.includes('difficulty 4')
            && !error.message.includes('sample-canary'),
    );
});

test('GraphQL requests retry transient HTTP failures without exposing response bodies', async () => {
    const responses = [
        response({ access_token: 'ephemeral' }),
        response({ private: 'response-canary' }, false, 503),
        response({ data: { worldData: { zones: [] } } }),
    ];
    const delays = [];
    const client = new WarcraftLogsClient({
        clientID: 'client',
        clientSecret: 'secret',
        gate: { run: (request) => request() },
        retrySleep: async (milliseconds) => { delays.push(milliseconds); },
        fetchImpl: async () => responses.shift(),
    });
    assert.deepEqual(await client.discoverZones(), []);
    assert.deepEqual(delays, [1000]);
});
