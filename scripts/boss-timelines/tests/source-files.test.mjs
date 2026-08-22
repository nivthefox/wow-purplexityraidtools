import assert from 'node:assert/strict';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';

import { listLuaFiles } from '../source-files.mjs';

async function createFile(root, relativePath) {
    const path = join(root, relativePath);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, '', 'utf8');
    return path;
}

test('source discovery excludes infrastructure and test trees without maintaining a tier list', async () => {
    const root = await mkdtemp(join(tmpdir(), 'prt-boss-source-'));
    try {
        const bigwigsBoss = await createFile(root, join('TheCurrentRaid', 'Boss.lua'));
        await createFile(root, join('Core', 'TestBoss.lua'));
        await createFile(root, join('Tools', 'Fixture.lua'));
        assert.deepEqual(await listLuaFiles(root, 'bigwigs'), [bigwigsBoss]);

        await rm(root, { recursive: true, force: true });
        await mkdir(root, { recursive: true });
        const dbmBoss = await createFile(root, join('DBM-Raids-Current', 'Boss.lua'));
        await createFile(root, join('DBM-Core', 'Demo.lua'));
        await createFile(root, join('DBM-Test', 'Fixture.lua'));
        assert.deepEqual(await listLuaFiles(root, 'dbm'), [dbmBoss]);
    } finally {
        await rm(root, { recursive: true, force: true });
    }
});
