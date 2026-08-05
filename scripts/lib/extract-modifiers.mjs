import {
    E_APPLY_AURA,
    A_ADD_FLAT_MODIFIER,
    A_ADD_PCT_MODIFIER,
    A_ADD_PCT_LABEL_MODIFIER,
    A_ADD_FLAT_LABEL_MODIFIER,
    PROPERTY_TO_FIELD,
    NUM_CLASS_FAMILY_FLAGS,
} from './constants.mjs';
import { resolveTraitSpecs } from './resolve-trait-specs.mjs';

/**
 * Extract talent modifier deltas and attach them to abilities.
 *
 * For each talent (from trait_data), examines its spell's effects for
 * APPLY_AURA modifier subtypes. Matches modifiers to target abilities via
 * class family bitmask or label-based matching, then writes the deltas into
 * each ability's `talents` table.
 */
export function extractModifiers(specAbilities, traits, spells, effects, labels, specs) {
    for (const trait of traits) {
        if (trait.spellId === 0) {
            continue;
        }

        const talentEffects = effects.get(trait.spellId);
        if (!talentEffects) {
            continue;
        }

        const talentSpell = spells.get(trait.spellId);
        if (!talentSpell) {
            continue;
        }

        const targetSpecIds = resolveTraitSpecs(trait, specs);

        for (const effect of talentEffects) {
            if (effect.type !== E_APPLY_AURA) {
                continue;
            }
            if (!isModifierSubtype(effect.subtype)) {
                continue;
            }

            const fieldName = PROPERTY_TO_FIELD[effect.miscValue];
            if (!fieldName) {
                continue;
            }

            const isPercent = effect.subtype === A_ADD_PCT_MODIFIER || effect.subtype === A_ADD_PCT_LABEL_MODIFIER;
            const isLabelBased = effect.subtype === A_ADD_PCT_LABEL_MODIFIER || effect.subtype === A_ADD_FLAT_LABEL_MODIFIER;

            for (const specId of targetSpecIds) {
                const specData = specAbilities.get(specId);
                if (!specData) {
                    continue;
                }

                for (const [abilitySpellId, ability] of specData.abilities) {
                    const abilitySpell = spells.get(abilitySpellId);
                    if (!abilitySpell) {
                        continue;
                    }

                    const matches = isLabelBased
                        ? matchesByLabel(effect, abilitySpellId, labels)
                        : matchesByFamilyFlags(effect, abilitySpell, talentSpell);

                    if (!matches) {
                        continue;
                    }

                    const delta = computeDelta(effect, fieldName, isPercent);
                    if (delta === 0) {
                        continue;
                    }

                    if (!ability.talents) {
                        ability.talents = {};
                    }
                    if (!ability.talents[trait.spellId]) {
                        ability.talents[trait.spellId] = {};
                    }

                    const outputKey = isPercent ? `${fieldName}_pct` : fieldName;
                    ability.talents[trait.spellId][outputKey] = delta;
                }
            }
        }
    }
}

function isModifierSubtype(subtype) {
    return subtype === A_ADD_FLAT_MODIFIER
        || subtype === A_ADD_PCT_MODIFIER
        || subtype === A_ADD_PCT_LABEL_MODIFIER
        || subtype === A_ADD_FLAT_LABEL_MODIFIER;
}

function matchesByFamilyFlags(effect, targetSpell, talentSpell) {
    if (talentSpell.classFlagsFamily !== targetSpell.classFlagsFamily) {
        return false;
    }

    if (!effect.classFlags || !targetSpell.classFlags) {
        return false;
    }

    for (let i = 0; i < NUM_CLASS_FAMILY_FLAGS; i++) {
        if ((effect.classFlags[i] & targetSpell.classFlags[i]) !== 0) {
            return true;
        }
    }

    return false;
}

function matchesByLabel(effect, targetSpellId, labels) {
    const targetLabels = labels.get(targetSpellId);
    if (!targetLabels) {
        return false;
    }

    if (effect.miscValue2 === 0) {
        return false;
    }

    return targetLabels.includes(effect.miscValue2);
}

function computeDelta(effect, fieldName, isPercent) {
    if (isPercent) {
        return effect.baseValue / 100;
    }

    if (fieldName === 'cooldown' || fieldName === 'duration') {
        return effect.baseValue / 1000;
    }

    return effect.baseValue;
}
