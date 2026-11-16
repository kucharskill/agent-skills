#!/usr/bin/env node
// Standalone Node.js helper, compatible with CommonJS and ES module projects.
(async () => {
  const fs = await import('node:fs/promises');
  const path = await import('node:path');
  const os = await import('node:os');
  const { createHash } = await import('node:crypto');
  const { spawn } = await import('node:child_process');
  const argv = process.argv.slice(2);
  const help = 'Usage: node extract_frames.js VIDEO\nRequires ffmpeg and ffprobe on PATH. Outputs JSON paths; images go to the OS temporary directory.';
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) { console.log(help); return; }
  if (argv.length !== 1 || argv[0].startsWith('-')) throw new Error(help);
  const source = await fs.realpath(path.resolve(argv[0]));
  const stat = await fs.stat(source);
  if (!stat.isFile()) throw new Error('Input must be a local file');
  const hash = value => createHash('sha256').update(value).digest('hex').slice(0, 16);
  const slug = value => value.normalize('NFKD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^[.-]+|[.-]+$/g, '').slice(0, 60) || 'video';
  const identity = { path: source, bytes: stat.size, mtime_ms: stat.mtimeMs };
  const settings = { version: 2, sample_target: 20, minimum_interval_seconds: 1, maximum_interval_seconds: 60, deduplication: 'ffmpeg-mpdecimate-defaults', image: 'jpeg-original-resolution', filename_time_base: 'seconds' };
  const sourceKey = process.platform === 'win32' ? source.toLowerCase() : source;
  const directory = path.join(os.tmpdir(), 'meeting-video-frames', slug(path.basename(path.dirname(source))) + '--' + slug(path.parse(source).name) + '--' + hash(sourceKey), hash(JSON.stringify({ identity, settings })));
  const manifestPath = path.join(directory, 'manifest.json');
  const logPath = path.join(directory, 'ffmpeg.log');
  const framePattern = /^frame-(\d+)s\.jpg$/;
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
  // Stream diagnostics to disk; a full recording may take longer than minutes.
  const run = async (command, args) => {
    await fs.appendFile(logPath, JSON.stringify({ time: new Date().toISOString(), command, args }) + '\n');
    const log = await fs.open(logPath, 'a');
    try {
      return await new Promise((resolve, reject) => {
        const chunks = [];
        let size = 0, error;
        const child = spawn(command, args, { windowsHide: true, stdio: ['ignore', 'pipe', log.fd] });
        child.on('error', failure => { error = failure; });
        child.stdout.on('data', chunk => {
          size += chunk.length;
          if (size > 4 * 1024 * 1024) { error = new Error('Unexpectedly large command output'); child.kill(); }
          else chunks.push(chunk);
        });
        child.on('close', code => {
          if (error || code !== 0) reject(new Error(command + ' failed; see ' + logPath + (error ? ': ' + error.message : '')));
          else resolve(Buffer.concat(chunks));
        });
      });
    } finally { await log.close(); }
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
        if (typeof frame.file !== 'string' || !framePattern.test(frame.file)) throw new Error('Invalid frame name in cached manifest');
        try { if (!(await fs.stat(path.join(directory, frame.file))).size) intact = false; }
        catch (error) { if (error.code !== 'ENOENT') throw error; intact = false; }
      }
      if (intact && previous.frames.length) { manifest = previous; report(true); return; }
    }
    await fs.writeFile(logPath, '');
    manifest = { status: 'running', source: identity, settings, created_at: new Date().toISOString(), frames: [], skipped: [] };
    await save();
    const probe = JSON.parse((await run('ffprobe', ['-v', 'error', '-show_format', '-show_streams', '-of', 'json', source])).toString('utf8'));
    const video = probe.streams?.find(stream => stream.codec_type === 'video' && !stream.disposition?.attached_pic);
    if (!video) throw new Error('No video stream found');
    const streamDuration = Number(video.duration);
    const duration = Number.isFinite(streamDuration) && streamDuration > 0 ? streamDuration : Number(probe.format?.duration);
    if (!Number.isFinite(duration) || duration <= 0) throw new Error('Cannot determine a finite positive video duration');
    const interval = Math.min(60, Math.max(1, duration / 20));
    Object.assign(manifest, { duration_seconds: duration, interval_seconds: interval, video_stream: video.index, note: 'Source seconds are relative to the first decoded video frame. Filenames round that time to whole seconds; source_seconds preserves the finer timestamp reported by FFmpeg. These are not meeting wall-clock times. Deduplication compares with the last retained sample, not all earlier slides.' });
    await save();
    // Replace only this run's generated JPEGs when repairing an incomplete cache.
    for (const file of await fs.readdir(directory)) if (framePattern.test(file)) await fs.unlink(path.join(directory, file));
    const filter = "setpts=PTS-STARTPTS,select='isnan(prev_selected_t)+gte(t-prev_selected_t," + interval.toFixed(9) + ")',showinfo@sample,mpdecimate,showinfo@kept";
    await run('ffmpeg', ['-hide_banner', '-loglevel', 'info', '-nostats', '-nostdin', '-i', source, '-map', '0:' + video.index, '-an', '-sn', '-dn', '-vf', filter, '-fps_mode', 'vfr', '-enc_time_base', '1:1', '-frame_pts', '1', '-q:v', '2', '-atomic_writing', '1', '-y', path.join(directory, 'frame-%06ds.jpg')]);
    const diagnostics = await fs.readFile(logPath, 'utf8');
    const times = label => Array.from(diagnostics.matchAll(new RegExp('showinfo@' + label + '[^\\r\\n]*?\\bn:\\s*\\d+[^\\r\\n]*?\\bpts_time:([^\\s]+)', 'g')), match => Number(match[1]));
    const samples = times('sample'), kept = times('kept');
    if (!samples.length || !kept.length || [...samples, ...kept].some(time => !Number.isFinite(time) || time < 0)) throw new Error('Missing or invalid frame timestamps in FFmpeg diagnostics');
    // showinfo prints pts_time with six significant digits, so its rounding
    // error grows with the timestamp even though FFmpeg samples at full precision.
    const printedTimeError = seconds => seconds > 0 ? 0.5 * 10 ** (Math.floor(Math.log10(seconds)) - 5) : 0;
    for (let i = 1; i < samples.length; i++) {
      const tolerance = 0.001 + printedTimeError(samples[i]) + printedTimeError(samples[i - 1]);
      if (samples[i] - samples[i - 1] < interval - tolerance) throw new Error('Sampling interval invariant failed');
    }
    // FFmpeg names files from full-precision PTS. Rounded showinfo text can
    // cross a half-second boundary, so never reconstruct filenames from it.
    const files = (await fs.readdir(directory)).filter(file => framePattern.test(file))
      .sort((a, b) => Number(framePattern.exec(a)[1]) - Number(framePattern.exec(b)[1]));
    if (files.length !== kept.length) throw new Error('Frame files do not match retained timestamps');
    manifest.frames = kept.map((seconds, index) => {
      const file = files[index], filenameSeconds = Number(framePattern.exec(file)[1]);
      if (!Number.isSafeInteger(filenameSeconds) || Math.abs(filenameSeconds - seconds) > 0.501 + printedTimeError(seconds)) {
        throw new Error('Frame filename does not match its source timestamp: ' + file);
      }
      return { file, source_seconds: seconds, filename_seconds: filenameSeconds };
    });
    const keptTimes = new Set(kept);
    manifest.skipped = samples.filter(seconds => !keptTimes.has(seconds)).map(seconds => ({ source_seconds: seconds, reason: 'mpdecimate' }));
    manifest.candidate_count = samples.length;
    for (const frame of manifest.frames) if (!(await fs.stat(path.join(directory, frame.file))).size) throw new Error('Missing or empty JPEG: ' + frame.file);
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
