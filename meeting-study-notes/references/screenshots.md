---
title: "Optional Screenshot Evidence"
doc_type: instruction
status: experimental
---

# Screenshot selection subagent task

Run after the text draft, before independent review. Receive the draft, original transcript path and YAML, relevant ledger items, selected output path, and the project's shared or dedicated note-directory convention. Inspect screenshots in your own context and return a compact selection record, not a full image dump to the writer.

## Locate and compare

- Read `screenshots_dir` from transcript YAML, or the equivalent key explicitly defined by the consuming project. Example: `screenshots_dir: "../screenshots/session"`. Resolve relative paths against the original transcript directory, not a chunk directory or the current working directory. Do not modify the transcript to add a field.
- An absent key, missing folder, empty folder, unsupported images, or lack of useful content means zero illustrations. Do not search elsewhere for substitutes, open a video, invoke frame extraction, or regenerate missing screenshots.
- List filenames and consult relevant manifest entries when available. Use source-relative seconds in names such as `frame-000720s.jpg` to shortlist images near relevant passages. Prefer manifest precision when available. Compare compatible recording timelines only; edits and start offsets can invalidate a match. Without compatible timestamps, assess content directly and do not claim simultaneous display from timing alone.
- Inspect candidates visually in small batches. Target references to slides, charts, diagrams, worked exercises, or exam instructions. Do not load all screenshots into the writer's context. Time proximity is a lead, not proof that an image supports a statement.
- Retain 0 to 10 images for the entire note, including multi-source notes. The limit is a ceiling, not a target. Choose complementary, representative evidence or teaching material. Avoid duplicate slides, decoration, and dense galleries. Do not infer final exam requirements from student speculation or unrelated screens.

## Prepare durable images

Use the final note path and the consuming project's directory convention:

| Note directory | Image directory beside the note |
| --- | --- |
| Shared by multiple notes | `<note-stem>_img/` |
| Dedicated to this note | `img/` |

For `notatka_session.md` in a shared directory, use `notatka_session_img/`. Ask if the directory convention is unknown instead of guessing from the current file count. Create the image directory only when needed. Use short descriptive filenames, preserve the actual format extension, and do not overwrite unrelated assets.

Copy the selected original, or save a cropped copy when removing meeting controls, borders, or empty space improves clarity. Never modify the source screenshot. Cropping and downscaling are optional; if tools are unavailable or cropping does not help, copy the original. Do not add npm or Python dependencies.

When FFmpeg is available, give it the selected PNG/JPEG or other supported still-image file as input, never a recording. Inspect the image first and choose coordinates within its dimensions. For example, after confirming these coordinates for that image:

```sh
ffmpeg -nostdin -n -i "/screenshots/frame-000720s.jpg" -vf "crop=1200:800:100:100" -frames:v 1 -update 1 "/notes/notatka_session_img/process-diagram.png"
```

These numbers are illustrative, not a default crop. Optional scaling must preserve aspect ratio, avoid upscaling, and keep text readable at the intended display size. Preserve titles, legends, axes, units, qualifications, and all data needed to solve an exercise. Do not use generative editing or alter displayed facts.

Open the final saved image and verify readability and completeness. If a crop loses important context, use a wider crop or the original. If visual tools are unavailable, omit uninspected images. Record skipped optional work honestly rather than claiming inspection.

## Integrate and return

Place retained images near supported explanations using relative Markdown paths, meaningful alt text, and optional factual captions in the project language. Never link final notes into an OS temporary directory. Keep the text independently understandable. A screenshot may supplement a transcript with clearly displayed material, but do not attribute unspoken text to the instructor. Flag substantive conflicts or uncertainty rather than silently resolving them.

Store a compact selection record under the note's project `.tmp/`: original screenshot path, source seconds if known, relevant transcript range or ledger ID, rationale, final relative asset path, and crop/scale or original-copy decision. Timing and provenance may also be adjacent HTML comments, not visible timestamps. Return the record and proposed insertion points to the writer. Supply selected originals and final copies to the independent reviewer; keep working analysis out of the note.
