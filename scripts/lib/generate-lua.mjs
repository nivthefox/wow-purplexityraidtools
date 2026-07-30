/**
 * Render specAbilities into a Lua source string matching the spec format.
 */
export function generateLua(specAbilities, buildInfo) {
    const lines = [];
    lines.push(`-- SpellData.lua (auto-generated, do not edit)`);
    lines.push(`-- Source: SimulationCraft dbc_extract3 (${buildInfo})`);
    lines.push('');
    lines.push('local PRT = PurplexityRaidTools');
    lines.push('');
    lines.push('PRT.SpellData = {');

    const sortedSpecIds = [...specAbilities.keys()].sort((a, b) => a - b);

    for (const specId of sortedSpecIds) {
        const spec = specAbilities.get(specId);
        const abilityCount = spec.abilities.size;

        lines.push(`    [${specId}] = {`);
        lines.push(`        name = ${luaString(spec.specName)},`);
        lines.push(`        class = ${luaString(spec.classToken)},`);
        lines.push(`        abilities = {`);

        const sortedAbilityIds = [...spec.abilities.keys()].sort((a, b) => a - b);

        for (const abilityId of sortedAbilityIds) {
            const ability = spec.abilities.get(abilityId);
            renderAbility(lines, ability);
        }

        lines.push('        },');
        lines.push(`    },`);
    }

    lines.push('}');
    lines.push('');

    return lines.join('\n');
}

function renderAbility(lines, ability) {
    lines.push(`            [${ability.spellId}] = {`);
    lines.push(`                spellId = ${ability.spellId},`);
    lines.push(`                name = ${luaString(ability.name)},`);
    lines.push(`                duration = ${ability.duration},`);
    lines.push(`                cooldown = ${ability.cooldown},`);
    lines.push(`                charges = ${ability.charges},`);

    if (ability.channeled) {
        lines.push(`                channeled = true,`);
    }

    if (ability.flags && ability.flags.length > 0) {
        const flagStrs = ability.flags.map(f => typeof f === 'string' ? luaString(f) : String(f));
        lines.push(`                flags = { ${flagStrs.join(', ')} },`);
    }

    if (ability.talents && Object.keys(ability.talents).length > 0) {
        lines.push('                talents = {');
        const sortedTalentIds = Object.keys(ability.talents).map(Number).sort((a, b) => a - b);
        for (const talentId of sortedTalentIds) {
            const mods = ability.talents[talentId];
            const modParts = [];
            for (const [key, val] of Object.entries(mods).sort()) {
                modParts.push(`${key} = ${val}`);
            }
            lines.push(`                    [${talentId}] = { ${modParts.join(', ')} },`);
        }
        lines.push('                },');
    }

    lines.push('            },');
}

function luaString(str) {
    const escaped = str.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
    return `"${escaped}"`;
}
