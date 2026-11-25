---
name: standardize-agent-layout
description: Audit, set up, or gradually migrate a project's agent instructions and skills to AGENTS.md and .agents/skills across coding clients.
---

# Standardize Agent Layout

Keep shared standing instructions in `AGENTS.md` at the repository root or at the directory where they apply. Keep each task-specific workflow and its resources together under `.agents/skills/<name>/SKILL.md`, using the equivalent location in a subdirectory when the skill has narrower scope. Use client-specific entry points where discovery requires them.

## Inspect the current setup

- Identify the project boundary, clients in use, and the scope of the request. An audit produces findings without editing files. A setup or migration changes only the agreed area. When standardizing as part of other work, migrate the instructions or skills relevant to that work in a small, independently verifiable step.
- Read the applicable project instructions. Inventory relevant instruction files, scoped rules, skill directories, imports, and links. Follow links to identify the authoritative files, and distinguish tracked project content, local overrides, and managed installations. Compare similarly named files before treating them as duplicates.
- Record what each client loads and when. Note scope, precedence, activation, and dependencies that would change if an instruction or skill moved.

## Apply the smallest complete migration

1. Map each affected source to its destination and identify the old entry points that still have callers. Preserve distinct instructions and active edits. If a conflict cannot be resolved from project intent or a required behavior cannot be reproduced, leave that part operational and report the decision needed.
2. Consolidate shared instructions at their original scope. Put project-wide rules in the root `AGENTS.md`, local rules in the appropriate scoped file, and reusable conditional workflows in skills. Keep client-specific or path-triggered behavior in a native rule if moving it would change when or how it applies.
3. Move a complete skill directory, including scripts, references, assets, and client metadata needed for behavior. Keep the folder name and frontmatter `name` aligned. Update relative references, callers, and setup instructions as needed. Preserve the authoritative source of externally managed skills and use their supported installation mechanism.
4. Add compatibility entry points only for clients that need them. Use a supported import for an instruction file, or a symbolic link for a skill directory. A local NTFS junction is an option on Windows when the target client follows it. Read [Client compatibility](references/client-compatibility.md) for example paths and verification. Keep MCP registrations, credentials, hooks, and permissions in their existing locations unless the user separately asks to change them.
5. Confirm the replacement before retiring legacy entries. If discovery cannot be checked and retirement would remove a working entry point, retain it for a later step. Leave unrelated modules and client settings outside the migration.

## Verify and report

- Compare the migrated content and its scope with the originals. Check import and link targets, skill frontmatter, and relative paths to bundled resources. Check that no duplicate discovery entry or staging of local-only material was introduced.
- In each available target client, confirm that the expected instructions load and that at least one changed skill is discoverable from the intended working directory. For scoped rules, also verify where they should not apply. If the layout is shared through Git, verify that a fresh checkout can use or recreate required links.
- Report what moved, which clients were checked, and any compatibility checks or migration steps that remain.
