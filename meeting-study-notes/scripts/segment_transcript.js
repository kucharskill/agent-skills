#!/usr/bin/env node
// Standalone CLI: no package.json, npm packages or module-type setting required.
(async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const { createHash } = await import('node:crypto');
  const { TextDecoder } = await import('node:util');
  const argv = process.argv.slice(2);
  const help = 'Usage: node segment_transcript.js SOURCE --out DIRECTORY [--target-chars 9000] [--overlap-chars 1000]';
  if (argv.includes('--help') || argv.includes('-h')) { console.log(help); return; }
  let source, out, target = 9000, overlap = 1000;
  const seen = new Set();
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (['--out', '--target-chars', '--overlap-chars'].includes(arg)) {
      if (seen.has(arg) || i + 1 >= argv.length || argv[i + 1].startsWith('--')) throw new Error(`Missing or repeated option: ${arg}`);
      seen.add(arg);
      const value = argv[++i];
      if (arg === '--out') out = value;
      else if (arg === '--target-chars') target = Number(value);
      else overlap = Number(value);
    } else if (arg.startsWith('-') || source) throw new Error(`Unexpected argument: ${arg}`);
    else source = arg;
  }
  if (!source || !out) throw new Error(help);
  if (!Number.isSafeInteger(target) || target < 100 || !Number.isSafeInteger(overlap) || overlap < 0 || overlap >= target) {
    throw new Error('Use integer target >= 100 and 0 <= overlap < target');
  }
  const text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(await fs.readFile(source)).replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  if (!text.trim()) throw new Error('Empty source');
  // Python-compatible character offsets: Unicode code points, not UTF-16 units.
  const offsets = [0];
  for (const char of text) offsets.push(offsets[offsets.length - 1] + char.length);
  const characters = offsets.length - 1;
  function lowerBound(values, value) {
    let lo = 0, hi = values.length;
    while (lo < hi) { const mid = (lo + hi) >>> 1; if (values[mid] < value) lo = mid + 1; else hi = mid; }
    return lo;
  }
  const ends = [];
  const paragraphs = /\n[ \t]*\n+/g;
  let match;
  while ((match = paragraphs.exec(text))) ends.push(lowerBound(offsets, match.index + match[0].length));
  if (ends[ends.length - 1] !== characters) ends.push(characters);
  const newlines = [];
  for (let i = 0; i < characters; i++) if (text[offsets[i]] === '\n') newlines.push(i);
  const lineAt = index => lowerBound(newlines, index) + 1;
  const slice = (a, b) => text.slice(offsets[a], offsets[b]);
  const chunks = [];
  let start = 0;
  while (start < characters) {
    const limit = Math.min(start + target, characters);
    const candidate = ends[lowerBound(ends, limit + 1) - 1];
    let end;
    if (candidate > start) end = candidate;
    else {
      const window = slice(start, limit);
      const sentences = /[.!?。！？]["”»')\]]*\s+/g;
      const whitespace = /\s+/g;
      let sentenceEnd = 0, whitespaceEnd = 0;
      while ((match = sentences.exec(window))) sentenceEnd = match.index + match[0].length;
      while ((match = whitespace.exec(window))) whitespaceEnd = match.index + match[0].length;
      const units = sentenceEnd || whitespaceEnd || window.length;
      end = lowerBound(offsets, offsets[start] + units);
    }
    const minimumContext = Math.max(0, start - overlap);
    const boundary = ends[lowerBound(ends, minimumContext)];
    const context = boundary <= start ? boundary : minimumContext;
    const index = chunks.length + 1;
    chunks.push({ id: `C${String(index).padStart(3, '0')}`, file: `chunk-${String(index).padStart(3, '0')}.md`,
      core_start: start, core_end: end, context_start: context,
      source_line_start: lineAt(start), source_line_end: lineAt(end - 1) });
    start = end;
  }
  const directory = path.resolve(out);
  const manifestPath = path.join(directory, 'manifest.json');
  await fs.mkdir(directory, { recursive: true });
  // Never overwrite a previous manifest, source snapshot or partial run.
  const outputs = ['manifest.json', 'source.txt', ...chunks.map(chunk => chunk.file)];
  for (const name of outputs) {
    try { await fs.lstat(path.join(directory, name)); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    throw new Error(`Output already exists: ${name}; choose a new working directory`);
  }
  await fs.writeFile(path.join(directory, 'source.txt'), text, { encoding: 'utf8', flag: 'wx' });
  for (const chunk of chunks) {
    let content = `<!-- ${chunk.id}; core chars [${chunk.core_start},${chunk.core_end}); source lines L${chunk.source_line_start}-L${chunk.source_line_end} -->\n`;
    if (chunk.context_start < chunk.core_start) content += '\n<!-- CONTEXT ONLY: already covered by previous chunk -->\n' + slice(chunk.context_start, chunk.core_start);
    content += '\n<!-- CORE START -->\n' + slice(chunk.core_start, chunk.core_end) + '\n<!-- CORE END -->\n';
    await fs.writeFile(path.join(directory, chunk.file), content, { encoding: 'utf8', flag: 'wx' });
  }
  const manifest = { version: 1, offset_units: 'unicode-code-points', source: path.resolve(source), normalized_source: path.join(directory, 'source.txt'),
    sha256: createHash('sha256').update(text, 'utf8').digest('hex'), characters, target_chars: target, overlap_chars: overlap, chunks };
  await fs.writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n', { encoding: 'utf8', flag: 'wx' });
  console.log(JSON.stringify({ manifest: manifestPath, chunks: chunks.length, characters }));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
