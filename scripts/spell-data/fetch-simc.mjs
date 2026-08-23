import { SIMC_REPO, SIMC_GENERATED_PATH } from './constants.mjs';

const SIMC_HPP_PATH = 'engine/dbc/spell_data.hpp';

async function resolveDefaultBranch() {
    const res = await fetch(`https://api.github.com/repos/${SIMC_REPO}`, {
        headers: { 'Accept': 'application/vnd.github.v3+json' },
    });
    if (!res.ok) {
        throw new Error(`GitHub API error resolving default branch: ${res.status} ${res.statusText}`);
    }
    const data = await res.json();
    return data.default_branch;
}

async function fetchRawFile(branch, path) {
    const url = `https://raw.githubusercontent.com/${SIMC_REPO}/${branch}/${path}`;
    const res = await fetch(url);
    if (!res.ok) {
        throw new Error(`Failed to fetch ${path} from branch "${branch}": ${res.status} ${res.statusText}`);
    }
    return res.text();
}

function fetchGeneratedFile(branch, filename) {
    return fetchRawFile(branch, `${SIMC_GENERATED_PATH}/${filename}`);
}

export async function fetchSimcData() {
    const branch = await resolveDefaultBranch();
    console.log(`Using SimC branch: ${branch}`);

    const generatedFiles = [
        'sc_spell_data.inc',
        'sc_specialization_data.inc',
        'sc_spec_list.inc',
        'class_spells.inc',
        'specialization_spells.inc',
        'trait_data.inc',
    ];

    const [generatedResults, spellDataHpp] = await Promise.all([
        Promise.all(generatedFiles.map(f => fetchGeneratedFile(branch, f))),
        fetchRawFile(branch, SIMC_HPP_PATH),
    ]);

    return {
        branch,
        spellData:            generatedResults[0],
        specializationData:   generatedResults[1],
        specList:             generatedResults[2],
        classSpells:          generatedResults[3],
        specializationSpells: generatedResults[4],
        traitData:            generatedResults[5],
        spellDataHpp,
    };
}
