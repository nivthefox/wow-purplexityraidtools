import { mkdir, readFile, rename, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { formatOmission, generateDatabase } from './boss-timelines/generator.mjs';
import { parseDatabase, serializeDatabase } from './boss-timelines/lua-data.mjs';
import { loadBossModules } from './boss-timelines/source-files.mjs';
import { WarcraftLogsClient } from './boss-timelines/wcl-client.mjs';

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const addonRoot = resolve(scriptDirectory, '..');
const outputPath = resolve(addonRoot, 'BossTimelineData.lua');

function parseArguments(argumentsList) {
    const values = new Map();
    for (let index = 0; index < argumentsList.length; index += 2) {
        const key = argumentsList[index];
        const value = argumentsList[index + 1];
        if (!key?.startsWith('--') || !value) {
            throw new Error('Expected --bigwigs PATH and --dbm PATH');
        }
        values.set(key, value);
    }
    if (!values.has('--bigwigs') || !values.has('--dbm')) {
        throw new Error('Expected --bigwigs PATH and --dbm PATH');
    }
    return { bigwigsRoot: resolve(values.get('--bigwigs')), dbmRoot: resolve(values.get('--dbm')) };
}

async function writeAtomically(path, contents) {
    const temporaryPath = `${path}.tmp`;
    await mkdir(dirname(path), { recursive: true });
    try {
        await writeFile(temporaryPath, contents, { encoding: 'utf8', flag: 'wx' });
        await rename(temporaryPath, path);
    } finally {
        await rm(temporaryPath, { force: true });
    }
}

async function main() {
    const { bigwigsRoot, dbmRoot } = parseArguments(process.argv.slice(2));
    const existingSource = await readFile(outputPath, 'utf8');
    const existingDatabase = parseDatabase(existingSource);
    const bossModules = await loadBossModules(bigwigsRoot, dbmRoot);
    const client = new WarcraftLogsClient({
        clientID: process.env.WCL_CLIENT_ID,
        clientSecret: process.env.WCL_CLIENT_SECRET,
    });
    const database = await generateDatabase({
        client,
        bossModules,
        existingDatabase,
        buildTime: Date.now(),
        onOmission: (omission) => {
            process.stdout.write(`${formatOmission(omission)}\n`);
        },
    });
    await writeAtomically(outputPath, serializeDatabase(database));
}

main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
});
