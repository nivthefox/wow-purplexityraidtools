function onePhase(name) {
    return ({ fight }) => [{
        id: 1,
        name,
        isIntermission: false,
        startTime: fight.startTime,
        endTime: fight.endTime,
    }];
}

export const LAIRS_PHASE_DECIDERS = new Map([
    [3379, onePhase('Nymrissa Wavecaller')],
]);
