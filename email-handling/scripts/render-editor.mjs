import { readFile, writeFile } from 'node:fs/promises';
import { isAbsolute } from 'node:path';

const [inputPath, outputPath] = process.argv.slice(2);
if (process.argv.length !== 4 || !isAbsolute(outputPath)) {
  throw new Error('Usage: node render-editor.mjs <draft.json> <absolute-output.html>');
}

const draft = JSON.parse((await readFile(inputPath, 'utf8')).replace(/^\uFEFF/, ''));
for (const key of ['draftId', 'destinationLabel', 'destination', 'body']) {
  if (typeof draft[key] !== 'string') {
    throw new Error('Expected a string in draft field ' + key);
  }
}
if (draft.subject !== null && typeof draft.subject !== 'string') {
  throw new Error('Expected subject to be a string or null.');
}
const bodyFormat = draft.bodyFormat ?? 'plain';
if (bodyFormat !== 'plain' && bodyFormat !== 'markdown') {
  throw new Error('Expected bodyFormat to be plain or markdown.');
}
if (!Array.isArray(draft.attachments)) {
  throw new Error('Expected an attachments array.');
}

const attachments = draft.attachments.map(({ name, url }) => {
  if (typeof name !== 'string' || !name.trim()) {
    throw new Error('Expected a file name for each attachment.');
  }
  if (url == null) return { name };
  if (typeof url !== 'string') {
    throw new Error('Expected an HTTPS URL for attachment ' + name);
  }
  const parsedUrl = new URL(url);
  if (parsedUrl.protocol !== 'https:' || parsedUrl.username || parsedUrl.password) {
    throw new Error('Expected an HTTPS URL without credentials for attachment ' + name);
  }
  return { name, url: parsedUrl.href };
});

const editorDraft = {
  draftId: draft.draftId,
  destinationLabel: draft.destinationLabel,
  destination: draft.destination,
  subject: draft.subject,
  body: draft.body,
  bodyFormat,
  attachments,
};
const template = await readFile(new URL('../assets/message-editor.html', import.meta.url), 'utf8');
const json = JSON.stringify(editorDraft).replaceAll('<', '\\u003c');
const fragment = template.replace('__OUTBOUND_MESSAGE_DRAFT__', () => json);
await writeFile(outputPath, fragment, { encoding: 'utf8', flag: 'wx' });
