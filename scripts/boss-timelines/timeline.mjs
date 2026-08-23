import { MAXIMUM_SAMPLES, MINIMUM_SAMPLES } from './constants.mjs';
import { decidePhases } from './phase-deciders.mjs';

function phaseSignature(phases) {
    return JSON.stringify(phases.map((phase) => phase.id));
}

function eventIdentity(event) {
    return `${event.fight}\u0000${event.sourceID}\u0000${event.timestamp}\u0000${event.type}\u0000${event.abilityGameID}`;
}

function canonicalSpellID(eventSpellID, modules, aliases) {
    for (const bossMod of ['bigwigs', 'dbm']) {
        if (modules[bossMod].has(eventSpellID)) {
            return eventSpellID;
        }
        for (const [timerID, spellID] of aliases[bossMod]) {
            if (spellID === eventSpellID && modules[bossMod].has(timerID)) {
                return eventSpellID;
            }
        }
    }
    return null;
}

function attachEvents(fight, phases, events, modules, aliases) {
    const uniqueEvents = new Map();
    for (const event of events) {
        if (event.fight !== fight.id || (event.type !== 'begincast' && event.type !== 'cast')) {
            continue;
        }
        uniqueEvents.set(eventIdentity(event), event);
    }

    const normalized = phases.map(() => []);
    for (const event of uniqueEvents.values()) {
        const spellID = canonicalSpellID(event.abilityGameID, modules, aliases);
        if (!spellID || event.timestamp < fight.startTime || event.timestamp > fight.endTime) {
            continue;
        }
        let phaseIndex = null;
        for (let index = phases.length - 1; index >= 0; index -= 1) {
            if (event.timestamp >= phases[index].startTime) {
                phaseIndex = index;
                break;
            }
        }
        if (phaseIndex === null || event.timestamp > phases[phaseIndex].endTime) {
            continue;
        }
        normalized[phaseIndex].push({
            spellID,
            type: event.type,
            offset: event.timestamp - phases[phaseIndex].startTime,
        });
    }
    return normalized;
}

function clusterEvents(events) {
    const groups = new Map();
    for (const event of events) {
        const key = `${event.spellID}:${event.type}`;
        const values = groups.get(key) ?? [];
        values.push(event);
        groups.set(key, values);
    }
    const clustered = [];
    for (const values of groups.values()) {
        values.sort((left, right) => left.offset - right.offset);
        let previous = null;
        for (const value of values) {
            if (previous && value.offset - previous.offset <= 1000) {
                continue;
            }
            clustered.push(value);
            previous = value;
        }
    }
    return clustered.sort((left, right) => left.offset - right.offset || left.spellID - right.spellID);
}

export function evaluateFight({ fight, events, encounterID, difficulty, modules, aliases, phaseDecider }) {
    if (!fight.kill) {
        return { rejectionReason: 'not-a-kill' };
    }
    if (fight.encounterID !== encounterID) {
        return { rejectionReason: 'encounter-mismatch' };
    }
    if (fight.difficulty !== difficulty) {
        return { rejectionReason: 'difficulty-mismatch' };
    }
    const phases = decidePhases({
        encounterID,
        decider: phaseDecider,
        fight,
        events,
    });
    if (!phases) {
        return { rejectionReason: 'missing-canonical-phase-boundaries' };
    }
    const phaseEvents = attachEvents(fight, phases, events, modules, aliases).map(clusterEvents);
    return {
        normalizedFight: { fightID: fight.id, phases, phaseEvents, signature: phaseSignature(phases) },
    };
}

export function normalizeFight(argumentsList) {
    return evaluateFight(argumentsList).normalizedFight ?? null;
}

function median(values) {
    const sorted = [...values].sort((left, right) => left - right);
    const middle = Math.floor(sorted.length / 2);
    if (sorted.length % 2 === 1) {
        return sorted[middle];
    }
    return (sorted[middle - 1] + sorted[middle]) / 2;
}

function occurrenceSeries(fights, phaseIndex) {
    const series = new Map();
    for (const fight of fights) {
        const indexes = new Map();
        for (const event of fight.phaseEvents[phaseIndex]) {
            const anchorKey = `${event.spellID}:${event.type}`;
            const occurrenceIndex = (indexes.get(anchorKey) ?? 0) + 1;
            indexes.set(anchorKey, occurrenceIndex);
            const key = `${event.spellID}:${occurrenceIndex}`;
            let occurrence = series.get(key);
            if (!occurrence) {
                occurrence = { spellID: event.spellID, occurrenceIndex, begincast: [], cast: [] };
                series.set(key, occurrence);
            }
            occurrence[event.type].push(event.offset);
        }
    }
    return series;
}

function buildOccurrences(fights, phaseIndex) {
    const occurrences = [];
    for (const occurrence of occurrenceSeries(fights, phaseIndex).values()) {
        let observations = occurrence.begincast;
        if (observations.length < MINIMUM_SAMPLES) {
            observations = occurrence.cast;
        }
        if (observations.length < MINIMUM_SAMPLES) {
            continue;
        }
        occurrences.push({
            spellID: occurrence.spellID,
            time: Math.floor((median(observations) / 1000) + 0.5),
            observations: observations.length,
            occurrenceIndex: occurrence.occurrenceIndex,
        });
    }
    occurrences.sort((left, right) => left.time - right.time
        || left.spellID - right.spellID
        || left.occurrenceIndex - right.occurrenceIndex);
    return occurrences.map(({ occurrenceIndex, ...occurrence }) => occurrence);
}

export function buildDifficulty(fights) {
    if (fights.length < MINIMUM_SAMPLES || fights.length > MAXIMUM_SAMPLES) {
        return null;
    }
    const signature = fights[0].signature;
    if (fights.some((fight) => fight.signature !== signature)) {
        throw new Error('Selected kills contain inconsistent phase sequences');
    }
    const phases = [];
    for (let phaseIndex = 0; phaseIndex < fights[0].phases.length; phaseIndex += 1) {
        const metadata = fights[0].phases[phaseIndex];
        phases.push({
            phaseID: metadata.id,
            name: metadata.name,
            isIntermission: metadata.isIntermission,
            occurrences: buildOccurrences(fights, phaseIndex),
        });
    }
    return { phases };
}
