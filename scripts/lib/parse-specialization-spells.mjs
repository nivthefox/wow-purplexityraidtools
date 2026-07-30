/**
 * Parse specialization_spells.inc (spec-granted abilities/passives).
 *
 * Format per line:
 *   {  classId,  specId,  spellId,  overrideSpellId, "Name", tier },
 *
 * Returns an array of { classId, specId, spellId, overrideSpellId, name }.
 */
export function parseSpecializationSpells(text) {
    const results = [];
    const linePattern = /\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*"([^"]*)"\s*,\s*\d+\s*\}/g;

    let match;
    while ((match = linePattern.exec(text)) !== null) {
        results.push({
            classId:         Number(match[1]),
            specId:          Number(match[2]),
            spellId:         Number(match[3]),
            overrideSpellId: Number(match[4]),
            name:            match[5],
        });
    }

    return results;
}
