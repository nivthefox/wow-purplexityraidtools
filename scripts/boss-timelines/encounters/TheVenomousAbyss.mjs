const NEKZALI_NPC_ID = 259927;
const RITUAL_OF_AWAKENING_ID = 1295124;
const UNCOILING_ID = 1292315;

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

export const THE_VENOMOUS_ABYSS_PHASE_DECIDERS = new Map([
    [3420, onePhase('Sszorak')],
    [3421, onePhase('The Twin Fangs')],
    [3445, onePhase('Entombed Sentinels')],
    [3455, onePhase('Vashnik the Malignant')],
    [3470, decideNekzali],
    [3497, onePhase('The Lost Explorers')],
]);
