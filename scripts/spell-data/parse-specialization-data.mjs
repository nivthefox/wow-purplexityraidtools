/**
 * Parse sc_specialization_data.inc to discover all specializations and their
 * numeric IDs, then derive class tokens and spec names from enum naming
 * conventions. Also parse sc_spec_list.inc to determine class_id ordering.
 *
 * Returns a Map<specId, { specId, specName, classId, classToken }>.
 */
export function parseSpecializationData(specializationDataText, specListText) {
    // Step 1: parse sc_specialization_data.inc enum entries.
    //   Format: "  WARRIOR_ARMS           = 71,"
    const enumPattern = /^\s+(\w+)\s*=\s*(\d+)/gm;
    const allEnums = new Map(); // enumName → numericId
    let match;
    while ((match = enumPattern.exec(specializationDataText)) !== null) {
        const [, name, id] = match;
        if (name === 'SPEC_NONE' || name === 'SPEC_PET') {
            continue;
        }
        allEnums.set(name, Number(id));
    }

    // Step 2: parse sc_spec_list.inc to get the class_id → enum name ordering.
    //   The array is indexed by class_id (0 = pets, 1 = warrior, ..., 13 = evoker).
    //   Each class has up to MAX_SPECS_PER_CLASS entries.
    const entryPattern = /\b([A-Z][A-Z_]+[A-Z])\b/g;
    const bodyStart = specListText.indexOf('{');
    const body = specListText.slice(bodyStart);

    // Each inner { ... } block is one class_id: classBlocks[0] = pets,
    // classBlocks[1] = warrior, etc.
    const classBlocks = body.match(/\{[^{}]*\}/g);
    if (!classBlocks) {
        throw new Error('Failed to parse sc_spec_list.inc class blocks');
    }

    const classIdToEnums = new Map(); // classId → [enumName, ...]
    for (let classId = 0; classId < classBlocks.length; classId++) {
        const block = classBlocks[classId];
        const enums = [];
        let m;
        while ((m = entryPattern.exec(block)) !== null) {
            if (m[1] !== 'SPEC_NONE') {
                enums.push(m[1]);
            }
        }
        if (enums.length > 0) {
            classIdToEnums.set(classId, enums);
        }
    }

    // Step 3: derive class tokens and spec names from enum naming conventions.
    //   For each class_id, find the longest common prefix (at underscore
    //   boundaries) across all its enum names. That prefix is the class portion;
    //   the remainder is the spec name.
    //
    //   DEMON_HUNTER_HAVOC → class prefix = "DEMON_HUNTER_", spec = "HAVOC"
    //   HUNTER_BEAST_MASTERY → class prefix = "HUNTER_", spec = "BEAST_MASTERY"
    //
    //   WoW API class token = prefix with underscores removed: DEMONHUNTER
    //   Spec display name = spec portion in title case: "Beast Mastery"
    const specs = new Map(); // specId → { specId, specName, classId, classToken }

    for (const [classId, enumNames] of classIdToEnums) {
        if (classId === 0) {
            continue;
        }

        const classPrefix = findCommonPrefix(enumNames);
        const classToken = classPrefix.replace(/_$/, '').replace(/_/g, '');

        for (const enumName of enumNames) {
            const specId = allEnums.get(enumName);
            if (specId === undefined) {
                throw new Error(`Enum "${enumName}" from spec_list not found in specialization_data`);
            }

            const specPart = enumName.slice(classPrefix.length);
            const specName = toTitleCase(specPart);

            specs.set(specId, { specId, specName, classId, classToken });
        }
    }

    return specs;
}

/**
 * Find the longest common prefix of an array of underscore-separated strings,
 * ending at an underscore boundary (inclusive of trailing underscore).
 *
 * E.g., ["DEMON_HUNTER_HAVOC", "DEMON_HUNTER_VENGEANCE"] → "DEMON_HUNTER_"
 *       ["HUNTER_BEAST_MASTERY", "HUNTER_MARKSMANSHIP"] → "HUNTER_"
 */
function findCommonPrefix(names) {
    if (names.length === 0) {
        return '';
    }
    if (names.length === 1) {
        // Single spec: prefix is everything up to and including the last underscore.
        const lastUnderscore = names[0].lastIndexOf('_');
        return names[0].slice(0, lastUnderscore + 1);
    }

    const splitNames = names.map(n => n.split('_'));
    const minParts = Math.min(...splitNames.map(p => p.length));

    let commonParts = 0;
    for (let i = 0; i < minParts - 1; i++) {
        // Must leave at least one part for the spec name
        if (splitNames.every(parts => parts[i] === splitNames[0][i])) {
            commonParts = i + 1;
        } else {
            break;
        }
    }

    if (commonParts === 0) {
        throw new Error(`No common prefix found for: ${names.join(', ')}`);
    }

    return splitNames[0].slice(0, commonParts).join('_') + '_';
}

/**
 * Convert an UPPER_SNAKE_CASE string to Title Case.
 * "BEAST_MASTERY" → "Beast Mastery"
 */
function toTitleCase(str) {
    return str
        .split('_')
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}
