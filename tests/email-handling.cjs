const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// Synthetic drafts only. No mail integration or send operation is invoked.
const root = path.resolve(__dirname, '..');
const work = fs.mkdtempSync(path.join(fs.mkdirSync(path.join(root, '.tmp'), { recursive: true }) || path.join(root, '.tmp'), 'email-test-'));
const helper = path.join(root, 'email-handling/scripts/render-editor.mjs');
const draft = {
  draftId: 'synthetic-1', destinationLabel: 'To', destination: 'recipient@example.com',
  subject: 'Synthetic preview', body: '**Hello**\n</script><script>unsafe()</script>',
  bodyFormat: 'markdown', attachments: [{ name: 'sample.txt', url: 'https://example.com/sample.txt' }],
};
function run(data, output) {
  const input = path.join(work, 'draft.json');
  fs.writeFileSync(input, JSON.stringify(data));
  return spawnSync(process.execPath, [helper, input, output], { encoding: 'utf8' });
}
const output = path.join(work, 'editor with spaces.html');
assert.equal(run(draft, output).status, 0);
const html = fs.readFileSync(output, 'utf8');
const json = html.match(/<script type="application\/json" id="outbound-message-draft">([\s\S]*?)<\/script>/)[1];
assert.deepEqual(JSON.parse(json), draft);
assert.ok(!json.includes('<'));
assert.ok(!html.includes('__OUTBOUND_MESSAGE_DRAFT__'));
assert.notEqual(run(draft, output).status, 0, 'Do not overwrite an existing editor');
assert.equal(fs.readFileSync(output, 'utf8'), html);
for (const url of ['http://example.com/a', 'https://user:password@example.com/a', 'javascript:alert(1)']) {
  const invalid = { ...draft, attachments: [{ name: 'bad.txt', url }] };
  assert.notEqual(run(invalid, path.join(work, 'invalid.html')).status, 0);
  assert.ok(!fs.existsSync(path.join(work, 'invalid.html')));
}
const plain = { ...draft, subject: null, attachments: [{ name: 'local.txt' }] };
delete plain.bodyFormat;
const plainOutput = path.join(work, 'plain.html');
assert.equal(run(plain, plainOutput).status, 0);
assert.ok(fs.readFileSync(plainOutput, 'utf8').includes('"bodyFormat":"plain"'));
assert.notEqual(spawnSync(process.execPath, [helper, path.join(work, 'draft.json'), 'relative.html']).status, 0);
console.log('PASS: synthetic editor generation, script-safe JSON, no overwrite, attachment validation, plain fallback, absolute output path; no email sent.');
