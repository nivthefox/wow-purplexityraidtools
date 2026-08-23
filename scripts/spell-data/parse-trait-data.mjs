/**
 * Parse trait_data.inc (modern talent tree entries).
 *
 * Format per line (from trait_data_t struct):
 *   { tree_index, id_class, id_trait_node_entry, id_node, max_ranks, req_points,
 *     id_trait_definition, id_spell, id_replace_spell, id_override_spell,
 *     row, col, selection_index, "name",
 *     { id_spec[0], id_spec[1], id_spec[2], id_spec[3] },
 *     { id_spec_starter[0], ... },
 *     id_sub_tree, node_type },
 *
 * Returns an array of trait objects.
 */
export function parseTraitData(text) {
    const results = [];
    const linePattern = /\{\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*"([^"]*)"\s*,\s*\{([^}]*)\}\s*,\s*\{([^}]*)\}\s*,\s*(\d+)\s*,\s*(\d+)\s*\}/g;

    let match;
    while ((match = linePattern.exec(text)) !== null) {
        const idSpecs = match[15].split(',').map(s => Number(s.trim())).filter(n => n > 0);

        results.push({
            treeIndex:        Number(match[1]),
            classId:          Number(match[2]),
            traitNodeEntryId: Number(match[3]),
            nodeId:           Number(match[4]),
            maxRanks:         Number(match[5]),
            reqPoints:        Number(match[6]),
            traitDefinitionId:Number(match[7]),
            spellId:          Number(match[8]),
            replaceSpellId:   Number(match[9]),
            overrideSpellId:  Number(match[10]),
            row:              Number(match[11]),
            col:              Number(match[12]),
            selectionIndex:   Number(match[13]),
            name:             match[14],
            specIds:          idSpecs,
            subTreeId:        Number(match[17]),
            nodeType:         Number(match[18]),
        });
    }

    return results;
}
