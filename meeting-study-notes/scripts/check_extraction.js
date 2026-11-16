#!/usr/bin/env node
// Standalone CLI; old version-1 manifests use the same Unicode offsets.
(async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const { createHash } = await import('node:crypto');
  const { TextDecoder } = await import('node:util');
  const argv = process.argv.slice(2);
  const help = 'Usage: node check_extraction.js MANIFEST EXTRACTION_DIRECTORY';
  if (argv.includes('--help') || argv.includes('-h')) { console.log(help); return; }
  if (argv.length !== 2 || argv.some(value => value.startsWith('-'))) throw new Error(help);
  const decode = bytes => new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes).replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
  const readJson = async file => JSON.parse(decode(await fs.readFile(file)));
  const manifestPath = path.resolve(argv[0]);
  const manifest = await readJson(manifestPath);
  if (manifest.version !== 1 || !Array.isArray(manifest.chunks) || !manifest.chunks.length
      || (manifest.offset_units && manifest.offset_units !== 'unicode-code-points')) throw new Error('Unsupported or empty manifest');
  let sourcePath = manifest.normalized_source;
  // A relocated working folder can still be checked without editing its manifest.
  try { if (!sourcePath) throw Object.assign(new Error('Missing path'), { code: 'ENOENT' }); await fs.access(sourcePath); }
  catch (error) { if (error.code !== 'ENOENT') throw error; sourcePath = path.join(path.dirname(manifestPath), 'source.txt'); }
  const source = decode(await fs.readFile(sourcePath));
  const points = Array.from(source);
  const errors = [], identifiers = new Set(), links = [];
  const compact = text => String(text || '').replace(/\s+/gu, ' ').trim();
  if (createHash('sha256').update(source, 'utf8').digest('hex') !== manifest.sha256) errors.push('Normalized source changed after segmentation');
  if (manifest.characters !== points.length) errors.push('Manifest character count does not match source');
  let previousEnd = 0, itemCount = 0;
  const chunkIds = new Set();
  for (const chunk of manifest.chunks) {
    const cid = chunk.id;
    if (typeof cid !== 'string' || chunkIds.has(cid)) errors.push('Duplicate or invalid chunk id');
    chunkIds.add(cid);
    const validRange = Number.isSafeInteger(chunk.core_start) && Number.isSafeInteger(chunk.core_end)
      && chunk.core_start === previousEnd && chunk.core_end > chunk.core_start && chunk.core_end <= points.length;
    if (!validRange) errors.push(`${cid}: gap, overlap or invalid range in manifest`);
    previousEnd = chunk.core_end;
    // Only generated C001-style ids may be used as file names.
    if (!/^C\d{3,}$/.test(cid)) { errors.push(`${cid}: invalid chunk id`); continue; }
    const filename = path.join(path.resolve(argv[1]), `extract-${cid}.json`);
    let record;
    try { record = await readJson(filename); }
    catch (error) { errors.push(`${cid}: ${error.code === 'ENOENT' ? 'missing extraction' : 'unreadable extraction: ' + error.message}`); continue; }
    if (!record || record.chunk_id !== cid || record.core_read !== true) errors.push(`${cid}: wrong id or unread core`);
    const items = record && record.items;
    if (!Array.isArray(items)) { errors.push(`${cid}: items must be an array`); continue; }
    if (!items.length && !(Array.isArray(record.excluded) && record.excluded.length)) errors.push(`${cid}: neither items nor justified exclusions`);
    const core = compact(validRange ? points.slice(chunk.core_start, chunk.core_end).join('') : '');
    for (const item of items) {
      if (!item || typeof item !== 'object') { errors.push(`${cid}: invalid item`); continue; }
      const iid = item.id;
      if (typeof iid !== 'string' || !iid.startsWith(cid + ':') || identifiers.has(iid)) errors.push(`${cid}: duplicate or invalid item id ${iid}`);
      identifiers.add(iid);
      const quote = compact(item.evidence && item.evidence.quote);
      if (!quote || !core.includes(quote)) errors.push(`${iid}: quote absent from core`);
      if (!compact(item.content) || !compact(item.attribution)) errors.push(`${iid}: missing content or attribution`);
      const dependencies = item.depends_on === undefined ? [] : item.depends_on;
      if (!Array.isArray(dependencies)) errors.push(`${iid}: depends_on must be an array`);
      else for (const other of dependencies) links.push([iid, other]);
    }
    itemCount += items.length;
  }
  if (previousEnd !== points.length) errors.push('Manifest does not reach source end');
  for (const [iid, other] of links) if (!identifiers.has(other)) errors.push(`${iid}: unknown dependency ${other}`);
  console.log(JSON.stringify({ chunks: manifest.chunks.length, items: itemCount, errors }, null, 2));
  process.exitCode = errors.length ? 1 : 0;
})().catch(error => { console.error(error.message); process.exitCode = 1; });
