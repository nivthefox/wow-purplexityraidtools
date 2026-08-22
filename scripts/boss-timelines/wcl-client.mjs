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
  $difficulty: Int!
  $region: String!
  $dateFilter: String!
  $page: Int!
) {
  worldData {
    encounter(id: $encounterID) {
      fightRankings(
        difficulty: $difficulty
        serverRegion: $region
        metric: execution
        filter: $dateFilter
        page: $page
      )
    }
  }
}`;

export const TIMELINE_FIGHTS_QUERY = `query TimelineFights(
  $reportCode: String!
  $fightIDs: [Int!]!
  $eventStartTime: Float!
) {
  reportData {
    report(code: $reportCode) {
      phases {
        encounterID
        phases {
          id
          name
          isIntermission
        }
      }
      fights(fightIDs: $fightIDs, killType: Kills) {
        id
        encounterID
        difficulty
        kill
        startTime
        endTime
        phaseTransitions {
          id
          startTime
        }
      }
      events(
        fightIDs: $fightIDs
        dataType: Casts
        hostilityType: Enemies
        startTime: $eventStartTime
        translate: false
        limit: 10000
      ) {
        data
        nextPageTimestamp
      }
    }
  }
}`;

function contractError(name) {
    throw new Error(`Warcraft Logs ${name} response did not match the required contract`);
}

function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function isPositiveInteger(value) {
    return Number.isInteger(value) && value > 0;
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
        if ((zone.difficulties ?? []).some((difficulty) => !isRecord(difficulty) || !isPositiveInteger(difficulty.id))) {
            contractError('zone discovery');
        }
        if ((zone.encounters ?? []).some((encounter) => !isRecord(encounter)
            || !isPositiveInteger(encounter.id) || !isPositiveInteger(encounter.journalID))) {
            contractError('zone discovery');
        }
    }
    return zones.map((zone) => ({
        ...zone,
        difficulties: zone.difficulties ?? [],
        encounters: zone.encounters ?? [],
    }));
}

export function validateCandidateResponse(response) {
    const rankings = response?.data?.worldData?.encounter?.fightRankings;
    if (!isRecord(rankings) || !Number.isInteger(rankings.page) || rankings.page < 1
        || typeof rankings.hasMorePages !== 'boolean' || !Array.isArray(rankings.rankings)) {
        contractError('candidate rankings');
    }
    for (const ranking of rankings.rankings) {
        if (!isRecord(ranking) || !isFiniteNumber(ranking.duration) || ranking.duration <= 0
            || !isFiniteNumber(ranking.startTime) || !isRecord(ranking.report)
            || typeof ranking.report.code !== 'string' || ranking.report.code.length === 0
            || !isPositiveInteger(ranking.report.fightID)) {
            contractError('candidate rankings');
        }
    }
    return rankings;
}

function validatePhaseDefinitions(phases) {
    if (!Array.isArray(phases)) {
        return false;
    }
    return phases.every((encounterPhases) => isRecord(encounterPhases)
        && isPositiveInteger(encounterPhases.encounterID)
        && Array.isArray(encounterPhases.phases)
        && encounterPhases.phases.every((phase) => isRecord(phase)
            && isPositiveInteger(phase.id)
            && typeof phase.name === 'string'
            && phase.name.length > 0
            && typeof phase.isIntermission === 'boolean'));
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
        && (fight.phaseTransitions === null || Array.isArray(fight.phaseTransitions))
        && (fight.phaseTransitions ?? []).every((transition) => isRecord(transition)
            && isPositiveInteger(transition.id)
            && isFiniteNumber(transition.startTime)));
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
        && isPositiveInteger(event.abilityGameID)
        && isFiniteNumber(event.timestamp)
        && typeof event.type === 'string');
}

export function validateTimelineResponse(response) {
    const report = response?.data?.reportData?.report;
    if (!isRecord(report) || !validatePhaseDefinitions(report.phases)
        || !validateFights(report.fights) || !validateEvents(report.events)) {
        contractError('fight timeline');
    }
    return {
        ...report,
        fights: report.fights.map((fight) => ({
            ...fight,
            phaseTransitions: fight.phaseTransitions ?? [],
        })),
    };
}

function timelineMetadataSignature(phases, fights) {
    const normalizedPhases = phases.map((encounterPhases) => ({
        encounterID: encounterPhases.encounterID,
        phases: encounterPhases.phases
            .map((phase) => ({ id: phase.id, name: phase.name, isIntermission: phase.isIntermission }))
            .sort((left, right) => left.id - right.id),
    })).sort((left, right) => left.encounterID - right.encounterID);
    const normalizedFights = fights.map((fight) => ({
        id: fight.id,
        encounterID: fight.encounterID,
        difficulty: fight.difficulty,
        kill: fight.kill,
        startTime: fight.startTime,
        endTime: fight.endTime,
        phaseTransitions: fight.phaseTransitions
            .map((transition) => ({ id: transition.id, startTime: transition.startTime }))
            .sort((left, right) => left.startTime - right.startTime || left.id - right.id),
    })).sort((left, right) => left.id - right.id);
    return JSON.stringify({ phases: normalizedPhases, fights: normalizedFights });
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
    constructor({ clientID, clientSecret, fetchImpl = fetch, gate = new SerializedRequestGate() }) {
        if (!clientID || !clientSecret) {
            throw new Error('WCL_CLIENT_ID and WCL_CLIENT_SECRET are required');
        }
        this.clientID = clientID;
        this.clientSecret = clientSecret;
        this.fetchImpl = fetchImpl;
        this.gate = gate;
        this.token = null;
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
        const response = await this.gate.run(() => this.fetchImpl('https://www.warcraftlogs.com/api/v2/client', {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${this.token}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ query, variables }),
        }));
        if (!response.ok) {
            throw new Error('Warcraft Logs GraphQL request failed');
        }
        const body = await response.json();
        if (!isRecord(body) || body.errors) {
            contractError('GraphQL');
        }
        return body;
    }

    async discoverZones() {
        return validateZonesResponse(await this.graphql(DISCOVER_ZONES_QUERY, {}));
    }

    async candidateKills(encounterID, difficulty, startTime, endTime) {
        const rankings = [];
        let page = 1;
        while (true) {
            const variables = {
                encounterID,
                difficulty,
                region: 'US',
                dateFilter: `date.${startTime}.${endTime}`,
                page,
            };
            const result = validateCandidateResponse(await this.graphql(CANDIDATE_KILLS_QUERY, variables));
            if (result.page !== page) {
                contractError('candidate rankings');
            }
            rankings.push(...result.rankings);
            if (!result.hasMorePages) {
                return rankings;
            }
            page += 1;
        }
    }

    async timelineFights(reportCode, fightIDs) {
        const events = [];
        let eventStartTime = 0;
        let phaseDefinitions = null;
        let fights = null;
        let metadataSignature = null;
        while (true) {
            const variables = { reportCode, fightIDs, eventStartTime };
            const report = validateTimelineResponse(await this.graphql(TIMELINE_FIGHTS_QUERY, variables));
            if (phaseDefinitions === null) {
                phaseDefinitions = report.phases;
                fights = report.fights;
                metadataSignature = timelineMetadataSignature(report.phases, report.fights);
            } else if (metadataSignature !== timelineMetadataSignature(report.phases, report.fights)) {
                contractError('fight timeline');
            }
            events.push(...report.events.data);
            if (report.events.nextPageTimestamp === null || report.events.nextPageTimestamp === undefined) {
                return { phaseDefinitions, fights, events };
            }
            if (report.events.nextPageTimestamp <= eventStartTime) {
                contractError('fight timeline');
            }
            eventStartTime = report.events.nextPageTimestamp;
        }
    }
}
