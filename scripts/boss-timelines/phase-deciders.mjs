import { LAIRS_PHASE_DECIDERS } from './encounters/Lairs.mjs';
import { THE_VENOMOUS_ABYSS_PHASE_DECIDERS } from './encounters/TheVenomousAbyss.mjs';

const PHASE_DECIDERS = new Map([
    ...LAIRS_PHASE_DECIDERS,
    ...THE_VENOMOUS_ABYSS_PHASE_DECIDERS,
]);

function invalidDecider(encounterID, detail) {
    throw new Error(`Encounter ${encounterID} phase decider returned invalid phases: ${detail}`);
}

function orderedFightEvents(events, fightID) {
    const matching = [];
    for (let index = 0; index < events.length; index += 1) {
        const event = events[index];
        if (event.fight === fightID) {
            matching.push({ event, index });
        }
    }
    matching.sort((left, right) => left.event.timestamp - right.event.timestamp
        || left.index - right.index);
    return matching.map(({ event }) => event);
}

function validatePhase(phase, index, encounterID) {
    if (phase === null || typeof phase !== 'object' || Array.isArray(phase)) {
        invalidDecider(encounterID, `phase ${index + 1} is not a record`);
    }
    if (phase.id !== index + 1) {
        invalidDecider(encounterID, `phase ${index + 1} has a non-canonical ID`);
    }
    if (typeof phase.name !== 'string' || phase.name.length === 0) {
        invalidDecider(encounterID, `phase ${index + 1} has an invalid name`);
    }
    if (typeof phase.isIntermission !== 'boolean') {
        invalidDecider(encounterID, `phase ${index + 1} has an invalid intermission flag`);
    }
    if (!Number.isFinite(phase.startTime) || !Number.isFinite(phase.endTime)
        || phase.endTime <= phase.startTime
    ) {
        invalidDecider(encounterID, `phase ${index + 1} has invalid boundaries`);
    }
}

function validatePhases(phases, fight, encounterID) {
    if (!Array.isArray(phases) || phases.length === 0) {
        invalidDecider(encounterID, 'expected at least one phase');
    }
    for (let index = 0; index < phases.length; index += 1) {
        validatePhase(phases[index], index, encounterID);
    }
    if (phases[0].startTime !== fight.startTime) {
        invalidDecider(encounterID, 'the first phase does not start with the fight');
    }
    if (phases.at(-1).endTime !== fight.endTime) {
        invalidDecider(encounterID, 'the final phase does not end with the fight');
    }
    for (let index = 1; index < phases.length; index += 1) {
        if (phases[index - 1].endTime !== phases[index].startTime) {
            invalidDecider(encounterID, `phases ${index} and ${index + 1} are not contiguous`);
        }
    }
    return phases;
}

export function getPhaseDecider(encounterID) {
    return PHASE_DECIDERS.get(encounterID) ?? null;
}

export function decidePhases({ encounterID, decider, fight, events }) {
    const phases = decider({ fight, events: orderedFightEvents(events, fight.id) });
    if (phases === null) {
        return null;
    }
    return validatePhases(phases, fight, encounterID);
}
