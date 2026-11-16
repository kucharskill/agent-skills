---
name: meeting-video-frames
description: Extract sparse, visually deduplicated screenshots from local meeting recordings with system FFmpeg. Save identifiable images and a source/time manifest in the OS temporary directory, then report their location. Use when asked to prepare video frames for later reference, without interpreting the recording or selecting educational illustrations.
---

# Meeting Video Frames

Prepare screenshots only when the user requests extraction. Do not inspect images, summarize the recording, transcribe audio, perform OCR, or decide which slides are useful unless separately asked. This skill prepares artifacts for a possible later comparison with notes or transcripts.

## Execute

Use the bundled script rather than writing a project-specific extraction script. Resolve its location from this installed skill directory, never from a hardcoded development checkout.

```text
node "/installed/meeting-video-frames/scripts/extract_frames.js" "/project/recordings/meeting.mp4"
```

Requires Node.js 18+ and system `ffmpeg` and `ffprobe` on PATH, without npm packages, Python, downloads, or paid services. Use local files; do not alter the recording. Process multiple requested files sequentially.

The default sampling interval is `min(60, max(1, duration_seconds / 20))`. Recordings of at least 20 minutes are sampled once per minute; shorter recordings receive approximately 20 candidates, with a minimum one-second interval. Sampling starts at zero and never adds an extra end frame closer than the interval. Sampling can miss short-lived slides between candidates.

One FFmpeg extraction process decodes the recording, samples frames with the select filter, removes similar consecutive samples with mpdecimate using its default thresholds, and writes full-resolution JPEGs. Node handles paths, process execution, and metadata only; it does not compare images or rename screenshots. A return to an earlier slide after a different one is retained. This is a visual heuristic: small text edits may be missed and moving overlays may produce extra frames. Do not claim semantic slide detection or completeness. This simpler workflow decodes the whole video; sparse output does not imply sparse decoding.

## Find the results

Read the script's final JSON output. It gives the absolute output directory, manifest, log, retained/skipped counts, interval, and cache status. Do not guess the current user's TEMP path or load the images to confirm their existence.

Output is under `os.tmpdir()/meeting-video-frames/<parent>--<video-name>--<source-path-id>/<source-version-and-settings-id>/`. On Windows this uses the system temporary directory, as requested, rather than the project's `.tmp/`. The manifest records the full source path, size, modification time, duration, settings, every retained filename and source-relative time, plus the times of samples skipped by mpdecimate. FFmpeg itself names images using -frame_pts 1 with -enc_time_base 1:1, for example `frame-000720s.jpg` for approximately 720 seconds. Filenames round to whole seconds; the manifest's source_seconds records the finer timestamp reported by FFmpeg. Time is normalized to the first decoded video frame. These are not meeting wall-clock times; edited recordings use the edited video's timeline. Match against a transcript made from the same recording version, accounting for any audio/video start offset when relevant.

A completed run with the same source identity and settings is reused if all listed images still exist and are nonempty. A changed path, size, modification time, or setting gets a separate identifiable directory. This identity is metadata-based, not a full-video content hash. TEMP can be cleaned by Windows; a later invocation recreates missing results. Do not treat TEMP as permanent storage or copy images into notes unless asked.

Errors return a nonzero exit code and report the output directory. Read `manifest.json` and `ffmpeg.log` for diagnostics; a failed run is not a completed extraction. An active or stale `.lock` prevents concurrent writes. Only remove a stale lock after verifying that no extraction is active. Never delete another run or modify the source to resolve a failure.

## Reply

Respond in the user's or consuming project's language with the output-folder link, manifest link, saved count, and sampling interval. Mention reuse or a failure when relevant. Do not add an interpretation of the recording. Follow-up analysis is a separate task.
