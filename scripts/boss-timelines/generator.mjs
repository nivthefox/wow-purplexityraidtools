import { BOSS_TIMELINE_ALIASES } from './aliases.mjs';
import { MAXIMUM_SAMPLES, MINIMUM_SAMPLES, SCHEMA_VERSION, WCL_DIFFICULTY_TO_WOW } from './constants.mjs';
import { discoverCurrentTier } from './discovery.mjs';
import { validateDatabase } from './schema.mjs';
import { buildDifficulty, normalizeFight } from './timeline.mjs';

const WOW_DIFFICULTY_NAMES = new Map([
    [17, 'LFR'],
    [14, 'Normal'],
    [15, 'Heroic'],
    [16, 'Mythic'],
]);

function candidateIdentity(candidate) {
    return `${candidate.report.code}\u0000${candidate.report.fightID}`;
}

function groupCandidatesByReport(candidates) {
    const groups = new Map();
    for (const candidate of candidates) {
        const values = groups.get(candidate.report.code) ?? [];
        values.push(candidate);
        groups.set(candidate.report.code, values);
    }
    return groups;
}

async function selectEligibleKills(client, candidates, encounterID, difficulty, modules, aliases) {
    const groups = groupCandidatesByReport(candidates);
    const loadedReports = new Map();
    const selected = [];
    let selectedSignature = null;

    for (const candidate of candidates) {
        const reportCode = candidate.report.code;
        let normalizedByIdentity = loadedReports.get(reportCode);
        if (!normalizedByIdentity) {
            const reportCandidates = groups.get(reportCode);
            const fightIDs = reportCandidates.map((value) => value.report.fightID).sort((left, right) => left - right);
            const report = await client.timelineFights(reportCode, fightIDs);
            const fightsByID = new Map(report.fights.map((fight) => [fight.id, fight]));
            normalizedByIdentity = new Map();
            for (const reportCandidate of reportCandidates) {
                const fight = fightsByID.get(reportCandidate.report.fightID);
                if (!fight) {
                    continue;
                }
                const normalized = normalizeFight({
                    fight,
                    phaseDefinitions: report.phaseDefinitions,
                    events: report.events,
                    encounterID,
                    difficulty,
                    modules,
                    aliases,
                });
                if (normalized) {
                    normalizedByIdentity.set(candidateIdentity(reportCandidate), normalized);
                }
            }
            loadedReports.set(reportCode, normalizedByIdentity);
        }

        const normalized = normalizedByIdentity.get(candidateIdentity(candidate));
        if (!normalized) {
            continue;
        }
        selectedSignature ??= normalized.signature;
        if (normalized.signature !== selectedSignature) {
            continue;
        }
        selected.push(normalized);
        if (selected.length === MAXIMUM_SAMPLES) {
            break;
        }
    }
    return selected;
}

function hasOccurrences(difficulty) {
    return difficulty.phases.some((phase) => phase.occurrences.length > 0);
}

function existingDifficulty(database, encounterID, difficultyID) {
    return database.encounters[encounterID]?.difficulties[difficultyID] ?? null;
}

function generationFailure(message) {
    const error = new Error(message);
    error.code = 'BOSS_TIMELINE_GENERATION_FAILED';
    return error;
}

function difficultyContext(omission) {
    const name = WOW_DIFFICULTY_NAMES.get(omission.wowDifficulty);
    return `encounter ${omission.encounterID}, ${name} difficulty (WoW ${omission.wowDifficulty}, WCL ${omission.wclDifficulty})`;
}

export function formatOmission(omission) {
    if (omission.reason === 'missing-boss-module') {
        return `Boss timeline omitted encounter ${omission.encounterID} (journal ${omission.journalID}): neither boss mod has a matching module.`;
    }
    const context = difficultyContext(omission);
    if (omission.reason === 'insufficient-candidates') {
        return `Boss timeline omitted ${context}: found ${omission.candidateCount} page-one candidates; at least ${MINIMUM_SAMPLES} are required.`;
    }
    if (omission.reason === 'insufficient-valid-kills') {
        return `Boss timeline omitted ${context}: validated ${omission.validKillCount} of ${omission.candidateCount} page-one candidates; at least ${MINIMUM_SAMPLES} valid kills are required.`;
    }
    if (omission.reason === 'no-qualifying-abilities') {
        return `Boss timeline omitted ${context}: ${omission.validKillCount} valid kills produced no qualifying boss abilities.`;
    }
    throw generationFailure('Boss timeline omission reason is malformed');
}

function indexBossModulesByEncounterID(bossModules) {
    const byEncounterID = new Map();
    for (const modules of bossModules.values()) {
        if (!modules.encounterID) {
            continue;
        }
        const existing = byEncounterID.get(modules.encounterID);
        if (existing && existing !== modules) {
            throw generationFailure('Boss modules map one encounter ID to multiple journal IDs');
        }
        byEncounterID.set(modules.encounterID, modules);
    }
    return byEncounterID;
}

function resolveBossModules(bossModules, modulesByEncounterID, encounter) {
    return bossModules.get(encounter.journalID) ?? modulesByEncounterID.get(encounter.id) ?? null;
}

function validateAliases(aliases) {
    for (const bossMod of ['bigwigs', 'dbm']) {
        if (!(aliases[bossMod] instanceof Map)) {
            throw generationFailure('Boss timeline aliases are malformed');
        }
        for (const [timerID, spellID] of aliases[bossMod]) {
            if (!Number.isInteger(timerID) || timerID <= 0 || !Number.isInteger(spellID) || spellID <= 0) {
                throw generationFailure('Boss timeline aliases are malformed');
            }
        }
    }
}

async function generateEncounter({
    client,
    encounter,
    combinations,
    modules,
    aliases,
    existingDatabase,
    onOmission,
}) {
    if (!modules || !modules.encounterID) {
        onOmission({
            encounterID: encounter.id,
            journalID: encounter.journalID,
            reason: 'missing-boss-module',
        });
        return null;
    }

    const encounterID = modules.encounterID;
    const difficulties = {};
    const byDifficulty = combinations.get(encounter.id);
    for (const [wclDifficulty, wowDifficulty] of WCL_DIFFICULTY_TO_WOW) {
        const candidates = byDifficulty.get(wclDifficulty) ?? [];
        const previous = existingDifficulty(existingDatabase, encounterID, wowDifficulty);
        if (candidates.length < MINIMUM_SAMPLES) {
            const omission = {
                encounterID,
                wclDifficulty,
                wowDifficulty,
                reason: 'insufficient-candidates',
                candidateCount: candidates.length,
            };
            if (previous) {
                throw generationFailure(`An existing encounter difficulty no longer has the minimum evidence. ${formatOmission(omission)}`);
            }
            onOmission(omission);
            continue;
        }
        const kills = await selectEligibleKills(
            client,
            candidates,
            encounter.id,
            wclDifficulty,
            modules,
            aliases,
        );
        if (kills.length < MINIMUM_SAMPLES) {
            const omission = {
                encounterID,
                wclDifficulty,
                wowDifficulty,
                reason: 'insufficient-valid-kills',
                candidateCount: candidates.length,
                validKillCount: kills.length,
            };
            if (previous) {
                throw generationFailure(`An existing encounter difficulty no longer has the minimum valid kills. ${formatOmission(omission)}`);
            }
            onOmission(omission);
            continue;
        }
        const difficulty = buildDifficulty(kills);
        if (!difficulty || !hasOccurrences(difficulty)) {
            const omission = {
                encounterID,
                wclDifficulty,
                wowDifficulty,
                reason: 'no-qualifying-abilities',
                candidateCount: candidates.length,
                validKillCount: kills.length,
            };
            if (previous) {
                throw generationFailure(`An existing encounter difficulty produced no qualifying abilities. ${formatOmission(omission)}`);
            }
            onOmission(omission);
            continue;
        }
        difficulties[wowDifficulty] = difficulty;
    }

    if (Object.keys(difficulties).length === 0) {
        if (existingDatabase.encounters[encounterID]) {
            throw generationFailure('An existing encounter produced no qualifying abilities');
        }
        return null;
    }
    return { encounterID, data: { difficulties } };
}

export async function generateDatabase({
    client,
    bossModules,
    existingDatabase,
    buildTime,
    aliases = BOSS_TIMELINE_ALIASES,
    onOmission = () => {},
}) {
    validateDatabase(existingDatabase);
    validateAliases(aliases);
    if (typeof onOmission !== 'function') {
        throw generationFailure('Boss timeline omission reporter is malformed');
    }
    const activeZones = await discoverCurrentTier(client, buildTime);
    const modulesByEncounterID = indexBossModulesByEncounterID(bossModules);
    const encounters = { ...existingDatabase.encounters };
    const activeEncounterIDs = new Set();

    for (const zone of activeZones) {
        for (const encounter of zone.encounters) {
            const modules = resolveBossModules(bossModules, modulesByEncounterID, encounter);
            const generated = await generateEncounter({
                client,
                encounter,
                combinations: zone.combinations,
                modules,
                aliases,
                existingDatabase,
                onOmission,
            });
            if (!generated) {
                continue;
            }
            activeEncounterIDs.add(generated.encounterID);
            encounters[generated.encounterID] = generated.data;
        }
    }

    for (const modules of bossModules.values()) {
        if (!modules.encounterID || activeEncounterIDs.has(modules.encounterID)) {
            continue;
        }
        const isActiveJournal = activeZones.some((zone) => zone.encounters.some((encounter) => (
            resolveBossModules(bossModules, modulesByEncounterID, encounter) === modules
        )));
        if (isActiveJournal && existingDatabase.encounters[modules.encounterID]) {
            throw generationFailure('An existing active encounter could not be regenerated');
        }
    }

    return validateDatabase({ schemaVersion: SCHEMA_VERSION, encounters });
}
