/**
 * Parse class_spells.inc (active class spells).
 *
 * Format per line:
 *   {  classId,  specId,  spellId,  overrideSpellId, "Name"  },
 *
 * Returns an array of { classId, specId, spellId, overrideSpellId, name }.
 * specId 0 means class-wide (available to all specs of that class).
 */
export function parseClassSpells(text) {
    const results = [];
    const linePattern = /\{\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*"([^"]*)"\s*\}/g;

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
