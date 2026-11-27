---
name: restart-codex
description: Restart Codex in ChatGPT Desktop for Windows immediately on a manual request, or configure a quiet scheduled idle check with at most two pages of chats. Includes graceful Quit, saved process-tree cleanup, and local diagnostics.
---

# Restart Codex (ChatGPT Desktop)

This skill targets the Codex experience in **ChatGPT Desktop for Windows**, not a standalone CLI session. It has two separate modes. Choose by the user's intent; editing, installing, configuring, or testing this skill without restart is not a request to restart the app.

## Restart now

A direct request such as “restart Codex”, “restart ChatGPT Desktop”, or “let's test the restart” authorizes dispatch now. Do not run scheduled idle checks, enumerate chats, impose a 60-minute threshold, or create a schedule. Use the current chat's UUID unless the user selected another local chat. The agent passes it explicitly; the script does not select a chat.

Resolve the helper relative to the installed skill folder:

```powershell
& '<skill-directory>\scripts\restart-codex.ps1' -ThreadId '<local-chat-uuid>' -Execute
```

Dispatch promptly and finish the turn. The helper's short startup delay lets this turn finish; do not poll it. Explain briefly that the app will reopen this chat and that the user should let it return on its own. A worker PID confirms dispatch, not completion. Opening the chat does not send a new prompt.

Without `-Execute`, the helper only prints a process snapshot. Use that mode when the user asks for inspection or a test **without** restarting. Do not require an extra dry run before every manual restart.

## Configure or run scheduled checks

When the user asks to add recurring checks to a chat, read [references/scheduled-checks.md](references/scheduled-checks.md). That mode owns activity checks and notification policy. It does not change the manual mode into an idle-only restart.

Use the app's automation tool to create or update a heartbeat attached to the requested chat. Preserve an existing automation instead of creating a duplicate. Default to hourly checks and the established 60-minute idle interval unless the user requests otherwise. Configure failure-only notifications through the automation setting. **Write the runtime decision rules and quiet chat-output rules explicitly into the saved automation prompt.** Do not rely on the future run opening this skill or a reference file: the saved task must be operationally self-contained, including the helper's resolved path. Do not create or enable a schedule merely because the user invoked a manual restart.

## Helper behavior

Requires Windows PowerShell 5.1+, CIM/WMI, and one identifiable ChatGPT Desktop/Codex Microsoft Store instance. No Node, Python, or downloaded packages are required. The verified package uses a main `ChatGPT.exe` under `OpenAI.Codex_*`; an unknown layout fails without guessing.

1. Restore a tray-only instance through normal single-instance activation with the selected chat link. Verify the same root PID and creation time. Snapshot the tree **after** activation so new renderers are included.
2. Invoke real Quit using the verified Windows **Ctrl+Q** accelerator. Check the original main-window handle and foreground PID before sending keys. Do not send input to a different window, a confirmation dialog, or another app. Do not use `CloseMainWindow()`, which can merely hide the window.
3. Allow up to 45 seconds for graceful exit: first request, 15 seconds, a second request if possible, then 30 seconds. Continue immediately if the process exits earlier. A failed focus check sends no keys. Log whether each attempt was sent.
4. Inspect saved descendants using one bulk process snapshot. Revalidate PID plus creation time only for still-running candidates before termination; process deepest descendants first. Never kill globally by executable name.
5. Verify that **no saved process identity remains**. A failed check or cleanup error blocks relaunch. Otherwise launch the captured desktop executable with `codex://threads/<ThreadId>` **immediately**, without a fixed 20-second pause.

The Ctrl+Q binding was verified in the installed app's native Quit definition. An app update may change it; verify the binding when troubleshooting instead of guessing another shortcut. Tray activation or foreground restrictions can prevent a graceful request.

`-ForceClose` remains an explicit, separately authorized fallback after both attempts and their full 45-second wait. Do not add it to normal manual or scheduled commands without that authorization. Forced termination can interrupt database writes despite the longer grace period.

## Logs and results

Only actual `-Execute` attempts create logs, under the system TEMP directory in **`codex-idle-restart/`**. This historical log-folder name is intentionally retained. Skipped checks and dry runs create no logs. `-LogPath` can override the path. Scheduled calls additionally pass `-AutomationId` so their failures are distinguishable from manual tests.

JSONL records include the initial PID tree, process creation times, commands with common credential values redacted, working sets, private committed bytes, post-Quit survivors, cleanup outcomes, and memory estimates before relaunch. Keep raw logs local; arbitrary arguments can still contain sensitive data. Do not call every descendant a dead MCP server. Working-set sums share pages, private committed bytes are not physical RAM, and these decreases do not subtract the new app's memory.

`launched` confirms process creation, not successful UI navigation. If cleanup fails, the app may remain closed; report the recorded failure rather than launching over surviving saved processes. Already-orphaned processes outside the saved tree and children created after the snapshot are not covered.

Run synthetic tests when changing the helper. A live restart is a separate authorized action; do not restart the app while authoring the skill or editing its schedule.
