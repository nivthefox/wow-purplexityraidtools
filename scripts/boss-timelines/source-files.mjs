import { readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

import { mergeBossModules, parseBossModule } from './lua-source.mjs';

const execFileAsync = promisify(execFile);

const EXCLUDED_DIRECTORIES = {
    bigwigs: new Set(['.github', 'Core', 'Libs', 'Locales', 'Media', 'Options', 'Plugins', 'Tools']),
    dbm: new Set(['.github', '.vscode', 'DBM-Core', 'DBM-GUI', 'DBM-StatusBarTimers', 'DBM-Test']),
};

export async function listLuaFiles(root, bossMod) {
    const files = [];
    async function visit(directory, depth) {
        const entries = await readdir(directory, { withFileTypes: true });
        entries.sort((left, right) => left.name.localeCompare(right.name));
        for (const entry of entries) {
            if (entry.name === '.git' || (depth === 0 && EXCLUDED_DIRECTORIES[bossMod].has(entry.name))) {
                continue;
            }
            const path = join(directory, entry.name);
            if (entry.isDirectory()) {
                await visit(path, depth + 1);
            } else if (entry.isFile() && entry.name.endsWith('.lua')) {
                files.push(path);
            }
        }
    }
    await visit(root, 0);
    return files;
}

export async function resolveRevision(root) {
    const { stdout } = await execFileAsync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
    const revision = stdout.trim();
    if (!/^[0-9a-f]{40}$/.test(revision)) {
        throw new Error('Boss-mod checkout did not resolve to an immutable Git revision');
    }
    const status = await execFileAsync('git', ['-C', root, 'status', '--porcelain'], { encoding: 'utf8' });
    if (status.stdout.trim() !== '') {
        throw new Error('Boss-mod checkout differs from its resolved Git revision');
    }
    return revision;
}

async function parseSourceTree(root, bossMod) {
    await resolveRevision(root);
    const modules = [];
    for (const path of await listLuaFiles(root, bossMod)) {
        const source = await readFile(path, 'utf8');
        const module = parseBossModule(source, bossMod);
        if (module) {
            modules.push(module);
        }
    }
    return modules;
}

export async function loadBossModules(bigwigsRoot, dbmRoot) {
    const bigwigs = await parseSourceTree(bigwigsRoot, 'bigwigs');
    const dbm = await parseSourceTree(dbmRoot, 'dbm');
    return mergeBossModules([...bigwigs, ...dbm]);
}
