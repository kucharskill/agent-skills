---
name: meeting-study-notes
description: "Create accessible, detailed educational notes from lecture, class, seminar, or meeting transcripts. Read sources in stages, preserve explanations and examples, synthesize the material, and obtain an independent review. Use for student and participant study notes rather than brief summaries or action minutes."
metadata:
  title: "Meeting Study Notes"
  doc_type: instruction
  status: experimental
---

# Meeting Study Notes

Produce a standalone, accessible text that helps readers understand and revisit the material. Let the source determine coverage rather than a preset length. Keep the core independent of any discipline.

## Reader-facing result

Read the [note standard](references/note-standard.md) before writing. Preserve three layers: topic and context (or meaningful chronology), developed explanations, and key takeaways. Adapt sections to the material; omit empty headings and invented exercises, definitions, or conclusions. If the meeting contains instructor requirements or decisions about homework, assessment, tests, exams, or deadlines, place a distinct section after the short meeting-details line below the title, before the substantive body. Follow the [note standard](references/note-standard.md) for evidence and uncertainty.

Write the notes in the consuming project's language, including headings and review questions. An explicit user language instruction takes precedence; otherwise follow project documentation and existing learner-facing materials. Do not infer the output language from this skill's English instructions or automatically from the transcript. If project conventions are ambiguous, ask before drafting. Preserve original-language terms when educationally necessary.

Do not include visible timestamps, raw transcript speaker labels, control reports, or accounts of agent work. Write like a student's study note, without self-presentation, AI references, or narration about processing or reviewing a source. Use the short title and meeting-details line defined in the note standard; start the substantive body with a concept or problem, not an appraisal of the lecture. Avoid repeatedly saying "the instructor says", while preserving attribution of opinions, disputed positions, and assessment requirements. In generated substantive prose, use neither U+2014 nor U+2013: use a plain hyphen or recast the sentence. Keep all processing doubts, transcription problems, confidence labels, verification requests, and reviewer comments out of rendered notes, including headings, captions, and alt text. Record them only in valid HTML comments or separate review files. Do not present an unverified interpretation as a fact: resolve it, retain only supported wording, or omit the unsupported passage and record the omission internally. If that would materially distort or incompletely state the topic or an important requirement, withhold the final note and explain the limitation outside the material. Preserve source-supported conditions and actual open questions from the meeting in natural prose; these are content, not processing annotations. Put source references and extraction IDs in adjacent HTML comments, for example `<!-- evidence: C002:I04,I08; source: chunk-002.md -->`.

Do not change the transcript. Resolve the output directory and whether it is shared by multiple notes or dedicated to this note from the consuming project or an explicit user instruction; ask if no destination can be established. Follow project naming conventions; otherwise name a single-transcript note `notatka_<transcript-stem>.md` (for example, `session.md` becomes `notatka_session.md`). Do not invent a single-source filename for a multi-source note. Store working material in a separate directory under the consuming project's `.tmp/`. Follow project conventions for provenance in YAML or hidden comments.

## 1. Segment and cover the entire source

Do not start by loading the whole long transcript into the main context. Inspect metadata, size, and a short opening to identify source language and meeting type. Mixed meetings may need different treatment in different parts.

Use `scripts/segment_transcript.js` to generate a manifest and ordered chunks. Both helpers run directly with Node.js built-ins, without npm installation, regardless of the consuming project's `package.json` module type. The default 9000 characters is a starting point, not a quality threshold. The script prefers paragraph boundaries and splits oversized paragraphs into sentences or smaller ranges. It saves disjoint core ranges and short preceding context. Do not then print every chunk at once.

```text
node "/path/to/meeting-study-notes/scripts/segment_transcript.js" "transcript.md" --out "/project/.tmp/study-note/segments"
```

Read the [extraction contract](references/extraction.md). Delegate sequential chunk reading and content ledgers to a subagent. For long meetings, disjoint chunk groups may be assigned to separate subagents. Provide boundary context without counting it as new content. If delegation is unavailable, follow the same staged workflow and disclose the lack of independent review in the user report, outside the notes.

Every chunk needs a completed ledger covering retained content, dependencies, uncertainty, and justified exclusions. Extract detail rather than another brief summary. Link later clarifications to earlier statements and preserve the final resolution. Do not turn a student's tentative answer into the instructor's claim.

After extraction, run:

```text
node "/path/to/meeting-study-notes/scripts/check_extraction.js" "manifest.json" "extractions"
```

The checker verifies a ledger for every range, identifiers, and verbatim quotes in the corresponding core. It cannot establish semantic completeness; a fresh reviewer must assess that.

## Decide whether a note is useful

After all source chunks have been covered, assess whether the material supports a useful note. Do not produce a note merely because a transcript exists. Greetings, technical setup, unrelated small talk, or repetition with no useful explanation, exercise, distinction, or actionable information may justify skipping. Do not decide from the opening or a sparse sample, and do not impose a minimum duration or word count. Short material can still be valuable. Assignments, assessment requirements, exam information, and deadlines can justify a brief note even without teaching content.

If nothing worth retaining remains, have a fresh subagent verify the skip decision against the source chunks and ledgers, checking especially for overlooked substantive content and requirements. Use the [review contract](references/review.md) in skip-review mode. Once confirmed, create no final Markdown file, placeholder, or image directory; keep only a short reason and coverage record in project `.tmp/` and tell the user the note was skipped and why. Do not delete or overwrite an existing note. Unreadable, incomplete, or unprocessed source is a processing limitation, not evidence that the material lacks value; report that limitation instead of declaring the note unnecessary. If delegation is unavailable, disclose the lack of independent confirmation.

## 2. Resolve uncertainty separately

Isolate names, numbers, and terms whose transcription could change meaning. Delegate targeted verification to another subagent when needed. Supply relevant excerpts and questions, not the entire lecture.

First consult neighboring statements, slides, and supplied materials. Search externally only for a specific unresolved issue and prefer primary sources. External verification may establish term recognition or assess a doubt; it must not expand the note with definitions, explanations, examples, or substantive corrections from general knowledge or the internet. Do not silently replace the instructor's view with a view found online. Require evidence and confidence, not just proposed wording. Without confirmation, keep the doubt in HTML comments or the review report, not visible caveats about the transcript or its processing. Use only wording supported by the evidence, without inventing the missing interpretation. Withhold the final note if an unresolved issue prevents a faithful standalone treatment.

## 3. Synthesize the note

The writer reads ledgers rather than full transcript dumps. Read content, attribution, and dependencies first; retrieve evidence quotes for specific issues rather than loading all quotations together. Organize around questions and conceptual relationships, returning to particular source passages when coherence or precision requires it. Do not synthesize only previous summaries.

- Lecture: preserve explanations, distinctions, conditions, exceptions, and examples.
- Exercise: preserve the task, relevant proposals, wrong paths, corrections, and reasoning toward a solution. Do not invent an answer when none was established.
- Discussion: distinguish positions, agreement, and disagreement. Instructor silence does not confirm an answer.
- Mixed meeting: adapt treatment to each part.

Do not drop an important term or distinction merely because the instructor treated it briefly or simplistically. First check neighboring context and available slides. Retain only the scope supported by speech or supplied visual material, without supplying a textbook definition, extra explanation, example, or substantive correction from your own knowledge or the internet. Assess the name separately from its explanation: keep a source-supported name as a short mention even when its definition or an associated claim must be removed as uncertain. Do not supply a definition merely to retain the name. If the name itself is unclear, use the targeted recognition process in section 2; do not guess it from memory or conceal an unresolved important name behind a vague paraphrase in an otherwise complete-looking note. Apply the existing internal uncertainty and final-delivery rules instead. Brief supported treatment is sufficient; incidental mentions may still be omitted, and not every slide label needs development. Do not repeat an uncertain definition as an established fact; resolve it, narrow the supported wording, or withhold final delivery when an important doubt remains unresolved.

Remove repetition without losing new qualifications or examples. Reordering may improve learning but must preserve question-answer relationships. The ending should support revision rather than replace the developed explanation with another summary. Do not claim exam relevance without source support.

## 4. Optional screenshot evidence

After drafting the text, if the source transcript YAML points to an existing screenshot folder, delegate selective visual inspection to a subagent using the [screenshot contract](references/screenshots.md). Use `screenshots_dir` or an explicitly documented project equivalent. Retain 0 to 10 representative images per note, only when they provide evidence of displayed material or educational value. Missing or unhelpful screenshots are a normal reason to include none. Never open a recording or extract new frames in this stage.

## 5. Independent review and revision

Before declaring the note ready, assign a fresh subagent the [review task](references/review.md). Neither the extractor nor the writer may be the only reviewer. Provide source chunks, manifest, ledgers, draft, and any selected images with their visual-selection record, without an expected verdict or your own suspected-error list.

The reviewer checks coverage, fidelity, attribution, clarity, and educational usefulness. Findings need evidence, severity, and a proposed correction. Apply corrections or justify rejecting a finding. Have changed passages rechecked without creating an endless cosmetic revision loop. An unresolved substantive issue means the note remains a draft; tell the user briefly. For an important assessment condition that remains unreadable or uncertain after checking context and supplied materials, name the specific unresolved threshold, scope, deadline, or eligibility condition in the handoff outside the note and state the resulting completeness limit. Known requirements do not make that gap immaterial. An HTML comment or internal report alone is insufficient, and agreement not to guess does not resolve the condition or justify unconditional readiness.

The note is ready when every core range has a ledger and inclusion decision, important examples and qualifications survived synthesis, and no unresolved finding affects meaning. Keep the review report in working files rather than inserting it into the student-facing note.
