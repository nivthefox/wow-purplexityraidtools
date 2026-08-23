import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const workflowPath = new URL('../../../.github/workflows/update-boss-timelines.yml', import.meta.url);

test('workflow is Wednesday/manual, uses build environment, and creates only reviewed database changes', async () => {
    const source = await readFile(workflowPath, 'utf8');
    assert.match(source, /cron: '0 8 \* \* 3'/);
    assert.match(source, /workflow_dispatch:/);
    assert.match(source, /environment: build/);
    assert.match(source, /WCL_CLIENT_ID: \$\{\{ secrets\.WCL_CLIENT_ID \}\}/);
    assert.match(source, /WCL_CLIENT_SECRET: \$\{\{ secrets\.WCL_CLIENT_SECRET \}\}/);
    assert.match(source, /group: update-boss-timelines/);
    assert.match(source, /cancel-in-progress: false/);
    assert.match(source, /git add BossTimelineData\.lua/);
    assert.doesNotMatch(source, /git add \./);
    assert.match(source, /if: steps\.diff\.outputs\.changed == 'true'/);
    assert.match(source, /luajit tests\/run_tests\.lua/);
    const generation = source.indexOf('- name: Generate boss timelines');
    const generatedValidation = source.indexOf('- name: Validate generated boss timelines');
    assert.notEqual(generation, -1);
    assert.ok(generatedValidation > generation);
});

test('workflow resolves immutable boss-mod revisions and publishes no artifacts or automatic merge', async () => {
    const source = await readFile(workflowPath, 'utf8');
    assert.equal((source.match(/rev-parse --verify HEAD/g) ?? []).length, 2);
    assert.doesNotMatch(source, /upload-artifact/);
    assert.doesNotMatch(source, /gh pr merge/);
    assert.doesNotMatch(source, /report\.code|fightID|revision manifest/i);
});
