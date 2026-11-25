# Client compatibility

Use the target client's documentation and installed configuration to choose an entry point. The same model can run in several clients with different discovery rules.

| Client | Instructions | Project skills |
| --- | --- | --- |
| Codex | Use `AGENTS.md` at the applicable scope. | Use `.agents/skills/` at the same scope where supported. |
| Claude Code | If the current setup needs `CLAUDE.md`, put `@AGENTS.md` on its own line outside code fences, using a path relative to that file. Keep only Claude-specific content alongside it. | If Claude needs a separate discovery path, link each required skill directory under `.claude/skills/` to the shared skill. |
| Gemini CLI | Where the project uses `GEMINI.md`, use `@./AGENTS.md` at the same scope, or reuse an existing `context.fileName` setting that already selects `AGENTS.md`. | Prefer the `.agents/skills/` alias when the installed client supports it. |
| Cursor, OpenCode, GitHub Copilot and other clients | Check the installed client's supported entry points, scopes, and settings. | Check for native `.agents/skills/` discovery before adding compatibility paths. |

## Links and verification

- A relative link from `.claude/skills/release-notes` to `../../.agents/skills/release-notes` makes the same directory available under both paths. The target is relative to the directory containing the link. Prefer per-skill links where the client's skills directory already contains unrelated entries.
- On Windows, a directory junction can provide the same local path mapping if the client follows it. A junction is local filesystem setup. If collaborators need it, document how to recreate it after checkout. For tracked symlinks, check the team's checkout configuration, including Git's `core.symlinks` where relevant.
- In Claude Code use `/memory` to inspect instructions. In Gemini CLI use `/memory show` and `/skills list`. Use a fresh session or the client's reload mechanism after moving files. Check discovery in each client that depends on a link before removing its legacy entry.
- MCP is a shared protocol. Its client registration belongs in the client configuration. When moving a skill, check that it can still identify its required tool by capability and that any client-specific tool names remain meaningful.

[Coding agent instructions](https://agents.md/) · [Agent Skills specification](https://agentskills.io/specification) · [Codex skill discovery](https://learn.chatgpt.com/docs/build-skills) · [Claude Code instructions](https://code.claude.com/docs/en/memory) · [Claude Code skills](https://code.claude.com/docs/en/skills) · [Gemini CLI instructions](https://geminicli.com/docs/cli/gemini-md/) · [Gemini CLI skills](https://geminicli.com/docs/cli/tutorials/skills-getting-started/) · [MCP overview](https://modelcontextprotocol.io/docs/getting-started/intro)

The migration sequence draws on [Adobe's repository migration guide](https://opensource.adobe.com/ai-repo-harness-guide/08-Migrate-Your-Harness/).
