# Agent Skills

Reusable, discipline-independent skills for agents that support SKILL.md instructions.

## Available skills

| Skill | Purpose | Status |
| --- | --- | --- |
| [Meeting Study Notes](meeting-study-notes/SKILL.md) | Detailed educational notes from lectures, exercises, seminars, and discussions, with staged reading and independent review | Experimental |
| [Email Handling](email-handling/SKILL.md) | Mail search, previews, drafts, organization, and explicit approval before sending | Experimental |
| [Meeting Video Frames](meeting-video-frames/SKILL.md) | Sparse, visually deduplicated screenshots from meeting recordings, saved to identifiable temporary folders without content analysis | Experimental |
| [Standardize Agent Layout](standardize-agent-layout/SKILL.md) | Set up and gradually migrate shared agent instructions and skills across coding clients | Experimental |
| [Codex Idle Restart](codex-idle-restart/SKILL.md) | Check idle eligibility and restart the Windows Codex app with saved process-tree cleanup | Experimental |

## Installation

Copy the entire selected skill directory into your agent's supported skills location. For Codex, use the configured skills directory, commonly `~/.codex/skills/`. Keep references and scripts alongside SKILL.md. Other agents can use the instructions if they support this layout; delegation and discovery depend on the host.

The repository and skill instructions are maintained in English. Generated notes follow the consuming project's language unless the user explicitly requests another language. Project-specific domain rules belong in that project.

## Meeting Study Notes

Provide a local UTF-8 Markdown or text transcript and an output destination. For example:

> Use $meeting-study-notes on transcripts/session.md. Save the notes to notes/session.md and follow this project's language conventions.

A note is not mandatory for every transcript. After complete staged reading, material with no useful educational content or actionable requirements is skipped, with independent confirmation when subagents are available. No empty note, placeholder, or image directory is created; the user receives a brief reason. Short material containing assignments, assessment instructions, or deadlines can still warrant a note. Input-processing failures are reported as limitations rather than treated as proof that the material is useless.

The workflow segments the transcript, extracts detailed content one chunk at a time, resolves material ambiguities, synthesizes explanations and examples, and obtains a fresh independent review. It adapts to lectures, student exercises, discussions, and mixed meetings.

The reader-facing result contains topic and context, developed explanations, and useful takeaways or recall questions. When present in the source, instructor requirements and decisions about assignments, assessment, exams, and deadlines appear in a distinct section below a short meeting-details line, before the substantive body. Confirmed decisions remain separate from tentative proposals and unresolved questions. Inapplicable sections are omitted. A short factual title names the topic, optionally with two or three key concepts. A natural line below it identifies the meeting and its known date. The substantive body reads like student notes and starts with a concept or problem, without repeatedly introducing statements as things the instructor said; necessary attribution is retained. Generated substantive prose uses plain hyphens rather than en or em dashes. Visible notes contain no timestamps or processing narrative; evidence links may remain in HTML comments. Transcription doubts, confidence labels, verification requests, and review remarks remain exclusively in HTML comments or separate review files. The rendered note contains only supported content and natural source-based explanations. Unresolved issues that prevent faithful treatment block final delivery rather than becoming visible processing annotations or unsupported facts.

By default, a single-transcript note is named `notatka_<transcript-stem>.md`; project conventions or an explicit destination take precedence. The output directory must come from the consuming project or user.

If transcript YAML contains `screenshots_dir` (or a documented project equivalent), a subagent can selectively inspect existing screenshots after the text draft and include 0 to 10 useful illustrations. Relative paths resolve from the transcript directory. Selection compares displayed content with relevant passages; timestamp proximity alone is insufficient. Missing or unhelpful screenshots are skipped. Only existing still images are processed, never a recording. Optional cropping or downscaling uses system FFmpeg when available; otherwise copy the original. No new dependency is required, and source screenshots remain unchanged.

In a shared notes directory, copied assets go in `<note-stem>_img/`; in a directory dedicated to one note, they go in `img/`. Markdown uses relative links to these durable copies, never links into a temporary screenshot cache.

Working manifests, extraction ledgers, and review reports stay under the consuming project's `.tmp/`. Original transcripts remain unchanged. Private transcripts and generated student notes do not belong in this repository.

### Requirements and helper commands

An agent capable of reading and writing local files and running commands is required. Subagent support enables independent extraction and review. Without it, use staged processing and disclose the review limitation outside the note.

The two standalone helper scripts use only Node.js built-in modules. No Python runtime, npm installation, package manifest, or external JavaScript dependencies are required. They work in CommonJS and ES module projects.

```sh
node meeting-study-notes/scripts/segment_transcript.js transcript.md --out .tmp/session/segments
node meeting-study-notes/scripts/check_extraction.js .tmp/session/segments/manifest.json .tmp/session/extractions
```

The agent creates extraction ledgers between these commands. Segmentation defaults to 9000 characters with preceding context and supports `--target-chars` and `--overlap-chars`. Use `--help` for exact options. The checker verifies structure and source quotations, not semantic completeness.

The skill itself calls no paid transcription service and includes no speech-to-text engine. Agent usage and optional targeted source verification depend on the host's services, access, and pricing.

## Email Handling

Use an available mail MCP integration to search, read, preview attachments, organize messages, and prepare drafts. The skill asks which integration to use for each new mailbox-check request unless the user already selected one. Different integrations may access different accounts.

Message text can be developed in chat. Sending requires a final preview and explicit approval through `functions.request_user_input_async` for that exact version. Editing the message requires renewed approval. If the approval form is unavailable, sending pauses. The optional inline editor uses the bundled Node.js helper and HTML template with the host's available visualization support; plain chat editing is the fallback. Mail and host integration availability determine which operations are supported.

The helper uses Node.js built-ins without npm dependencies. Markdown preview loads pinned markdown-it from a CDN; without it, the editor shows plain text. The skill does not include mail credentials or call a mail service itself. Email language follows the user's request; repository instructions and default editor labels are English. Private messages, attachments, and rendered drafts stay outside this repository.

Run the synthetic helper checks with `node tests/email-handling.cjs`. They generate test HTML under `.tmp/` without accessing a mailbox or sending messages.

## Meeting Video Frames

Provide a local meeting video and request screenshot extraction:

> Use $meeting-video-frames on recordings/session.mp4. Extract screenshots and report their location without analyzing the recording.

Requires Node.js 18+ and system FFmpeg and FFprobe on PATH. No npm packages, Python, transcription service, or network access are needed.

```sh
node meeting-video-frames/scripts/extract_frames.js recordings/session.mp4
```

Sampling uses approximately 20 candidates for shorter recordings, with a minimum one-second interval. Recordings lasting at least 20 minutes are sampled once per minute. One FFmpeg process decodes the recording, samples frames with select, removes similar consecutive samples with mpdecimate, and saves full-resolution JPEGs. A return to an earlier slide after a different one is retained. There are no JavaScript image comparisons, repeated extraction processes, or filename-renaming steps. The whole video is decoded; sparse output does not guarantee a faster run.

The command prints JSON containing the absolute output directory, manifest, log, counts, and cache status. Results use the OS temporary directory, including Windows TEMP, under `meeting-video-frames/<parent>--<video-name>--<path-id>/<source-version-and-settings-id>/`. The manifest associates each screenshot with the complete source path and its source-relative time. FFmpeg directly names images such as `frame-000060s.jpg` using -frame_pts 1 and a one-second encoder time base. Names round to whole seconds; source_seconds in the manifest preserves the finer timestamp reported by FFmpeg. Times start at the first decoded video frame, so transcript comparison requires the same recording version and consideration of any audio/video start offset. Completed results are reused; missing images are regenerated. A source or settings change gets a separate directory. Source identity uses path, size, and modification time rather than a full-content hash.

The skill does not view images, perform OCR, summarize recordings, or choose illustrations. Later analysis or copying images into notes requires a separate request. Visual similarity is a heuristic: small slide changes can be missed and moving overlays may produce extra images. Sparse sampling can miss slides between samples. TEMP is disposable; request permanent copies when needed. Private images, manifests, and logs do not belong in this repository.

## Verification

Run the synthetic FFmpeg integration checks from the repository:

```sh
node tests/meeting-video-frames.cjs
```

Fixtures stay under .tmp/; generated extraction artifacts use the OS temporary directory. Checks cover deduplication, second-based filenames, fractional timestamps, long-recording sampling, cache reuse and repair, input errors, and module compatibility.

## Scope and limitations

This is an experimental workflow, not a guarantee that every detail is preserved. Transcript errors may require verification against supplied materials or primary sources. Review of a transcript does not establish accuracy against the original recording.

## Codex Idle Restart

Use `$codex-idle-restart` for an authorized Windows desktop restart after checking all relevant chats for active work and at least one hour since the latest finished turn. Only the current maintenance turn is exempt. The agent owns these decisions; a standalone Windows PowerShell script performs the restart without Node or extra packages.

The script is a dry run unless `-Execute` is supplied. Its detached worker snapshots PID plus creation-time identities, restores a tray-only window and requests real Quit through Ctrl+Q, terminates remaining saved descendants, waits 20 seconds, and relaunches Codex with the local chat UUID passed through `-ThreadId`. It does not scan or kill unrelated processes by name. Actual restart attempts write JSONL logs under the system TEMP directory in `codex-idle-restart/`; dry runs and skipped checks create no logs. Logs include redacted commands, working sets, private committed bytes, post-close survivors, per-process cleanup outcomes, and saved-tree memory decreases before relaunch. These are estimates, not net physical RAM savings. App launch is recorded, but successful UI navigation is not verified.

Stop checking as soon as a definite blocker is confirmed. Full chat coverage is required only before approving a restart, not to justify skipping one.

```powershell
& ./codex-idle-restart/scripts/restart-codex.ps1 -ThreadId '<local-chat-uuid>'
& ./tests/codex-idle-restart.ps1
```

Activity checking requires Codex app tools. There is no atomic lock against new work arriving after the final check. Cleanup covers the saved process tree, not already-orphaned processes outside it. An unknown app layout, failed close, or incomplete activity evidence stops the workflow.

## License

Licensed under the [MIT License](LICENSE).
