import { NUM_CLASS_FAMILY_FLAGS } from './constants.mjs';

/**
 * Parse sc_spell_data.inc which contains three arrays:
 *   - __spell_data[] — spells
 *   - __spelleffect_data[] — effects
 *   - __spelllabel_data[] — labels
 *
 * Also fetches spell_data.hpp to discover struct field positions at runtime,
 * so this parser doesn't break when SimC adds/removes fields.
 */
export function parseSpellData(text, fieldLayout) {
    const spellSectionStart = text.indexOf('__spell_data[');
    const effectSectionStart = text.indexOf('__spelleffect_data[');
    const labelSectionStart = text.indexOf('__spelllabel_data');

    if (spellSectionStart === -1 || effectSectionStart === -1 || labelSectionStart === -1) {
        throw new Error('Failed to find expected sections in sc_spell_data.inc');
    }

    const spellSection = text.slice(spellSectionStart, effectSectionStart);
    const effectSection = text.slice(effectSectionStart, labelSectionStart);
    const labelSection = text.slice(labelSectionStart);

    console.log('Parsing spells...');
    const spells = parseSpells(spellSection, fieldLayout.spell);
    console.log(`    ${spells.size} spells parsed`);

    console.log('Parsing effects...');
    const effects = parseEffects(effectSection, fieldLayout.effect);
    let effectCount = 0;
    for (const arr of effects.values()) {
        effectCount += arr.length;
    }
    console.log(`    ${effectCount} effects parsed`);

    console.log('Parsing labels...');
    const labels = parseLabels(labelSection);
    let labelCount = 0;
    for (const arr of labels.values()) {
        labelCount += arr.length;
    }
    console.log(`    ${labelCount} labels parsed`);

    return { spells, effects, labels };
}

/**
 * Parse spell_data.hpp to discover struct field positions at runtime.
 * Returns { spell: { ... field indices }, effect: { ... field indices } }.
 */
export function parseFieldLayout(hppText) {
    return {
        spell: parseStructLayout(hppText, 'struct spell_data_t'),
        effect: parseStructLayout(hppText, 'struct spelleffect_data_t'),
    };
}

function parseStructLayout(hppText, structName) {
    // Find the actual struct definition (with body), not a forward declaration.
    // Forward declarations look like "struct foo;" — definitions have "{" nearby.
    let searchFrom = 0;
    let structStart = -1;
    while (true) {
        const pos = hppText.indexOf(structName, searchFrom);
        if (pos === -1) {
            break;
        }
        const afterName = hppText.slice(pos + structName.length, pos + structName.length + 20).trim();
        if (afterName.startsWith('{') || afterName.startsWith('\n{') || afterName.startsWith('\r\n{')) {
            structStart = pos;
            break;
        }
        searchFrom = pos + structName.length;
    }

    if (structStart === -1) {
        throw new Error(`Struct definition for ${structName} not found in hpp`);
    }

    const braceStart = hppText.indexOf('{', structStart);
    let braceDepth = 0;
    let structEnd = braceStart;
    for (let i = braceStart; i < hppText.length; i++) {
        if (hppText[i] === '{') {
            braceDepth++;
        }
        if (hppText[i] === '}') {
            braceDepth--;
            if (braceDepth === 0) {
                structEnd = i;
                break;
            }
        }
    }

    // Trim the body to just data member declarations. Methods start after the
    // data members and look like function signatures. We detect the boundary
    // by looking for lines where '(' appears outside of a comment.
    const fullBody = hppText.slice(braceStart + 1, structEnd);
    const bodyLines = fullBody.split('\n');
    const memberLines = [];
    for (const line of bodyLines) {
        const codeOnly = line.replace(/\/\/.*$/, '').replace(/\/\*.*?\*\//g, '');
        if (codeOnly.includes('(')) {
            break;
        }
        memberLines.push(line);
    }
    const body = memberLines.join('\n');

    const fieldPattern = /^\s+(?:const\s+)?(?:\w+(?:::\w+)?(?:<[^>]+>)?)\s+(\*?)(_\w+)(?:\[\s*(\w+)\s*\])?(?:\[\s*(\w+)\s*\])?\s*;/gm;
    const fields = {};
    let index = 0;
    let match;

    const constants = parseConstants(hppText);

    while ((match = fieldPattern.exec(body)) !== null) {
        const isPointer = match[1] === '*';
        const name = match[2];
        const arraySizeToken = match[3];
        const arraySizeToken2 = match[4];

        // Skip pointer fields (runtime linkage, not serialized)
        if (isPointer) {
            continue;
        }

        // The name field (_name) is a `const char*` — it's the first field and is serialized as a string
        if (name === '_name') {
            fields[name] = { index: -1, isString: true };
            continue;
        }

        let arraySize = 1;
        if (arraySizeToken) {
            arraySize = constants[arraySizeToken] || parseInt(arraySizeToken, 10) || 1;
        }
        if (arraySizeToken2) {
            const size2 = constants[arraySizeToken2] || parseInt(arraySizeToken2, 10) || 1;
            arraySize *= size2;
        }

        if (arraySize > 1) {
            fields[name] = { index, isBraceArray: true, size: arraySize };
        } else {
            fields[name] = { index };
        }
        index++;
    }

    return fields;
}

function parseConstants(hppText) {
    const result = {};
    const pattern = /constexpr\s+unsigned\s+(\w+)\s*=\s*(\d+)/g;
    let match;
    while ((match = pattern.exec(hppText)) !== null) {
        result[match[1]] = Number(match[2]);
    }
    return result;
}

function parseSpells(section, layout) {
    const spells = new Map();

    const linePattern = /\{\s*"([^"]*)"(.*?)\},?\s*\/\*/g;
    let match;

    while ((match = linePattern.exec(section)) !== null) {
        const name = match[1];
        const fields = parseFieldList(stripLeadingComma(match[2]));

        const id = int(fieldVal(fields, layout._id));
        if (id === 0) {
            continue;
        }

        const cooldownMs = int(fieldVal(fields, layout._cooldown));
        const categoryCooldownMs = int(fieldVal(fields, layout._category_cooldown));
        const chargeCount = int(fieldVal(fields, layout._charges));
        const chargeCooldownMs = int(fieldVal(fields, layout._charge_cooldown));
        const durationMs = parseFloat(fieldVal(fields, layout._duration)) || 0;

        const attributes = parseUintArray(fieldVal(fields, layout._attributes));
        const classFlags = parseUintArray(fieldVal(fields, layout._class_flags));
        const classFlagsFamily = int(fieldVal(fields, layout._class_flags_family));
        const channelInterrupt = parseUintArray(fieldVal(fields, layout._channel_interrupt));

        let effectiveCooldownMs;
        if (chargeCount > 0 && chargeCooldownMs > 0) {
            effectiveCooldownMs = chargeCooldownMs;
        } else {
            effectiveCooldownMs = cooldownMs > 0 ? cooldownMs : categoryCooldownMs;
        }

        spells.set(id, {
            id,
            name,
            cooldown: effectiveCooldownMs / 1000,
            duration: durationMs < 0 ? 0 : durationMs / 1000,
            charges: chargeCount > 0 ? chargeCount : 1,
            channeled: (channelInterrupt[0] !== 0 || channelInterrupt[1] !== 0) || undefined,
            attributes,
            classFlags,
            classFlagsFamily,
            classMask: parseHex(fieldVal(fields, layout._class_mask)),
        });
    }

    return spells;
}

function parseEffects(section, layout) {
    const effects = new Map();

    // Find only the __spelleffect_data array, not the id index array that follows
    const arrayDecl = section.indexOf('__spelleffect_data[');
    if (arrayDecl === -1) {
        return effects;
    }
    const dataStart = section.indexOf('{', arrayDecl);
    const closingBrace = section.indexOf('};', dataStart);
    if (dataStart === -1 || closingBrace === -1) {
        return effects;
    }

    const data = section.slice(dataStart, closingBrace);
    // Match each inner { ... } block as a complete effect record
    const linePattern = /\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}/g;
    let match;

    while ((match = linePattern.exec(data)) !== null) {
        const fields = parseFieldList(match[1]);

        const id = int(fieldVal(fields, layout._id));
        if (id === 0) {
            continue;
        }

        const spellId = int(fieldVal(fields, layout._spell_id));
        const effect = {
            id,
            spellId,
            index: int(fieldVal(fields, layout._index)),
            type: int(fieldVal(fields, layout._type)),
            subtype: int(fieldVal(fields, layout._subtype)),
            baseValue: parseFloat(fieldVal(fields, layout._base_value)) || 0,
            miscValue: int(fieldVal(fields, layout._misc_value)),
            miscValue2: int(fieldVal(fields, layout._misc_value_2)),
            classFlags: parseUintArray(fieldVal(fields, layout._class_flags)),
        };

        if (!effects.has(spellId)) {
            effects.set(spellId, []);
        }
        effects.get(spellId).push(effect);
    }

    return effects;
}

function parseLabels(section) {
    const labels = new Map();
    const linePattern = /\{\s*(\d+)\s*,\s*(-?\d+)\s*\}/g;
    let match;

    while ((match = linePattern.exec(section)) !== null) {
        const spellId = Number(match[1]);
        const labelId = Number(match[2]);

        if (!labels.has(spellId)) {
            labels.set(spellId, []);
        }
        labels.get(spellId).push(labelId);
    }

    return labels;
}

function fieldVal(fields, layoutEntry) {
    if (!layoutEntry) {
        return '0';
    }
    return fields[layoutEntry.index] || '0';
}

/**
 * Strip the leading comma and empty field from the "rest" portion of a
 * regex match, so field index 0 aligns with the first actual value.
 */
function stripLeadingComma(rest) {
    const trimmed = rest.trimStart();
    if (trimmed.startsWith(',')) {
        return trimmed.slice(1);
    }
    return rest;
}

/**
 * Parse a comma-separated field list, treating brace-enclosed sub-arrays as
 * single tokens. Each { ... } block becomes one field regardless of internal commas.
 */
function parseFieldList(str) {
    const fields = [];
    let current = '';
    let depth = 0;

    for (const ch of str) {
        if (ch === '{') {
            depth++;
            current += ch;
        } else if (ch === '}') {
            depth--;
            current += ch;
        } else if (ch === ',' && depth === 0) {
            fields.push(current.trim());
            current = '';
        } else {
            current += ch;
        }
    }

    if (current.trim()) {
        fields.push(current.trim());
    }

    return fields;
}

function parseUintArray(str) {
    if (!str || !str.includes('{')) {
        return [];
    }
    const inner = str.replace(/[{}]/g, '').trim();
    if (!inner) {
        return [];
    }
    return inner.split(',').map(s => parseHex(s.trim()));
}

function parseHex(str) {
    if (!str) {
        return 0;
    }
    str = str.trim();
    if (str.startsWith('0x') || str.startsWith('0X')) {
        return parseInt(str, 16) | 0;
    }
    return parseInt(str, 10) || 0;
}

function int(str) {
    if (!str) {
        return 0;
    }
    return parseInt(str.trim(), 10) || 0;
}
