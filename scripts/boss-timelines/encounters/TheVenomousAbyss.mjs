const NEKZALI_NPC_ID = 259927;
const RITUAL_OF_AWAKENING_ID = 1295124;
const UNCOILING_ID = 1292315;
const ZULJAN_NPC_ID = 257911;
const GHASTLY_REGENERATION_ID = 1304033;

function onePhase(name) {
    return ({ fight }) => [{
        id: 1,
        name,
        isIntermission: false,
        startTime: fight.startTime,
        endTime: fight.endTime,
    }];
}

function enemyActorIDs(fight, gameID) {
    const actorIDs = new Set();
    for (const actor of fight.enemyNPCs) {
        if (actor.gameID === gameID) {
            actorIDs.add(actor.id);
        }
    }
    return actorIDs;
}

function firstCastTime(events, sourceIDs, abilityGameID) {
    for (const event of events) {
        if (event.type === 'cast'
            && event.abilityGameID === abilityGameID
            && sourceIDs.has(event.sourceID)
        ) {
            return event.timestamp;
        }
    }
    return null;
}

function decideNekzali({ fight, events }) {
    const sourceIDs = enemyActorIDs(fight, NEKZALI_NPC_ID);
    const ritualStart = firstCastTime(events, sourceIDs, RITUAL_OF_AWAKENING_ID);
    const uncoilingStart = firstCastTime(events, sourceIDs, UNCOILING_ID);
    if (ritualStart === null || uncoilingStart === null
        || ritualStart <= fight.startTime
        || uncoilingStart <= ritualStart
        || uncoilingStart >= fight.endTime
    ) {
        return null;
    }

    return [
        {
            id: 1,
            name: 'Stage One: Soulcoiler Initiation',
            isIntermission: false,
            startTime: fight.startTime,
            endTime: ritualStart,
        },
        {
            id: 2,
            name: 'Intermission: Ritual of Awakening',
            isIntermission: true,
            startTime: ritualStart,
            endTime: uncoilingStart,
        },
        {
            id: 3,
            name: 'Stage Two: Uncoiling',
            isIntermission: false,
            startTime: uncoilingStart,
            endTime: fight.endTime,
        },
    ];
}

function decideCoiledAltar({ fight, events }) {
    const zuljanActorIDs = enemyActorIDs(fight, ZULJAN_NPC_ID);
    let zuljanDeath = null;
    let regenerationApplied = null;
    let regenerationRemoved = null;
    for (const event of events) {
        if (zuljanDeath === null
            && event.type === 'death'
            && zuljanActorIDs.has(event.targetID)
        ) {
            zuljanDeath = event.timestamp;
            continue;
        }
        if (zuljanDeath !== null
            && regenerationApplied === null
            && event.type === 'applybuff'
            && event.abilityGameID === GHASTLY_REGENERATION_ID
        ) {
            regenerationApplied = event.timestamp;
            continue;
        }
        if (regenerationApplied !== null
            && event.type === 'removebuff'
            && event.abilityGameID === GHASTLY_REGENERATION_ID
        ) {
            regenerationRemoved = event.timestamp;
            break;
        }
    }
    if (zuljanDeath === null || regenerationApplied === null || regenerationRemoved === null
        || zuljanDeath <= fight.startTime
        || regenerationApplied <= zuljanDeath
        || regenerationRemoved <= regenerationApplied
        || regenerationRemoved >= fight.endTime
    ) {
        return null;
    }

    return [
        {
            id: 1,
            name: "Stage One: Serpent's Bargain",
            isIntermission: false,
            startTime: fight.startTime,
            endTime: zuljanDeath,
        },
        {
            id: 2,
            name: "Stage Two: Usurper's Reprisal",
            isIntermission: false,
            startTime: zuljanDeath,
            endTime: regenerationApplied,
        },
        {
            id: 3,
            name: 'Intermission: The Claimed Vessel',
            isIntermission: true,
            startTime: regenerationApplied,
            endTime: regenerationRemoved,
        },
        {
            id: 4,
            name: 'Stage Three: Coiled Union',
            isIntermission: false,
            startTime: regenerationRemoved,
            endTime: fight.endTime,
        },
    ];
}

export const THE_VENOMOUS_ABYSS_PHASE_DECIDERS = new Map([
    [3420, onePhase('Sszorak')],
    [3421, onePhase('The Twin Fangs')],
    [3429, decideCoiledAltar],
    [3445, onePhase('Entombed Sentinels')],
    [3455, onePhase('Vashnik the Malignant')],
    [3470, decideNekzali],
    [3497, onePhase('The Lost Explorers')],
]);
