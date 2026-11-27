---
name: codex-idle-restart
description: Check Codex chats for active work and recent completed turns, then restart the Windows desktop app and clean up its saved process tree when an authorized idle-maintenance run is eligible.
---

# Codex Idle Restart

Use this for an authorized one-off restart or recurring idle maintenance of the Codex desktop app on Windows. The agent decides whether restarting is appropriate. The bundled PowerShell script only snapshots processes, closes the app, cleans up the saved tree, waits 20 seconds, and relaunches it.

## Eligibility

Use the available Codex app tools to inspect chats. Tool names can be deferred; discover `list_threads` and `read_thread`. Do not substitute CPU usage, process existence, or a database timestamp for live task status.

**Stop as soon as a definite blocker is confirmed.** One other active task or one finished turn within the idle interval is sufficient to skip. Do not continue paginating or inspect process trees just to prove a skip. Full coverage is needed only before declaring a restart eligible. Report the decisive evidence and which conditions were not checked.

1. Enumerate chats and their runtime statuses, including pinned chats. Follow pagination when required to cover all potentially active Codex tasks; the first page of recent chats alone is not proof of global inactivity. Include other connected hosts and ChatGPT work when they can be affected by restarting the desktop client. An unavailable source, incomplete inventory, unrecognized status, or missing required tool means **skip this run**.
2. A running turn, queued user request, pending approval, or waiting-for-input task blocks restart. Only the exact current maintenance turn in its own chat is exempt. Do not exempt all work in that chat or all scheduled tasks. In a subagent simulation, do not automatically exempt an active parent conversation as if it were a separate maintenance run; identify the exact exempt turn or treat it as blocking activity. Treat only statuses known to mean idle/unloaded as idle; inspect ambiguous cases with `read_thread`.
3. Require at least **60 minutes since the latest finished turn**, unless the user supplied another interval. Inspect recent turn history, including earlier turns in the maintenance chat. Use the actual terminal-turn `completedAt` timestamp, including failed/interrupted work when available. Normalize seconds versus milliseconds and compare with the current clock. Do not use a title edit or `updatedAt` as a completion timestamp. Other maintenance runs count as activity; exclude only the current run. Missing evidence, a future timestamp, or unresolved pending input means skip.
4. For efficiency, a documented chat update timestamp that cannot predate its last finished turn may be used to identify chats whose histories need inspection. It is only a candidate filter, never the completion-time check itself. If that property is not established, inspect the necessary histories rather than assuming recency order proves inactivity.
5. Choose the most recently updated **local Codex chat** to reopen. Discount the update caused by this maintenance turn; use that chat's preceding ordinary activity when comparing it with other chats. If no target can be established, skip rather than opening an arbitrary chat.

The agent must pass the chosen chat's UUID explicitly through `-ThreadId`. The script does not choose a chat or infer it from the invoking agent's environment. It forwards the same UUID to its detached worker and constructs `codex://threads/<ThreadId>`; opening this link does not send a prompt or resume an agent turn.

Perform one final live status check immediately before launching the script. Restart authorization for recurring maintenance is standing authorization for eligible runs; do not ask again every run. This skill does not itself authorize creating or enabling a schedule. There is no atomic lock against new user work: a request arriving after the final check can still race with shutdown.

## Restart script

Requires Windows PowerShell 5.1+, CIM/WMI, and one identifiable Microsoft Store Codex desktop instance. Resolve `scripts/restart-codex.ps1` relative to this skill's installed directory. It has no Node, Python, or downloaded dependencies. The installed application currently uses a main `ChatGPT.exe` under an `OpenAI.Codex_*` package; unexpected layouts fail without guessing.

First inspect the dry-run JSON. Without `-Execute`, the command does not create a worker, close windows, write a log, or terminate processes:

```powershell
& '<skill-directory>\scripts\restart-codex.ps1' -ThreadId '<local-chat-uuid>'
```

After eligibility is established, run:

```powershell
& '<skill-directory>\scripts\restart-codex.ps1' -ThreadId '<local-chat-uuid>' -Execute
```

The command returns a worker PID and log path. Finish the maintenance turn promptly after dispatch; do not keep it active by polling the worker. The hidden worker is detached through WMI so it survives the app's shutdown. It waits briefly for the launching turn to finish, then performs exactly this sequence:

1. Save the Codex root and complete descendant PID tree, including process creation times, command lines, working-set bytes, and private committed bytes, in the log.
2. Ask the main window to close and wait up to 30 seconds for the root process to exit. A refusal, timeout, changed root, or inaccessible process stops the operation; do not force-kill the root to bypass it.
3. Terminate remaining members of the saved descendant tree, deepest first. Verify PID plus creation time before each termination. A missing process is already cleaned up; a reused PID is skipped. Never kill processes globally by executable name.
4. Wait **20 seconds after cleanup completes**.
5. Relaunch the captured desktop executable with `codex://threads/<uuid>` to reopen the selected chat. Do not automatically send another prompt.

Only an actual `-Execute` dispatch creates logging output; skipped eligibility checks and dry runs create no log or log directory. Logs default to the system temporary directory, under `codex-idle-restart/restart-<UTC-time>-<UUID>.jsonl`. Resolve that root through `[System.IO.Path]::GetTempPath()`, not a hard-coded profile path. An explicit absolute `-LogPath` can be supplied. Review the previous real attempt's log on the next maintenance run.

The log distinguishes the initial tree, survivors after graceful closure, and cleanup outcomes (`terminated`, `already_exited`, `pid_reused`). It records current command/memory details for processes that require forced termination, followed by saved-tree memory totals after cleanup and before relaunch. This lets the user distinguish normal application shutdown from additional cleanup. Common credential flags, assignments, and URL query parameters are redacted from commands; keep the diagnostic files local because arbitrary arguments can still contain sensitive data.

Report working-set decreases as estimates: shared pages can be counted more than once, private committed bytes are not physical RAM, and these measurements do not subtract the cost of the newly launched app. A process surviving graceful closure is evidence of a leftover, not proof that it was an abandoned MCP connection before shutdown. Do not label every descendant a dead MCP server.

A returned worker PID confirms dispatch, not successful restart. The worker records `launched` after process creation; it cannot verify that the UI actually opened the chat. Report that limitation accurately.

For an explicitly authorized forced-close test, `-ForceClose` allows terminating the saved, revalidated desktop root if window closure has not ended it within five seconds. It records `root_force_close` and then follows normal saved-tree cleanup and the 20-second delay. Do not add this flag to routine scheduled runs without user authorization; ordinary window closure may only hide the app in the system tray.

Cleanup is scoped to the saved tree, including tool-launched descendants. Already-orphaned processes outside that tree and children spawned after the snapshot are not identified. Do not expand cleanup to unrelated processes as a fallback. If cleanup fails after the app closed, the worker attempts to restore the application and records the failure; do not report a clean restart.

## Maintenance and verification

Keep activity decisions in these instructions, not in an extra service or polling supervisor. Do not replace the script with an MCP gateway or add a separate client to Codex's internal pipe.

Use the dry run and synthetic tests when changing the script. A live restart interrupts this agent; perform it only as the authorized restart itself or when the user explicitly asks for a live test. Create or enable recurring execution only when requested; a standing schedule request authorizes eligible future restarts even if a live development test was not requested. Source publication and installation do not require restarting Codex.
