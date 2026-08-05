// Protocol constants — these are baked into the WoW engine, not data.

// Spell effect type for APPLY_AURA
export const E_APPLY_AURA = 6;

// Spell effect subtypes for modifier extraction
export const A_ADD_FLAT_MODIFIER = 107;
export const A_ADD_PCT_MODIFIER = 108;
export const A_ADD_PCT_LABEL_MODIFIER = 218;
export const A_ADD_FLAT_LABEL_MODIFIER = 219;

// Property types (from misc_value on modifier effects)
export const P_DURATION = 0;
export const P_COOLDOWN = 11;
export const P_CHARGES = 22;

// Map property type → output field name
export const PROPERTY_TO_FIELD = {
  [P_DURATION]: 'duration',
  [P_COOLDOWN]: 'cooldown',
  [P_CHARGES]:  'charges',
};

// Spell attribute bit positions (from spell_attribute enum in data_enums.hh)
export const SPELL_ATTR0_PASSIVE = 0x40;
export const SX_IS_BIG_DEFENSIVE = 512;
export const SX_IS_EXTERNAL_DEFENSIVE = 499;
export const SX_IMPORTANT_SPELL = 491;

// Number of class family flag uint32s per spell/effect
export const NUM_CLASS_FAMILY_FLAGS = 4;

// Statically maintained — WoW has no attribute bit for raidwide CDs.
export const RAID_MOVEMENT_SPELLS = new Set([
    106898,   // Stampeding Roar
    192077,   // Wind Rush Totem
    374968,   // Time Spiral
]);

export const RAID_COOLDOWN_SPELLS = new Set([
    740,      // Tranquility
    31821,    // Aura Mastery
    31884,    // Avenging Wrath
    51052,    // Anti-Magic Zone
    62618,    // Power Word: Barrier
    64843,    // Divine Hymn
    97462,    // Rallying Cry
    98008,    // Spirit Link Totem
    108280,   // Healing Tide Totem
    114052,   // Ascendance (Restoration Shaman)
    115310,   // Revival
    196718,   // Darkness
    216331,   // Avenging Crusader
    359816,   // Dream Flight
    363534,   // Rewind
    388615,   // Restoral
    200183,   // Apotheosis
    472433,   // Evangelism
]);

// Validation gate — alert if the discovered spec count doesn't match.
export const EXPECTED_SPEC_COUNT = 40;

// SimC GitHub coordinates — branch discovered at runtime via fetch-simc.
export const SIMC_REPO = 'simulationcraft/simc';
export const SIMC_GENERATED_PATH = 'engine/dbc/generated';
