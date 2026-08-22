import {
    MAXIMUM_SAMPLES,
    MINIMUM_SAMPLES,
    SCHEMA_VERSION,
    WCL_DIFFICULTY_TO_WOW,
} from './constants.mjs';

const ROOT_FIELDS = ['schemaVersion', 'encounters'];
const ENCOUNTER_FIELDS = ['difficulties'];
const DIFFICULTY_FIELDS = ['phases'];
const PHASE_FIELDS = ['phaseID', 'name', 'isIntermission', 'occurrences'];
const OCCURRENCE_FIELDS = ['spellID', 'time', 'observations'];
const WOW_DIFFICULTIES = new Set(WCL_DIFFICULTY_TO_WOW.values());

function fail(path, message) {
    throw new Error(`Invalid boss timeline database at ${path}: ${message}`);
}

function isRecord(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function requireFields(value, fields, path) {
    if (!isRecord(value)) {
        fail(path, 'expected an object');
    }

    const actual = Object.keys(value).sort();
    const expected = [...fields].sort();
    if (actual.length !== expected.length || actual.some((field, index) => field !== expected[index])) {
        fail(path, `expected exactly ${expected.join(', ')}`);
    }
}

function requirePositiveInteger(value, path) {
    if (!Number.isInteger(value) || value <= 0) {
        fail(path, 'expected a positive integer');
    }
}

function requireNumericMap(value, path) {
    if (!isRecord(value)) {
        fail(path, 'expected a numeric-keyed object');
    }

    for (const key of Object.keys(value)) {
        const numericKey = Number(key);
        requirePositiveInteger(numericKey, `${path}[${key}]`);
        if (String(numericKey) !== key) {
            fail(`${path}[${key}]`, 'expected a canonical numeric key');
        }
    }
}

function validateOccurrence(occurrence, path) {
    requireFields(occurrence, OCCURRENCE_FIELDS, path);
    requirePositiveInteger(occurrence.spellID, `${path}.spellID`);
    if (!Number.isInteger(occurrence.time) || occurrence.time < 0) {
        fail(`${path}.time`, 'expected a non-negative integer');
    }
    if (!Number.isInteger(occurrence.observations)
        || occurrence.observations < MINIMUM_SAMPLES
        || occurrence.observations > MAXIMUM_SAMPLES) {
        fail(`${path}.observations`, `expected ${MINIMUM_SAMPLES} through ${MAXIMUM_SAMPLES}`);
    }
}

function validateOccurrences(occurrences, path) {
    if (!Array.isArray(occurrences)) {
        fail(path, 'expected an array');
    }

    let previous = null;
    for (let index = 0; index < occurrences.length; index += 1) {
        const occurrence = occurrences[index];
        validateOccurrence(occurrence, `${path}[${index + 1}]`);
        if (previous && (occurrence.time < previous.time
            || (occurrence.time === previous.time && occurrence.spellID < previous.spellID))) {
            fail(path, 'occurrences are not sorted by time and spellID');
        }
        previous = occurrence;
    }
}

function validatePhase(phase, path) {
    requireFields(phase, PHASE_FIELDS, path);
    requirePositiveInteger(phase.phaseID, `${path}.phaseID`);
    if (typeof phase.name !== 'string' || phase.name.length === 0) {
        fail(`${path}.name`, 'expected a non-empty string');
    }
    if (typeof phase.isIntermission !== 'boolean') {
        fail(`${path}.isIntermission`, 'expected a Boolean');
    }
    validateOccurrences(phase.occurrences, `${path}.occurrences`);
}

function validateDifficulty(difficulty, path) {
    requireFields(difficulty, DIFFICULTY_FIELDS, path);
    if (!Array.isArray(difficulty.phases) || difficulty.phases.length === 0) {
        fail(`${path}.phases`, 'expected a non-empty array');
    }
    for (let index = 0; index < difficulty.phases.length; index += 1) {
        validatePhase(difficulty.phases[index], `${path}.phases[${index + 1}]`);
    }
}

function validateEncounter(encounter, path) {
    requireFields(encounter, ENCOUNTER_FIELDS, path);
    requireNumericMap(encounter.difficulties, `${path}.difficulties`);
    if (Object.keys(encounter.difficulties).length === 0) {
        fail(`${path}.difficulties`, 'expected at least one difficulty');
    }
    for (const [key, difficulty] of Object.entries(encounter.difficulties)) {
        const difficultyID = Number(key);
        if (!WOW_DIFFICULTIES.has(difficultyID)) {
            fail(`${path}.difficulties[${key}]`, 'unsupported WoW raid difficulty');
        }
        validateDifficulty(difficulty, `${path}.difficulties[${key}]`);
    }
}

export function validateDatabase(database) {
    requireFields(database, ROOT_FIELDS, 'root');
    if (database.schemaVersion !== SCHEMA_VERSION) {
        fail('root.schemaVersion', `unsupported schema version ${database.schemaVersion}`);
    }
    requireNumericMap(database.encounters, 'root.encounters');
    for (const [key, encounter] of Object.entries(database.encounters)) {
        validateEncounter(encounter, `root.encounters[${key}]`);
    }
    return database;
}

