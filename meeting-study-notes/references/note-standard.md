---
title: "Educational Note Standard"
doc_type: template
status: experimental
---

# Note standard

This is an editorial structure, not a form to fill mechanically. Follow the output-language policy in SKILL.md: learner-facing prose and headings use the consuming project's language unless explicitly overridden. The English section names below describe functions, not mandatory output labels. Do not impose fixed headings or item counts regardless of content.

## Document metadata

Every note must start with YAML frontmatter containing a `lang` field whose value is a BCP 47 language tag matching the actual note text. Preserve the existing user/project language-selection policy and other project metadata. For example, a Polish note may begin with `---`, then `lang: pl-PL`, then `---` on separate lines; `pl-PL` is an example, not a default for other languages. Do not copy the transcript's language tag when the note uses a different language.

## Title and meeting details

Use a short, factual title naming the topic, preferably the instructor's concise topic wording. Avoid editorial subtitles, extended prose, and titles that read like a table of contents. Optionally append two or three key concepts in parentheses, as short labels rather than a detailed outline. Do not force this pattern on material it does not fit.

Directly below the title, add one short natural line identifying the meeting and its known date, in the project language. For example: "Prepared from the class: Introduction to economics, 8 November 2026." Adapt "class" to a seminar, workshop, or other meeting as appropriate. Use only established names and dates; omit unavailable details rather than inventing them or inserting technical placeholders. The date is the meeting date, never the processing date. This simple origin line is not a report about transcription or source processing.

## Requirements, decisions, and deadlines

When supported by the source, place this section below the meeting-details line, before the substantive body. Use a natural heading in the project language, such as "Requirements and deadlines". Omit it when no relevant information was given.

Collect instructor instructions and established decisions about homework, deliverables, preparation, assessment criteria, tests, final exams, dates, submission channels, and permitted materials. For other meeting types, apply the same treatment to explicitly assigned work and established deadlines without imposing academic terminology. State what is required, by whom if specified, when, and under which conditions, preserving exact thresholds, scope, and exceptions. Do not invent missing details.

Distinguish confirmed instructions from proposals, tentative dates, and unresolved questions. Student speculation or instructor silence does not establish a requirement. Check later source chunks for corrections, cancellations, or qualifications and show the final supported state; briefly explain a change when needed to prevent confusion. Resolve a relative deadline to a calendar date only when the meeting date and reference are unambiguous; otherwise preserve the original wording and uncertainty. Do not confuse the processing date with the meeting date. Distinguish processing uncertainty from a genuinely open meeting decision: if the instructor explicitly leaves a date unsettled or a proposal awaiting approval, preserve that naturally in the note without automatically blocking the whole result. An important condition that cannot be reliably recovered is different: check context and supplied materials, then apply the final-delivery rule and identify the specific gap outside the note rather than silently omitting it because other requirements are known.

This section must retain actionable detail rather than merely link to scattered body paragraphs. Keep relevant explanations and worked examples in the main note where needed. Preserve evidence links in adjacent HTML comments.

## Topic and context

Start the substantive body with the relevant concept or problem. Establish scope through the content itself rather than an appraisal of the lecture. Do not repeat the course or date in an artificial introductory paragraph after the meeting-details line.

Describe chronology only when the order of discussion or problem solving has educational value. Otherwise use a logical topic map without a separate timeline. Omit greetings, breaks, and technical interruptions. Separate important organizational requirements from substantive content.

## Developed explanation

Use headings corresponding to concepts, problems, or questions. Readers should understand both the conclusion and why and when it applies. Connect definitions to explanations, distinctions to consequences, and rules to limitations and examples present in the source.

For exercises, preserve necessary data, reasoning, and instructor corrections. Do not present all student suggestions as correct. Retain a wrong path when explaining it teaches a useful distinction. A student may be right, but instructor silence alone does not establish that.

Do not invent definitions, explanations, examples, recommendations, answers, or substantive corrections from general knowledge or internet sources. Do not turn an unclear term into fluent but unsupported prose. Preserve important terms and distinctions even when the instructor only touched on them: first inspect surrounding context and available slides, then retain the supported scope without expanding it into textbook coverage. A brief mention may warrant a brief treatment, while incidental mentions and undeveloped slide labels need not all be included or explained. Do not present an uncertain definition as settled. Record unresolved processing doubts internally and withhold final delivery if faithful treatment of an important point remains impossible.

Write as a student's study note, using complete, accessible sentences. Avoid technical provenance phrases such as "dated in the source", "the transcript indicates", or "the material records", and avoid narration about automated processing or reviewing a lecture. Remove unnecessary commentary about the limits of the source, missing coverage, or absent assurances. If it carries a meaningful limitation, retain the supported fact itself in natural prose, such as a historical scope or an explicitly unsettled arrangement, without describing the source's failure to provide information. Do not turn an inability to recover a detail into a claim that the instructor deferred a decision; processing uncertainty still follows the external-handoff rule. Reduce repetitive "the instructor says" framing while retaining necessary attribution for opinions, contested positions, assessment requirements, and actual announcements about future meetings. Do not mechanically replace every reporting verb or speaker reference. Do not use U+2014 or U+2013 in generated substantive prose; use a plain hyphen or recast the sentence. Use lists for parallel items or sequences and tables for actual comparisons. Avoid both walls of text and unexplained shorthand. Do not impose a word limit that removes exceptions or examples.

## Key takeaways

Identify concrete distinctions, rules, relationships, lessons from exercises, and common mistakes supported by the material. Each point should be specific enough for readers to check their understanding.

Add recall questions when they help reconstruct an explanation or apply a distinction. Do not call them exam questions without support. Answers should follow from the note; unresolved meeting questions must not become exercises with supposedly established answers.

## Optional illustrations

Use 0 to 10 representative screenshots only when they document displayed material or improve understanding. Place each near the relevant explanation with concise alt text and, when helpful, a factual caption in the project language. Keep timestamps and selection details in hidden comments or working files. A useful slide, diagram, exercise, or exam-information screen is evidence or teaching material, not decoration. Keep the text understandable without opening an image. Follow the [screenshot contract](screenshots.md) for selection, cropping, and durable relative asset paths.

## Internal evidence

Keep extraction IDs, precise source ranges, timestamps, technical verification details, and agent-work information in HTML comments or separate working files. Readers must not need them to understand the note. Keep all transcription doubts, confidence markers, requests to verify, and agent or review remarks exclusively in valid HTML comments or separate review files. Do not add visible labels such as "unclear in the transcript", "requires verification", or "probably a transcription error". This also applies to image captions and alt text. Preserve actual source-supported conditions in ordinary prose; moving a processing doubt into a comment does not authorize stating an uncertain fact as certain. Resolve the issue, narrow the text to supported content, or omit the unsupported passage and document it internally. If those options would materially mislead readers or lose an important requirement, withhold final delivery and explain the limitation outside the note.
