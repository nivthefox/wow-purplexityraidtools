import { EXPECTED_SPEC_COUNT } from './constants.mjs';

/**
 * Run sanity checks on the assembled spec abilities.
 * Throws on failure so the workflow exits non-zero.
 */
export function validate(specAbilities) {
    const errors = [];

    if (specAbilities.size !== EXPECTED_SPEC_COUNT) {
        errors.push(`Expected ${EXPECTED_SPEC_COUNT} specs, got ${specAbilities.size}`);
    }

    for (const [specId, spec] of specAbilities) {
        if (spec.abilities.size === 0) {
            errors.push(`Spec ${specId} (${spec.specName} ${spec.classToken}) has zero abilities`);
        }

        for (const [abilityId, ability] of spec.abilities) {
            if (!ability.name || ability.name.trim() === '') {
                errors.push(`Spec ${specId}: ability ${abilityId} has empty name`);
            }
            if (!ability.spellId || ability.spellId <= 0) {
                errors.push(`Spec ${specId}: ability "${ability.name}" has invalid spellId ${ability.spellId}`);
            }
        }
    }

    if (errors.length > 0) {
        throw new Error(`Validation failed:\n  ${errors.join('\n  ')}`);
    }

    console.log(`Validation passed: ${specAbilities.size} specs`);
    for (const [specId, spec] of [...specAbilities.entries()].sort((a, b) => a[0] - b[0])) {
        console.log(`  [${specId}] ${spec.specName} ${spec.classToken}: ${spec.abilities.size} abilities`);
    }
}
