# Quiet scheduled checks for ChatGPT Desktop

Use this reference only for schedule configuration and heartbeat execution. Manual restart requests use the immediate-dispatch mode in SKILL.md.

## Schedule setup

Use `automation_update`. Create or update a thread heartbeat, normally hourly, with failure-only notifications (`notificationPolicy: failed_runs_only` when supported). Preserve its ID and target chat when changing an existing schedule. The saved prompt should invoke `$restart-codex` in **scheduled-check mode**, reference this file, and state the two-page limit and quiet behavior. Do not copy the whole skill into the prompt.

## Runtime decision

1. If a new log from a previous real attempt is available, inspect only its result and summary. The log's `AutomationId` identifies whether it belongs to this schedule. Notify only about a new failure of this automation; do not report old manual-test failures or repeat a failure already reported.
2. Discover `list_threads` and `read_thread`. Read **at most two pages**, with 50 entries per page, from local Codex chat history in recency order. Pass `mode: history`, `source: codex`, `hostId: local`, and the returned cursor for the second page. Stop early on a definite blocker. Do not list more pages or run a third final check.
3. A running turn, queued user request, pending approval, or waiting-for-input task in the inspected chats blocks restart. The current maintenance turn is exempt; other work in that chat is not. Unknown statuses and unavailable data mean skip. Only known idle/unloaded statuses qualify as idle.
4. Require 60 minutes since recent ordinary work, unless configured otherwise. Use actual terminal-turn `completedAt` values from recent relevant histories, not a title-edit/update timestamp. A recent finished turn is an immediate blocker. This automation's own status-only checks must not continually reset the idle interval; inspect preceding ordinary activity in its chat when needed. Other automations doing real work count as activity. If the bounded inspection cannot establish enough idle evidence, skip quietly.
5. Select the most recently active local chat observed in this inspection, discounting this maintenance turn's update. Pass its UUID through `-ThreadId`. If no target can be established, skip.
6. If eligible, dispatch the bundled helper with `-Execute -ThreadId '<uuid>' -AutomationId '<automation-id>'` and finish the turn promptly. Use the default TEMP log path. Do not use `-ForceClose` unless separately authorized.

The decision is deliberately limited to at most 100 recent local chats. A cursor beyond the second page is expected, not an API failure and not a requirement to scan thousands of older chats. Do not claim that this bounded check proves inactivity of every chat or remote host. No atomic lock prevents new work from arriving after the check.

## Quiet behavior

Normal skips, active work, recent activity, successful dispatch, and a successful previous restart produce **no chat update or progress commentary**. Use the host's non-notifying heartbeat result (`DONT_NOTIFY`) when a terminal heartbeat response is required. Put no user-facing prose outside it.

Notify only about a concrete failure in this automation: a failed tool/dispatch, a failed scheduled restart log, or broken installation needed by the schedule. Include a short error and next action, without raw commands or credentials. A two-page cap or ordinary uncertainty is a normal skip, not a failure notification.
