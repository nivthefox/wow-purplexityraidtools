/**
 * Resolve which spec IDs a trait applies to. Traits with explicit spec IDs
 * target those specs; class-wide traits (no spec IDs) target every spec of
 * the trait's class.
 */
export function resolveTraitSpecs(trait, specs) {
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
