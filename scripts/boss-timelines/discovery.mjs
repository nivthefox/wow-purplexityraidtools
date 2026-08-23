import { CURRENT_TIER_WINDOW_MS, RAID_DIFFICULTIES } from './constants.mjs';

function candidateIdentity(candidate) {
    return `${candidate.report.code}\u0000${candidate.report.fightID}`;
}

export function selectDistinctCandidates(rankings) {
    const byIdentity = new Map();
    for (const ranking of rankings) {
        const identity = candidateIdentity(ranking);
        const existing = byIdentity.get(identity);
        if (!existing || ranking.duration > existing.duration
            || (ranking.duration === existing.duration && ranking.startTime > existing.startTime)) {
            byIdentity.set(identity, ranking);
        }
    }
    return [...byIdentity.values()].sort((left, right) => {
        if (left.duration !== right.duration) {
            return right.duration - left.duration;
        }
        if (left.startTime !== right.startTime) {
            return right.startTime - left.startTime;
        }
        return candidateIdentity(left).localeCompare(candidateIdentity(right));
    });
}

export function raidZones(zones) {
    return zones.filter((zone) => !zone.frozen
        && zone.difficulties.some((difficulty) => RAID_DIFFICULTIES.has(difficulty.id))
        && zone.encounters.length > 0);
}

export async function discoverCurrentTier(client, buildTime) {
    const startTime = buildTime - CURRENT_TIER_WINDOW_MS;
    const discovered = [];
    for (const zone of raidZones(await client.discoverZones())) {
        const combinations = new Map();
        let active = false;
        const difficulties = zone.difficulties
            .map((difficulty) => difficulty.id)
            .filter((difficulty) => RAID_DIFFICULTIES.has(difficulty))
            .sort((left, right) => left - right);
        const encounters = [...zone.encounters].sort((left, right) => left.id - right.id);
        for (const encounter of encounters) {
            const byDifficulty = new Map();
            const rankingsByDifficulty = await client.candidateKills(encounter.id, startTime, buildTime);
            for (const difficulty of difficulties) {
                const rankings = rankingsByDifficulty.get(difficulty) ?? [];
                const candidates = selectDistinctCandidates(rankings);
                byDifficulty.set(difficulty, candidates);
                if (candidates.length > 0) {
                    active = true;
                }
            }
            combinations.set(encounter.id, byDifficulty);
        }
        if (active) {
            discovered.push({ ...zone, encounters, combinations });
        }
    }
    if (discovered.length === 0) {
        throw new Error('No current raid tier was discoverable in the rolling seven-day window');
    }
    return discovered;
}
