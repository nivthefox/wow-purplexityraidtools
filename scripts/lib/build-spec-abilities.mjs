import { SPELL_ATTR0_PASSIVE, SX_IS_BIG_DEFENSIVE, SX_IS_EXTERNAL_DEFENSIVE, SX_IMPORTANT_SPELL, RAID_COOLDOWN_SPELLS } from './constants.mjs';

/**
 * Combine parsed data to produce per-spec ability lists.
 *
 * @param {Map} specs - specId → { specId, specName, classId, classToken }
 * @param {Map} spells - spellId → spell data
 * @param {Array} classSpells - parsed class_spells.inc entries
 * @param {Array} specSpells - parsed specialization_spells.inc entries
 * @param {Array} traits - parsed trait_data.inc entries
 * @returns {Map} specId → { specId, specName, classToken, abilities: Map<spellId, ability> }
 */
export function buildSpecAbilities(specs, spells, classSpells, specSpells, traits) {
    const result = new Map();

    for (const [specId, spec] of specs) {
        result.set(specId, {
            specId,
            specName: spec.specName,
            classId: spec.classId,
            classToken: spec.classToken,
            abilities: new Map(),
        });
    }

    addClassSpellAbilities(result, specs, spells, classSpells);
    addTraitAbilities(result, specs, spells, traits);
    addSpecSpellAbilities(result, specs, spells, specSpells);

    for (const specData of result.values()) {
        pruneNonCastable(specData.abilities, spells);
        attachFlags(specData.abilities, spells);
    }

    return result;
}

function addClassSpellAbilities(result, specs, spells, classSpells) {
    for (const entry of classSpells) {
        if (entry.classId === 0) {
            continue;
        }

        const spellId = entry.overrideSpellId || entry.spellId;
        const spell = spells.get(spellId);
        if (!spell) {
            continue;
        }
        if (isPassive(spell)) {
            continue;
        }
        if (isPetSpec(entry.specId)) {
            continue;
        }

        if (entry.specId === 0) {
            addToAllSpecsOfClass(result, specs, entry.classId, spell);
        } else if (result.has(entry.specId)) {
            addAbility(result.get(entry.specId).abilities, spell);
        }
    }
}

function addTraitAbilities(result, specs, spells, traits) {
    for (const trait of traits) {
        if (trait.spellId === 0) {
            continue;
        }

        const spell = spells.get(trait.overrideSpellId || trait.spellId);
        if (!spell) {
            continue;
        }
        if (isPassive(spell)) {
            continue;
        }

        const targetSpecs = resolveTraitSpecs(trait, specs);
        for (const specId of targetSpecs) {
            if (result.has(specId)) {
                addAbility(result.get(specId).abilities, spell);
            }
        }
    }
}

function addSpecSpellAbilities(result, specs, spells, specSpells) {
    for (const entry of specSpells) {
        if (entry.classId === 0) {
            continue;
        }

        const spellId = entry.overrideSpellId || entry.spellId;
        const spell = spells.get(spellId);
        if (!spell) {
            continue;
        }
        if (isPassive(spell)) {
            continue;
        }
        if (isPetSpec(entry.specId)) {
            continue;
        }
        if (!result.has(entry.specId)) {
            continue;
        }

        addAbility(result.get(entry.specId).abilities, spell);
    }
}

function addToAllSpecsOfClass(result, specs, classId, spell) {
    for (const [specId, spec] of specs) {
        if (spec.classId === classId) {
            addAbility(result.get(specId).abilities, spell);
        }
    }
}

function addAbility(abilities, spell) {
    if (abilities.has(spell.id)) {
        return;
    }

    abilities.set(spell.id, {
        spellId: spell.id,
        name: spell.name,
        duration: spell.duration,
        cooldown: spell.cooldown,
        charges: spell.charges,
        channeled: spell.channeled || undefined,
    });
}

function resolveTraitSpecs(trait, specs) {
    if (trait.specIds.length > 0) {
        return trait.specIds.filter(id => specs.has(id));
    }

    if (trait.classId === 0) {
        return [];
    }

    const classSpecs = [];
    for (const [specId, spec] of specs) {
        if (spec.classId === trait.classId) {
            classSpecs.push(specId);
        }
    }
    return classSpecs;
}

function isPassive(spell) {
    if (!spell.attributes || spell.attributes.length === 0) {
        return false;
    }
    return (spell.attributes[0] & SPELL_ATTR0_PASSIVE) !== 0;
}

function isPetSpec(specId) {
    return specId >= 535 && specId <= 537;
}

function pruneNonCastable(abilities, spells) {
    for (const [spellId, ability] of abilities) {
        const spell = spells.get(spellId);
        if (!spell) {
            abilities.delete(spellId);
            continue;
        }

        if (ability.name === '' || ability.spellId <= 0) {
            abilities.delete(spellId);
        }
    }
}

function hasAttribute(spell, bitPos) {
    const wordIndex = Math.floor(bitPos / 32);
    const bitIndex = bitPos % 32;
    if (!spell.attributes || wordIndex >= spell.attributes.length) {
        return false;
    }
    return (spell.attributes[wordIndex] & (1 << bitIndex)) !== 0;
}

function attachFlags(abilities, spells) {
    for (const [spellId, ability] of abilities) {
        const spell = spells.get(spellId);
        if (!spell) {
            continue;
        }

        const flags = [];
        if (hasAttribute(spell, SX_IS_BIG_DEFENSIVE)) {
            flags.push('BIG_DEFENSIVE');
        }
        if (hasAttribute(spell, SX_IS_EXTERNAL_DEFENSIVE)) {
            flags.push('EXTERNAL_DEFENSIVE');
        }
        if (hasAttribute(spell, SX_IMPORTANT_SPELL)) {
            flags.push('IMPORTANT');
        }
        if (RAID_COOLDOWN_SPELLS.has(spellId)) {
            flags.push('RAID_COOLDOWN');
        }

        if (flags.length > 0) {
            ability.flags = flags;
        }
    }
}
