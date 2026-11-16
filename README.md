# Agent Skills

Reusable, discipline-independent skills for agents that support SKILL.md instructions.

## Available skills

| Skill | Purpose | Status |
| --- | --- | --- |
| [Meeting Study Notes](meeting-study-notes/SKILL.md) | Detailed educational notes from lectures, exercises, seminars, and discussions, with staged reading and independent review | Experimental |

## Installation

Copy the entire selected skill directory into your agent's supported skills location. For Codex, use the configured skills directory, commonly `~/.codex/skills/`. Keep references and scripts alongside SKILL.md. Other agents can use the instructions if they support this layout; delegation and discovery depend on the host.

The repository and skill instructions are maintained in English. Generated notes follow the consuming project's language unless the user explicitly requests another language. Project-specific domain rules belong in that project.

## Meeting Study Notes

Provide a local UTF-8 Markdown or text transcript and an output destination. For example:

> Use $meeting-study-notes on transcripts/session.md. Save the notes to notes/session.md and follow this project's language conventions.

The workflow segments the transcript, extracts detailed content one chunk at a time, resolves material ambiguities, synthesizes explanations and examples, and obtains a fresh independent review. It adapts to lectures, student exercises, discussions, and mixed meetings.

The reader-facing result contains topic and context, developed explanations, and useful takeaways or recall questions. Inapplicable sections are omitted. Visible notes contain no timestamps or processing narrative; evidence links may remain in HTML comments. Substantive uncertainty remains visible.

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

## Scope and limitations

This is an experimental workflow, not a guarantee that every detail is preserved. Transcript errors may require verification against supplied materials or primary sources. Review of a transcript does not establish accuracy against the original recording.

## License

Licensed under the [MIT License](LICENSE).
