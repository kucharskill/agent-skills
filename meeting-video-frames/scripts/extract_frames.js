#!/usr/bin/env node
// Standalone Node.js helper, compatible with CommonJS and ES module projects.
(async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const os = await import('node:os');
  const { createHash } = await import('node:crypto');
  const { spawnSync } = await import('node:child_process');
  const argv = process.argv.slice(2);
  const help = 'Usage: node extract_frames.js VIDEO [--threshold 0.015]\nRequires ffmpeg and ffprobe on PATH. Outputs JSON paths; images go to the OS temporary directory.';
  if (argv.includes('--help') || argv.includes('-h')) { console.log(help); return; }
  let input, threshold = 0.015, thresholdSeen = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--threshold' && !thresholdSeen && i + 1 < argv.length) {
      thresholdSeen = true; threshold = Number(argv[++i]);
    } else if (!argv[i].startsWith('-') && !input) input = argv[i];
    else throw new Error('Unexpected or repeated argument: ' + argv[i]);
  }
  if (!input || !Number.isFinite(threshold) || threshold < 0 || threshold > 0.1) throw new Error(help);
  const source = await fs.realpath(path.resolve(input));
  const stat = await fs.stat(source);
  if (!stat.isFile()) throw new Error('Input must be a local file');
  const hash = value => createHash('sha256').update(value).digest('hex').slice(0, 16);
  const slug = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^[.-]+|[.-]+$/g, '').slice(0, 60) || 'video';
  const identity = { path: source, bytes: stat.size, mtime_ms: stat.mtimeMs };
  const settings = { version: 1, threshold, sample_target: 20, minimum_interval_seconds: 1, maximum_interval_seconds: 60, fingerprint: 'rgb96x54-mean-absolute-difference', image: 'jpeg-original-resolution' };
  const sourceKey = process.platform === 'win32' ? source.toLowerCase() : source;
  const directory = path.join(os.tmpdir(), 'meeting-video-frames', slug(path.basename(path.dirname(source))) + '--' + slug(path.parse(source).name) + '--' + hash(sourceKey), hash(JSON.stringify({ identity, settings })));
  const manifestPath = path.join(directory, 'manifest.json');
  const logPath = path.join(directory, 'ffmpeg.log');
  await fs.mkdir(directory, { recursive: true });
  const lockPath = path.join(directory, '.lock');
  let lock;
  try { lock = await fs.open(lockPath, 'wx'); }
  catch (error) { if (error.code === 'EEXIST') throw new Error('Extraction is locked: ' + lockPath + '. Verify no process is active before removing a stale lock.'); throw error; }
  let manifest;
  const save = async () => {
    const staging = path.join(directory, 'manifest.pending.json');
    await fs.writeFile(staging, JSON.stringify(manifest, null, 2) + '\n');
    await fs.rename(staging, manifestPath);
  };
  const run = async (command, args, maxBuffer = 4 * 1024 * 1024) => {
    const result = spawnSync(command, args, { encoding: null, windowsHide: true, maxBuffer, timeout: 180000, stdio: ['ignore', 'pipe', 'pipe'] });
    await fs.appendFile(logPath, JSON.stringify({ time: new Date().toISOString(), command, args, status: result.status, error: result.error?.message }) + '\n' + (result.stderr?.toString('utf8') || '') + '\n');
    if (result.error || result.status !== 0) throw new Error(command + ' failed; see ' + logPath + (result.error ? ': ' + result.error.message : ''));
    return result.stdout;
  };
  const report = cached => console.log(JSON.stringify({ directory, manifest: manifestPath, log: logPath, saved: manifest.frames.length, skipped_similar: manifest.skipped.length, interval_seconds: manifest.interval_seconds, cached }));
  try {
    await lock.writeFile(JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
    let previous;
    try { previous = JSON.parse(await fs.readFile(manifestPath, 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw new Error('Unreadable existing manifest: ' + manifestPath); }
    if (previous?.status === 'complete' && JSON.stringify(previous.source) === JSON.stringify(identity) && JSON.stringify(previous.settings) === JSON.stringify(settings)) {
      let intact = true;
      for (const frame of previous.frames) {
        if (typeof frame.file !== 'string' || !/^frame-\d+-\d{2}-\d{2}\.\d{3}\.jpg$/.test(frame.file)) throw new Error('Invalid frame name in cached manifest');
        try { if (!(await fs.stat(path.join(directory, frame.file))).size) intact = false; }
        catch (error) { if (error.code !== 'ENOENT') throw error; intact = false; }
      }
      if (intact && previous.frames.length) { manifest = previous; report(true); return; }
    }
    manifest = { status: 'running', source: identity, settings, created_at: new Date().toISOString(), frames: [], skipped: [] };
    await save();
    const probe = JSON.parse((await run('ffprobe', ['-v', 'error', '-show_format', '-show_streams', '-of', 'json', source])).toString('utf8'));
    const video = probe.streams?.find(stream => stream.codec_type === 'video' && !stream.disposition?.attached_pic);
    if (!video) throw new Error('No video stream found');
    const streamDuration = Number(video.duration);
    const duration = Number.isFinite(streamDuration) && streamDuration > 0 ? streamDuration : Number(probe.format?.duration);
    if (!Number.isFinite(duration) || duration <= 0) throw new Error('Cannot determine a finite positive video duration');
    const interval = Math.min(60, Math.max(1, duration / 20));
    Object.assign(manifest, { duration_seconds: duration, interval_seconds: interval, video_stream: video.index, note: 'Times are requested seek positions relative to the video start, not original meeting wall-clock times. Similarity is visual and heuristic, not semantic.' });
    await save();
    const retained = [];
    const base = ['-hide_banner', '-loglevel', 'warning', '-nostdin'];
    const stamp = seconds => {
      const milliseconds = Math.round(seconds * 1000);
      return String(Math.floor(milliseconds / 3600000)).padStart(2, '0') + '-' + String(Math.floor(milliseconds / 60000) % 60).padStart(2, '0') + '-' + String(Math.floor(milliseconds / 1000) % 60).padStart(2, '0') + '.' + String(milliseconds % 1000).padStart(3, '0');
    };
    for (let index = 0; index * interval < duration; index++) {
      const seconds = index * interval;
      const seek = [...base, '-ss', seconds.toFixed(6), '-i', source, '-map', '0:' + video.index, '-an', '-sn', '-dn', '-frames:v', '1'];
      const fingerprint = await run('ffmpeg', [...seek, '-vf', 'scale=96:54:flags=area', '-pix_fmt', 'rgb24', '-f', 'rawvideo', 'pipe:1']);
      if (fingerprint.length !== 96 * 54 * 3) throw new Error('Could not decode a complete frame at ' + seconds + ' seconds');
      let nearest, distance = Infinity;
      for (const prior of retained) {
        let sum = 0;
        for (let p = 0; p < fingerprint.length; p++) sum += Math.abs(fingerprint[p] - prior.fingerprint[p]);
        const difference = sum / (fingerprint.length * 255);
        if (difference < distance) { distance = difference; nearest = prior.file; }
      }
      if (nearest && distance <= threshold) {
        manifest.skipped.push({ requested_seconds: seconds, similar_to: nearest, difference: distance });
      } else {
        const file = 'frame-' + stamp(seconds) + '.jpg';
        const pending = path.join(directory, 'pending.jpg');
        await run('ffmpeg', [...seek, '-q:v', '2', '-update', '1', '-y', pending]);
        if (!(await fs.stat(pending)).size) throw new Error('Empty image at ' + seconds);
        await fs.rename(pending, path.join(directory, file));
        manifest.frames.push({ file, requested_seconds: seconds, nearest_difference: nearest ? distance : null });
        retained.push({ file, fingerprint });
      }
      await save();
    }
    const after = await fs.stat(source);
    if (after.size !== stat.size || after.mtimeMs !== stat.mtimeMs) throw new Error('Source changed during extraction; result is incomplete');
    manifest.status = 'complete';
    manifest.completed_at = new Date().toISOString();
    await save();
    report(false);
  } catch (error) {
    if (manifest) { manifest.status = 'failed'; manifest.error = error.message; await save(); }
    console.error('Output directory: ' + directory);
    throw error;
  } finally {
    await lock.close();
    await fs.unlink(lockPath);
  }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
