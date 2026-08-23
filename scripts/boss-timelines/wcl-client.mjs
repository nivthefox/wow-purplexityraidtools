import { REQUEST_INTERVAL_MS } from './constants.mjs';

export const DISCOVER_ZONES_QUERY = `query DiscoverZones {
  worldData {
    zones {
      id
      frozen
      difficulties {
        id
      }
      encounters {
        id
        journalID
      }
    }
  }
}`;

export const CANDIDATE_KILLS_QUERY = `query CandidateKills(
  $encounterID: Int!
  $region: String!
  $dateFilter: String!
) {
  worldData {
    encounter(id: $encounterID) {
      lfr: fightRankings(
        difficulty: 1
        serverRegion: $region
        metric: execution
        filter: $dateFilter
        page: 1
      )
      normal: fightRankings(
        difficulty: 3
        serverRegion: $region
        metric: execution
        filter: $dateFilter
        page: 1
      )
      heroic: fightRankings(
        difficulty: 4
        serverRegion: $region
        metric: execution
        filter: $dateFilter
        page: 1
      )
      mythic: fightRankings(
        difficulty: 5
        serverRegion: $region
        metric: execution
        filter: $dateFilter
        page: 1
      )
    }
  }
}`;

const CANDIDATE_DIFFICULTY_FIELDS = new Map([
    [1, 'lfr'],
    [3, 'normal'],
    [4, 'heroic'],
    [5, 'mythic'],
]);

export const TIMELINE_FIGHTS_QUERY = `query TimelineFights(
  $reportCode: String!
  $fightIDs: [Int!]!
  $castStartTime: Float!
  $buffStartTime: Float!
  $deathStartTime: Float!
) {
  reportData {
    report(code: $reportCode) {
      fights(fightIDs: $fightIDs, killType: Kills) {
        id
        encounterID
        difficulty
        kill
        startTime
        endTime
        enemyNPCs {
          id
          gameID
        }
      }
      casts: events(
        fightIDs: $fightIDs
        dataType: Casts
        hostilityType: Enemies
        startTime: $castStartTime
        translate: false
        limit: 10000
      ) {
        data
        nextPageTimestamp
      }
      buffs: events(
        fightIDs: $fightIDs
        dataType: Buffs
        hostilityType: Enemies
        startTime: $buffStartTime
        translate: false
        limit: 10000
      ) {
        data
        nextPageTimestamp
      }
      deaths: events(
        fightIDs: $fightIDs
        dataType: Deaths
        hostilityType: Enemies
        startTime: $deathStartTime
        translate: false
        limit: 10000
      ) {
        data
        nextPageTimestamp
      }
    }
  }
}`;

function contractError(name, detail = null) {
    const suffix = detail ? `: ${detail}` : '';
    throw new Error(`Warcraft Logs ${name} response did not match the required contract${suffix}`);
}

function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isPositiveInteger(value) {
    return Number.isInteger(value) && value > 0;
}

function isNonNegativeInteger(value) {
    return Number.isInteger(value) && value >= 0;
}

function isFiniteNumber(value) {
    return typeof value === 'number' && Number.isFinite(value);
}

export function validateZonesResponse(response) {
    const zones = response?.data?.worldData?.zones;
    if (!Array.isArray(zones)) {
        contractError('zone discovery');
    }
    for (const zone of zones) {
        if (!isRecord(zone) || !isPositiveInteger(zone.id) || typeof zone.frozen !== 'boolean'
            || (zone.difficulties !== null && !Array.isArray(zone.difficulties))
            || (zone.encounters !== null && !Array.isArray(zone.encounters))) {
            contractError('zone discovery');
        }
        if ((zone.difficulties ?? []).some((difficulty) => !isRecord(difficulty) || !Number.isInteger(difficulty.id))) {
            contractError('zone discovery');
        }
        if ((zone.encounters ?? []).some((encounter) => !isRecord(encounter)
            || !isPositiveInteger(encounter.id) || !Number.isInteger(encounter.journalID))) {
            contractError('zone discovery');
        }
    }
    return zones.map((zone) => ({
        ...zone,
        difficulties: zone.difficulties ?? [],
        encounters: zone.encounters ?? [],
    }));
}

function validateCandidateRankings(rankings, difficulty) {
    if (!isRecord(rankings) || !Number.isInteger(rankings.page) || rankings.page < 1
        || typeof rankings.hasMorePages !== 'boolean' || !Array.isArray(rankings.rankings)) {
        contractError('candidate rankings', `difficulty ${difficulty} has invalid pagination metadata`);
    }
    if (rankings.page !== 1) {
        contractError('candidate rankings', `difficulty ${difficulty} returned an unexpected page number`);
    }
    for (const [index, ranking] of rankings.rankings.entries()) {
        if (!isRecord(ranking)) {
            contractError('candidate rankings', `difficulty ${difficulty} ranking ${index} is not a record`);
        }
        if (!isFiniteNumber(ranking.duration) || ranking.duration <= 0) {
            contractError('candidate rankings', `difficulty ${difficulty} ranking ${index} has an invalid duration`);
        }
        if (!isFiniteNumber(ranking.startTime)) {
            contractError('candidate rankings', `difficulty ${difficulty} ranking ${index} has an invalid start time`);
        }
        if (!isRecord(ranking.report)) {
            contractError('candidate rankings', `difficulty ${difficulty} ranking ${index} has an invalid report`);
        }
        if (typeof ranking.report.code !== 'string' || ranking.report.code.length === 0) {
            contractError('candidate rankings', `difficulty ${difficulty} ranking ${index} has an invalid report code`);
        }
        if (!isPositiveInteger(ranking.report.fightID)) {
            contractError('candidate rankings', `difficulty ${difficulty} ranking ${index} has an invalid fight ID`);
        }
    }
    return rankings.rankings;
}

export function validateCandidateResponse(response) {
    const encounter = response?.data?.worldData?.encounter;
    if (!isRecord(encounter)) {
        contractError('candidate rankings', 'invalid encounter result');
    }
    const byDifficulty = new Map();
    for (const [difficulty, field] of CANDIDATE_DIFFICULTY_FIELDS) {
        byDifficulty.set(difficulty, validateCandidateRankings(encounter[field], difficulty));
    }
    return byDifficulty;
}

function validateFights(fights) {
    if (!Array.isArray(fights)) {
        return false;
    }
    return fights.every((fight) => isRecord(fight)
        && isPositiveInteger(fight.id)
        && isPositiveInteger(fight.encounterID)
        && isPositiveInteger(fight.difficulty)
        && typeof fight.kill === 'boolean'
        && isFiniteNumber(fight.startTime)
        && isFiniteNumber(fight.endTime)
        && fight.endTime > fight.startTime
        && (fight.enemyNPCs === null || Array.isArray(fight.enemyNPCs))
        && (fight.enemyNPCs ?? []).every((actor) => isRecord(actor)
            && isPositiveInteger(actor.id)
            && isPositiveInteger(actor.gameID)));
}

function validateEvents(events) {
    if (!isRecord(events) || !Array.isArray(events.data)) {
        return false;
    }
    if (events.nextPageTimestamp !== null && events.nextPageTimestamp !== undefined
        && !isFiniteNumber(events.nextPageTimestamp)) {
        return false;
    }
    return events.data.every((event) => isRecord(event)
        && isPositiveInteger(event.fight)
        && Number.isInteger(event.sourceID)
        && isNonNegativeInteger(event.abilityGameID)
        && (event.targetID === undefined || Number.isInteger(event.targetID))
        && (event.type !== 'death' || isPositiveInteger(event.targetID))
        && isFiniteNumber(event.timestamp)
        && typeof event.type === 'string');
}

export function validateTimelineResponse(response) {
    const report = response?.data?.reportData?.report;
    if (!isRecord(report) || !validateFights(report.fights)
        || !validateEvents(report.casts)
        || !validateEvents(report.buffs)
        || !validateEvents(report.deaths)
    ) {
        contractError('fight timeline');
    }
    return {
        ...report,
        fights: report.fights.map((fight) => ({
            ...fight,
            enemyNPCs: fight.enemyNPCs ?? [],
        })),
    };
}

function timelineMetadataSignature(fights) {
    const normalizedFights = fights.map((fight) => ({
        id: fight.id,
        encounterID: fight.encounterID,
        difficulty: fight.difficulty,
        kill: fight.kill,
        startTime: fight.startTime,
        endTime: fight.endTime,
        enemyNPCs: fight.enemyNPCs
            .map((actor) => ({ id: actor.id, gameID: actor.gameID }))
            .sort((left, right) => left.id - right.id || left.gameID - right.gameID),
    })).sort((left, right) => left.id - right.id);
    return JSON.stringify({ fights: normalizedFights });
}

function timelineEventIdentity(event) {
    return `${event.fight}\u0000${event.sourceID}\u0000${event.targetID ?? ''}`
        + `\u0000${event.timestamp}\u0000${event.type}\u0000${event.abilityGameID}`;
}

export class SerializedRequestGate {
    constructor({ now = () => Date.now(), sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)) } = {}) {
        this.now = now;
        this.sleep = sleep;
        this.lastStartTime = null;
        this.pending = Promise.resolve();
    }

    async run(request) {
        const turn = this.pending.then(async () => {
            if (this.lastStartTime !== null) {
                const wait = REQUEST_INTERVAL_MS - (this.now() - this.lastStartTime);
                if (wait > 0) {
                    await this.sleep(wait);
                }
            }
            this.lastStartTime = this.now();
            return request();
        });
        this.pending = turn.then(() => undefined, () => undefined);
        return turn;
    }
}

export class WarcraftLogsClient {
    constructor({
        clientID,
        clientSecret,
        fetchImpl = fetch,
        gate = new SerializedRequestGate(),
        retrySleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)),
    }) {
        if (!clientID || !clientSecret) {
            throw new Error('WCL_CLIENT_ID and WCL_CLIENT_SECRET are required');
        }
        this.clientID = clientID;
        this.clientSecret = clientSecret;
        this.fetchImpl = fetchImpl;
        this.gate = gate;
        this.retrySleep = retrySleep;
        this.token = null;
    }

    async graphqlResponse(options) {
        for (let attempt = 0; attempt < 4; attempt += 1) {
            const response = await this.gate.run(() => this.fetchImpl('https://www.warcraftlogs.com/api/v2/client', options));
            if (response.ok) {
                return response;
            }
            const retryable = response.status === 429 || response.status >= 500;
            if (!retryable || attempt === 3) {
                throw new Error(`Warcraft Logs GraphQL request failed with HTTP ${response.status ?? 'unknown'}`);
            }
            const retryAfterHeader = response.headers?.get?.('retry-after');
            const retryAfter = Number(retryAfterHeader);
            const delay = retryAfterHeader !== null && retryAfterHeader !== undefined
                && Number.isFinite(retryAfter) && retryAfter >= 0
                ? retryAfter * 1000
                : 1000 * (2 ** attempt);
            await this.retrySleep(delay);
        }
        throw new Error('Warcraft Logs GraphQL request failed');
    }

    async authenticate() {
        const authorization = Buffer.from(`${this.clientID}:${this.clientSecret}`, 'utf8').toString('base64');
        const response = await this.gate.run(() => this.fetchImpl('https://www.warcraftlogs.com/oauth/token', {
            method: 'POST',
            headers: {
                Authorization: `Basic ${authorization}`,
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: 'grant_type=client_credentials',
        }));
        if (!response.ok) {
            throw new Error('Warcraft Logs authentication failed');
        }
        const body = await response.json();
        if (!isRecord(body) || typeof body.access_token !== 'string' || body.access_token.length === 0) {
            contractError('authentication');
        }
        this.token = body.access_token;
    }

    async graphql(query, variables) {
        if (!this.token) {
            await this.authenticate();
        }
        const response = await this.graphqlResponse({
            method: 'POST',
            headers: {
                Authorization: `Bearer ${this.token}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ query, variables }),
        });
        const body = await response.json();
        if (!isRecord(body) || body.errors) {
            contractError('GraphQL');
        }
        return body;
    }

    async discoverZones() {
        return validateZonesResponse(await this.graphql(DISCOVER_ZONES_QUERY, {}));
    }

    async candidateKills(encounterID, startTime, endTime) {
        const variables = {
            encounterID,
            region: 'US',
            dateFilter: `date.${startTime}.${endTime}`,
        };
        try {
            return validateCandidateResponse(await this.graphql(CANDIDATE_KILLS_QUERY, variables));
        } catch (error) {
            throw new Error(
                `Warcraft Logs candidate rankings failed for encounter ${encounterID}: ${error.message}`,
            );
        }
    }

    async timelineFights(reportCode, fightIDs) {
        const events = new Map();
        const startTimes = { casts: 0, buffs: 0, deaths: 0 };
        const completed = { casts: false, buffs: false, deaths: false };
        let fights = null;
        let metadataSignature = null;
        while (true) {
            const variables = {
                reportCode,
                fightIDs,
                castStartTime: startTimes.casts,
                buffStartTime: startTimes.buffs,
                deathStartTime: startTimes.deaths,
            };
            const report = validateTimelineResponse(await this.graphql(TIMELINE_FIGHTS_QUERY, variables));
            if (fights === null) {
                fights = report.fights;
                metadataSignature = timelineMetadataSignature(report.fights);
            } else if (metadataSignature !== timelineMetadataSignature(report.fights)) {
                contractError('fight timeline');
            }
            for (const streamName of Object.keys(startTimes)) {
                const stream = report[streamName];
                for (const event of stream.data) {
                    events.set(timelineEventIdentity(event), event);
                }
                if (completed[streamName]) {
                    continue;
                }
                const nextPageTimestamp = stream.nextPageTimestamp;
                if (nextPageTimestamp === null || nextPageTimestamp === undefined) {
                    completed[streamName] = true;
                    continue;
                }
                if (nextPageTimestamp <= startTimes[streamName]) {
                    contractError('fight timeline');
                }
                startTimes[streamName] = nextPageTimestamp;
            }
            if (Object.values(completed).every(Boolean)) {
                return { fights, events: [...events.values()] };
            }
        }
    }
}
