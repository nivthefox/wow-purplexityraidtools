import { writeFile } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import { fetchSimcData } from './lib/fetch-simc.mjs';
import { parseSpecializationData } from './lib/parse-specialization-data.mjs';
import { parseSpellData, parseFieldLayout } from './lib/parse-spell-data.mjs';
import { parseClassSpells } from './lib/parse-class-spells.mjs';
import { parseSpecializationSpells } from './lib/parse-specialization-spells.mjs';
import { parseTraitData } from './lib/parse-trait-data.mjs';
import { buildSpecAbilities } from './lib/build-spec-abilities.mjs';
import { extractModifiers } from './lib/extract-modifiers.mjs';
import { generateLua } from './lib/generate-lua.mjs';
import { validate } from './lib/validate.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const OUTPUT_PATH = resolve(__dirname, '..', 'SpellData.lua');

async function main() {
    console.log('Fetching SimC data...');
    const raw = await fetchSimcData();

    const buildMatch = raw.spellData.match(/wow build[^\n]*?(\d[\d.]+)/i);
    const buildInfo = buildMatch ? `build ${buildMatch[1]}` : 'unknown build';
    console.log(`SimC ${buildInfo}`);

    console.log('\nDiscovering struct field layout from spell_data.hpp...');
    const fieldLayout = parseFieldLayout(raw.spellDataHpp);

    console.log('\nDiscovering specs...');
    const specs = parseSpecializationData(raw.specializationData, raw.specList);
    console.log(`    ${specs.size} player specs discovered`);

    console.log('\nParsing spell data...');
    const { spells, effects, labels } = parseSpellData(raw.spellData, fieldLayout);

    console.log('\nParsing class spells...');
    const classSpells = parseClassSpells(raw.classSpells);
    console.log(`    ${classSpells.length} entries`);

    console.log('\nParsing specialization spells...');
    const specSpells = parseSpecializationSpells(raw.specializationSpells);
    console.log(`    ${specSpells.length} entries`);

    console.log('\nParsing trait data...');
    const traits = parseTraitData(raw.traitData);
    console.log(`    ${traits.length} traits`);

    console.log('\nBuilding per-spec ability lists...');
    const specAbilities = buildSpecAbilities(specs, spells, classSpells, specSpells, traits);

    console.log('\nExtracting talent modifiers...');
    extractModifiers(specAbilities, traits, spells, effects, labels, specs);

    console.log('\nValidating...');
    validate(specAbilities);

    console.log('\nGenerating SpellData.lua...');
    const lua = generateLua(specAbilities, buildInfo);

    await writeFile(OUTPUT_PATH, lua, 'utf-8');
    console.log(`\nWrote ${OUTPUT_PATH}`);
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
