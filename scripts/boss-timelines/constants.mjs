export const SCHEMA_VERSION = 1;
export const MINIMUM_SAMPLES = 3;
export const MAXIMUM_SAMPLES = 30;
export const REQUEST_INTERVAL_MS = 1000;
export const CURRENT_TIER_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
export const WCL_DIFFICULTY_TO_WOW = new Map([
    [1, 17],
    [3, 14],
    [4, 15],
    [5, 16],
]);
export const RAID_DIFFICULTIES = new Set(WCL_DIFFICULTY_TO_WOW.keys());
