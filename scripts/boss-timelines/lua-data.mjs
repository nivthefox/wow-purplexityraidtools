import { validateDatabase } from './schema.mjs';

const ASSIGNMENT = 'PRT.BossTimelineData =';

function escapeLuaString(value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');
}

function renderOccurrences(lines, occurrences, indent) {
    lines.push(`${indent}occurrences = {`);
    for (const occurrence of occurrences) {
        lines.push(`${indent}    { spellID = ${occurrence.spellID}, time = ${occurrence.time}, observations = ${occurrence.observations} },`);
    }
    lines.push(`${indent}},`);
}

function renderPhase(lines, phase, indent) {
    lines.push(`${indent}{`);
    lines.push(`${indent}    phaseID = ${phase.phaseID},`);
    lines.push(`${indent}    name = "${escapeLuaString(phase.name)}",`);
    lines.push(`${indent}    isIntermission = ${phase.isIntermission},`);
    renderOccurrences(lines, phase.occurrences, `${indent}    `);
    lines.push(`${indent}},`);
}

export function serializeDatabase(database) {
    validateDatabase(database);
    const lines = [
        'local PRT = PurplexityRaidTools',
        '',
        `${ASSIGNMENT} {`,
        `    schemaVersion = ${database.schemaVersion},`,
        '    encounters = {',
    ];

    const encounterIDs = Object.keys(database.encounters).map(Number).sort((a, b) => a - b);
    for (const encounterID of encounterIDs) {
        const encounter = database.encounters[encounterID];
        lines.push(`        [${encounterID}] = {`);
        lines.push('            difficulties = {');
        const difficultyIDs = Object.keys(encounter.difficulties).map(Number).sort((a, b) => a - b);
        for (const difficultyID of difficultyIDs) {
            const difficulty = encounter.difficulties[difficultyID];
            lines.push(`                [${difficultyID}] = {`);
            lines.push('                    phases = {');
            for (const phase of difficulty.phases) {
                renderPhase(lines, phase, '                        ');
            }
            lines.push('                    },');
            lines.push('                },');
        }
        lines.push('            },');
        lines.push('        },');
    }

    lines.push('    },');
    lines.push('}');
    lines.push('');
    return lines.join('\n');
}

function tokenize(source) {
    const tokens = [];
    let index = 0;
    while (index < source.length) {
        const remaining = source.slice(index);
        const whitespace = remaining.match(/^\s+/);
        if (whitespace) {
            index += whitespace[0].length;
            continue;
        }
        const string = remaining.match(/^"(?:\\.|[^"\\])*"/);
        if (string) {
            tokens.push({ type: 'string', value: JSON.parse(string[0]) });
            index += string[0].length;
            continue;
        }
        const number = remaining.match(/^\d+/);
        if (number) {
            tokens.push({ type: 'number', value: Number(number[0]) });
            index += number[0].length;
            continue;
        }
        const identifier = remaining.match(/^[A-Za-z_][A-Za-z0-9_]*/);
        if (identifier) {
            tokens.push({ type: 'identifier', value: identifier[0] });
            index += identifier[0].length;
            continue;
        }
        if ('{}[]=,'.includes(source[index])) {
            tokens.push({ type: source[index], value: source[index] });
            index += 1;
            continue;
        }
        throw new Error('Generated boss timeline Lua contains unsupported syntax');
    }
    return tokens;
}

function createParser(tokens) {
    let index = 0;

    function peek(type) {
        return tokens[index]?.type === type;
    }

    function take(type) {
        const token = tokens[index];
        if (!token || token.type !== type) {
            throw new Error(`Generated boss timeline Lua expected ${type}`);
        }
        index += 1;
        return token.value;
    }

    function parseValue() {
        if (peek('{')) {
            return parseTable();
        }
        if (peek('number')) {
            return take('number');
        }
        if (peek('string')) {
            return take('string');
        }
        if (peek('identifier')) {
            const value = take('identifier');
            if (value === 'true') {
                return true;
            }
            if (value === 'false') {
                return false;
            }
        }
        throw new Error('Generated boss timeline Lua contains an invalid value');
    }

    function parseTable() {
        take('{');
        const entries = [];
        let arrayIndex = 1;
        while (!peek('}')) {
            let key = arrayIndex;
            if (peek('[')) {
                take('[');
                key = take('number');
                take(']');
                take('=');
            } else if (peek('identifier') && tokens[index + 1]?.type === '=') {
                key = take('identifier');
                take('=');
            } else {
                arrayIndex += 1;
            }
            entries.push([key, parseValue()]);
            if (peek(',')) {
                take(',');
            }
        }
        take('}');

        if (entries.length === 0) {
            return {};
        }
        const numericKeys = entries.every(([key]) => Number.isInteger(key));
        if (numericKeys && entries.every(([key], entryIndex) => key === entryIndex + 1)) {
            return entries.map(([, value]) => value);
        }
        return Object.fromEntries(entries.map(([key, value]) => [String(key), value]));
    }

    return {
        parse() {
            const value = parseValue();
            if (index !== tokens.length) {
                throw new Error('Generated boss timeline Lua contains trailing syntax');
            }
            return value;
        },
    };
}

function normalizeEmptyArrays(database) {
    if (!database || typeof database !== 'object' || Array.isArray(database)) {
        return database;
    }
    for (const encounter of Object.values(database.encounters ?? {})) {
        for (const difficulty of Object.values(encounter.difficulties ?? {})) {
            for (const phase of difficulty.phases ?? []) {
                if (phase.occurrences && !Array.isArray(phase.occurrences)
                    && Object.keys(phase.occurrences).length === 0) {
                    phase.occurrences = [];
                }
            }
        }
    }
    return database;
}

export function parseDatabase(source) {
    const assignmentIndex = source.indexOf(ASSIGNMENT);
    if (assignmentIndex === -1) {
        throw new Error('BossTimelineData.lua does not expose PRT.BossTimelineData');
    }
    const tableSource = source.slice(assignmentIndex + ASSIGNMENT.length);
    const database = normalizeEmptyArrays(createParser(tokenize(tableSource)).parse());
    return validateDatabase(database);
}
