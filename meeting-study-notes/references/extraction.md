---
title: "Staged Extraction Contract"
doc_type: instruction
status: experimental
---

# Extraction subagent task

Read SKILL.md and this contract. You receive a manifest, ordered chunk paths, and a working directory. Read one chunk, save its ledger, then continue. Do not load every chunk in one call. Do not write the final note.

Save `extract-CNNN.json` for each chunk. Keep schema keys, identifiers, and enum values in English. Write explanatory content in the selected project language; preserve evidence quotes verbatim in the source language. The pipe-separated values below denote alternatives, not literal combined values.

```json
{
  "chunk_id": "C001",
  "core_read": true,
  "meeting_mode": "lecture | exercise | discussion | mixed",
  "items": [
    {
      "id": "C001:I01",
      "kind": "definition | distinction | claim | explanation | example | exercise | correction | question | requirement",
      "content": "Detailed content including conditions, limitations, and reasoning",
      "attribution": "instructor / student / uncertain",
      "evidence": {"quote": "short verbatim excerpt from the core range", "source_lines": "L12-L15"},
      "depends_on": [],
      "uncertainty": null
    }
  ],
  "excluded": [{"scope": "brief description", "reason": "e.g. greeting or repetition of C001:I01 without new content"}],
  "open_links": [],
  "verification_questions": []
}
```

Not every utterance needs a separate item, but do not merge so many threads that a condition, exception, concrete example, or change of position disappears. Preserve task data and its resolution if given. Include student questions that exposed a misunderstanding and how it was explained. Do not infer instructor acceptance when the source leaves it unresolved.

Preserve educationally meaningful boundaries, values, and ranges, including those stated by students. Do not replace an explicit limit with vague words such as "appropriate" or "specified." Separate an actual recommendation from an inferred sequence of subsequent work.

Evidence must come from the core range. Repeated context restores continuity rather than creating duplicate items. Link an answer or correction in the next chunk after reading it. Preserve uncertain terms in short quotations and explain what evidence is missing.

Capture every instructor instruction or established decision about assignments, preparation, assessment, tests, exams, dates, submission methods, or permitted materials as a `requirement` item (or a linked `correction` when revised). Preserve exact quantities, thresholds, deadlines, responsible participants if specified, and conditions. Record who established the instruction and whether it is confirmed, tentative, or unresolved. Link later changes or cancellations across chunks; do not infer approval from silence or fill in missing details. Identify these items in the compact handoff so the writer can build the opening requirements section.

At completion, return only ledger paths, a brief meeting-type description, item counts per chunk, and issues requiring separate verification. Do not return the full transcript or lengthy working analysis.
