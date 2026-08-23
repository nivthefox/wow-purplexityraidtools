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

test('timeline validation normalizes nullable single-phase transitions to an empty array', () => {
    const report = validateTimelineResponse({
        data: {
            reportData: {
                report: {
                    phases: [{ encounterID: 10, phases: [{ id: 1, name: 'One', isIntermission: false }] }],
                    fights: [{
                        id: 101,
                        encounterID: 10,
                        difficulty: 5,
                        kill: true,
                        startTime: 0,
                        endTime: 10000,
                        phaseTransitions: null,
                    }],
                    events: { data: [], nextPageTimestamp: null },
                },
            },
        },
    });
    assert.deepEqual(report.fights[0].phaseTransitions, []);
});

test('client sends exact discovery and paginated candidate queries with the rolling window variables', async () => {
    const requests = [];
    const bodies = [
        { access_token: 'ephemeral' },
        { data: { worldData: { zones: [] } } },
        {
            data: {
                worldData: {
                    encounter: {
                        fightRankings: {
                            page: 1,
                            hasMorePages: true,
                            rankings: [{ duration: 5000, startTime: 1000, report: { code: runtimeCode(), fightID: 101 } }],
                        },
                    },
                },
            },
        },
        {
            data: {
                worldData: {
                    encounter: { fightRankings: { page: 2, hasMorePages: false, rankings: [] } },
                },
            },
        },
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
    await client.candidateKills(10, 5, 100, 200);
    assert.deepEqual(JSON.parse(requests[1].options.body), { query: DISCOVER_ZONES_QUERY, variables: {} });
    assert.deepEqual(JSON.parse(requests[2].options.body), {
        query: CANDIDATE_KILLS_QUERY,
        variables: { encounterID: 10, difficulty: 5, region: 'US', dateFilter: 'date.100.200', page: 1 },
    });
    assert.equal(JSON.parse(requests[3].options.body).variables.page, 2);
});

test('candidate queries split long sampling periods into adjacent daily windows', async () => {
    const requests = [];
    const bodies = [
        { access_token: 'ephemeral' },
        { data: { worldData: { encounter: { fightRankings: { page: 1, hasMorePages: false, rankings: [] } } } } },
        { data: { worldData: { encounter: { fightRankings: { page: 1, hasMorePages: false, rankings: [] } } } } },
    ];
    const client = new WarcraftLogsClient({
        clientID: 'client',
        clientSecret: 'secret',
        gate: { run: (request) => request() },
        fetchImpl: async (url, options) => {
            if (url.includes('/api/')) {
                requests.push(JSON.parse(options.body).variables);
            }
            return response(bodies.shift());
        },
    });
    await client.candidateKills(10, 5, 100, 172800100);
    assert.deepEqual(requests, [
        { encounterID: 10, difficulty: 5, region: 'US', dateFilter: 'date.100.86400100', page: 1 },
        { encounterID: 10, difficulty: 5, region: 'US', dateFilter: 'date.86400100.172800100', page: 1 },
    ]);
});

test('timeline requests group fights, tolerates metadata reordering, and paginates events from zero', async () => {
    const starts = [];
    const reportBody = (nextPageTimestamp, eventStartTime, reverse = false) => ({
        data: {
            reportData: {
                report: {
                    phases: (reverse ? [
                        { encounterID: 11, phases: [{ id: 1, name: 'Other', isIntermission: false }] },
                        { encounterID: 10, phases: [{ id: 1, name: 'One', isIntermission: false }] },
                    ] : [
                        { encounterID: 10, phases: [{ id: 1, name: 'One', isIntermission: false }] },
                        { encounterID: 11, phases: [{ id: 1, name: 'Other', isIntermission: false }] },
                    ]),
                    fights: (reverse ? [102, 101] : [101, 102]).map((id) => ({
                        id,
                        encounterID: id === 101 ? 10 : 11,
                        difficulty: 5,
                        kill: true,
                        startTime: 0,
                        endTime: 10000,
                        phaseTransitions: [],
                    })),
                    events: {
                        data: [{ fight: 101, abilityGameID: 20, timestamp: eventStartTime, type: 'cast' }],
                        nextPageTimestamp,
                    },
                },
            },
        },
    });
    const bodies = [{ access_token: 'ephemeral' }, reportBody(5000, 0), reportBody(null, 5000, true)];
    const client = new WarcraftLogsClient({
        clientID: 'client',
        clientSecret: 'secret',
        gate: { run: (request) => request() },
        fetchImpl: async (url, options) => {
            if (url.includes('/api/')) {
                const requestBody = JSON.parse(options.body);
                assert.equal(requestBody.query, TIMELINE_FIGHTS_QUERY);
                starts.push(requestBody.variables.eventStartTime);
            }
            return response(bodies.shift());
        },
    });
    const result = await client.timelineFights(runtimeCode(), [101, 102]);
    assert.deepEqual(starts, [0, 5000]);
    assert.equal(result.events.length, 2);
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
            return response({
                data: {
                    worldData: {
                        encounter: {
                            fightRankings: {
                                page: 1,
                                hasMorePages: false,
                                rankings: [{ malformed: 'sample-canary' }],
                            },
                        },
                    },
                },
            });
        },
    });
    await assert.rejects(
        () => client.candidateKills(3455, 4, 100, 200),
        (error) => error.message.includes('encounter 3455, difficulty 4, page 1')
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
