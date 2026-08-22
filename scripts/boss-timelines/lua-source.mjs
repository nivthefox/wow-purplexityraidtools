function stripLuaComments(source) {
    let output = '';
    let index = 0;
    let quote = null;
    while (index < source.length) {
        const char = source[index];
        const next = source[index + 1];
        if (quote) {
            if (char === '\\') {
                output += '  ';
                index += 2;
                continue;
            }
            if (char === quote) {
                quote = null;
                output += char;
            } else {
                output += char === '\n' ? '\n' : ' ';
            }
            index += 1;
            continue;
        }
        if (char === '"' || char === "'") {
            quote = char;
            output += char;
            index += 1;
            continue;
        }
        if (char === '[' && next === '[') {
            const end = source.indexOf(']]', index + 2);
            if (end === -1) {
                throw new Error('Unterminated Lua long string');
            }
            const value = source.slice(index, end + 2);
            output += value.replace(/[^\n]/g, ' ');
            index = end + 2;
            continue;
        }
        if (char === '-' && next === '-' && source.slice(index + 2, index + 4) === '[[') {
            const end = source.indexOf(']]', index + 4);
            if (end === -1) {
                throw new Error('Unterminated Lua block comment');
            }
            output += '\n'.repeat(source.slice(index, end + 2).split('\n').length - 1);
            index = end + 2;
            continue;
        }
        if (char === '-' && next === '-') {
            const end = source.indexOf('\n', index + 2);
            if (end === -1) {
                break;
            }
            output += '\n';
            index = end + 1;
            continue;
        }
        output += char;
        index += 1;
    }
    return output;
}

function splitArguments(argumentSource) {
    const argumentsList = [];
    let current = '';
    let depth = 0;
    let quote = null;
    for (let index = 0; index < argumentSource.length; index += 1) {
        const char = argumentSource[index];
        if (quote) {
            current += char;
            if (char === '\\') {
                current += argumentSource[index + 1] ?? '';
                index += 1;
            } else if (char === quote) {
                quote = null;
            }
            continue;
        }
        if (char === '"' || char === "'") {
            quote = char;
            current += char;
            continue;
        }
        if ('({['.includes(char)) {
            depth += 1;
        } else if (')}]'.includes(char)) {
            depth -= 1;
        }
        if (char === ',' && depth === 0) {
            argumentsList.push(current.trim());
            current = '';
            continue;
        }
        current += char;
    }
    argumentsList.push(current.trim());
    return argumentsList;
}

function findCalls(source, pattern) {
    const calls = [];
    let match;
    pattern.lastIndex = 0;
    while ((match = pattern.exec(source)) !== null) {
        if (/function\s*$/.test(source.slice(Math.max(0, match.index - 20), match.index))) {
            continue;
        }
        const openIndex = source.indexOf('(', match.index);
        let depth = 1;
        let quote = null;
        let index = openIndex + 1;
        for (; index < source.length && depth > 0; index += 1) {
            const char = source[index];
            if (quote) {
                if (char === '\\') {
                    index += 1;
                } else if (char === quote) {
                    quote = null;
                }
                continue;
            }
            if (char === '"' || char === "'") {
                quote = char;
            } else if (char === '(') {
                depth += 1;
            } else if (char === ')') {
                depth -= 1;
            }
        }
        if (depth !== 0) {
            throw new Error(`Unterminated Lua call to ${match[1]}`);
        }
        calls.push({ name: match[1], index: match.index, arguments: splitArguments(source.slice(openIndex + 1, index - 1)) });
        pattern.lastIndex = index;
    }
    return calls;
}

function numericLiteral(value) {
    if (!/^\d+$/.test(value)) {
        return null;
    }
    const number = Number(value);
    return Number.isSafeInteger(number) && number > 0 ? number : null;
}

function extractEncounterID(source) {
    const matches = [...source.matchAll(/:\s*SetEncounterID\s*\(\s*(\d+)\s*\)/g)].map((match) => Number(match[1]));
    if (matches.length > 1 && new Set(matches).size > 1) {
        throw new Error('Boss module declares conflicting encounter IDs');
    }
    return matches[0] ?? null;
}

function extractBigWigsJournalID(source) {
    const calls = findCalls(source, /BigWigs\s*:\s*(NewBoss)\s*\(/g);
    if (calls.length === 0) {
        return null;
    }
    if (calls.length > 1) {
        throw new Error('BigWigs source contains multiple boss declarations');
    }
    if (calls[0].arguments.length < 3) {
        return null;
    }
    const journalID = numericLiteral(calls[0].arguments.at(-1));
    if (!journalID) {
        throw new Error('BigWigs boss declaration has no journal ID');
    }
    return journalID;
}

function extractBigWigsTimerIDs(source) {
    const ids = new Set();
    const calls = findCalls(source, /:\s*(Bar|CDBar|CastBar)\s*\(/g);
    for (const call of calls) {
        const id = numericLiteral(call.arguments[0]);
        if (id) {
            ids.add(id);
        }
    }

    if (!/:\s*(?:Bar|CDBar|CastBar)\s*\(\s*barInfo\.key\b/.test(source)) {
        return ids;
    }
    const functions = [...source.matchAll(/function\s+(?:mod|self)\s*:\s*([A-Za-z0-9_]+)\s*\([^)]*\)/g)];
    for (let index = 0; index < functions.length; index += 1) {
        const name = functions[index][1];
        const bodyStart = functions[index].index + functions[index][0].length;
        const bodyEnd = functions[index + 1]?.index ?? source.length;
        const body = source.slice(bodyStart, bodyEnd);
        if (!new RegExp(`\\bbarInfo\\s*=\\s*(?:self|mod)\\s*:\\s*${name}\\s*\\(`).test(source)) {
            continue;
        }
        const returnedKey = body.match(/\breturn\s*\{[\s\S]*?\bkey\s*=\s*(\d+)\b/);
        if (returnedKey) {
            ids.add(Number(returnedKey[1]));
        }
    }
    return ids;
}

const EXCLUDED_DBM_TIMERS = /(?:Stage|Phase|Combat|Berserk|Roleplay|Achievement|SpeedClear|Intermission)Timer$/;

function extractDbmJournalID(source) {
    const calls = findCalls(source, /DBM\s*:\s*(NewMod)\s*\(/g);
    if (calls.length === 0) {
        return null;
    }
    if (calls.length > 1) {
        throw new Error('DBM source contains multiple boss declarations');
    }
    return numericLiteral(calls[0].arguments[0]);
}

function extractDbmTimerIDs(source) {
    const ids = new Set();
    const calls = findCalls(source, /:\s*(New[A-Za-z0-9_]*Timer)\s*\(/g);
    for (const call of calls) {
        if (EXCLUDED_DBM_TIMERS.test(call.name)) {
            continue;
        }
        const lineStart = source.lastIndexOf('\n', call.index) + 1;
        const assignment = source.slice(lineStart, call.index).match(/(?:local\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:mod|self)\s*$/);
        if (!assignment) {
            continue;
        }
        const timerName = assignment[1];
        const activation = new RegExp(`\\b${timerName}\\s*:\\s*(?:Start|TLStart|SetTimeline)\\s*\\(`);
        if (!activation.test(source)) {
            continue;
        }
        const idPosition = call.name.includes('Var') ? 2 : 1;
        const id = numericLiteral(call.arguments[idPosition]);
        if (id) {
            ids.add(id);
        }
    }
    return ids;
}

export function parseBossModule(source, bossMod) {
    const cleanSource = stripLuaComments(source);
    if (bossMod === 'bigwigs') {
        const journalID = extractBigWigsJournalID(cleanSource);
        if (!journalID) {
            return null;
        }
        return {
            bossMod,
            journalID,
            encounterID: extractEncounterID(cleanSource),
            timerIDs: extractBigWigsTimerIDs(cleanSource),
        };
    }
    if (bossMod === 'dbm') {
        const journalID = extractDbmJournalID(cleanSource);
        if (!journalID) {
            return null;
        }
        return {
            bossMod,
            journalID,
            encounterID: extractEncounterID(cleanSource),
            timerIDs: extractDbmTimerIDs(cleanSource),
        };
    }
    throw new Error(`Unsupported boss mod ${bossMod}`);
}

export function mergeBossModules(modules) {
    const byJournalID = new Map();
    for (const module of modules) {
        if (!module) {
            continue;
        }
        let encounter = byJournalID.get(module.journalID);
        if (!encounter) {
            encounter = { journalID: module.journalID, encounterID: null, bigwigs: new Set(), dbm: new Set() };
            byJournalID.set(module.journalID, encounter);
        }
        if (module.encounterID) {
            if (encounter.encounterID && encounter.encounterID !== module.encounterID) {
                throw new Error(`Boss mods disagree on encounter ID for journal ID ${module.journalID}`);
            }
            encounter.encounterID = module.encounterID;
        }
        for (const timerID of module.timerIDs) {
            encounter[module.bossMod].add(timerID);
        }
    }
    return byJournalID;
}
