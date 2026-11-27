# Quiet scheduled checks for ChatGPT Desktop

Use this reference only for schedule configuration and heartbeat execution. Manual restart requests use the immediate-dispatch mode in SKILL.md.

## Schedule setup

Use `automation_update`. Create or update a thread heartbeat, normally hourly, with failure-only notifications (`notificationPolicy: failed_runs_only` when supported). Preserve its ID and target chat when changing an existing schedule.

**The configuring agent must save a self-contained runtime prompt.** Skill loading during setup does not guarantee skill loading when the timer fires. A skill name or reference-file path alone is insufficient. Explicitly save the two-page limit, active-work and idle-time conditions, target-chat selection, resolved helper command, and quiet chat-output rules. Keep app notification preferences in the automation setting; chat-output instructions belong in the saved task itself. Do not copy unrelated manual-mode or implementation guidance.

Use the template below as the task's core, resolving its placeholders before saving. On a later policy or path change, update existing saved prompts too; editing this reference alone does not update installed schedules.

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

## Self-contained saved-task template

```text
This is a scheduled idle check for Codex in ChatGPT Desktop on Windows, not a manual restart. All necessary runtime instructions are below; opening a skill file is not a prerequisite.

Produce no ordinary chat reply or progress commentary for skips, active work, recent activity, successful dispatch, or successful prior restarts. If the host requires a heartbeat result, return only its non-notifying DONT_NOTIFY result with a minimal technical message. Write an error report only for a new concrete failure of this automation; never repeat old errors or report manual-test failures as schedule failures.

Inspect a new latest restart log under system TEMP/codex-idle-restart only for its result/summary and matching AutomationId <AUTOMATION_ID>. Keep raw commands and credentials out of the chat.

Use list_threads in history mode for source codex, host local, limit 50. Read at most two pages using the returned cursor; no third/final listing or exhaustive scan. Stop immediately if inspected chats contain another running turn, queued request, approval, or waiting-for-input task. Only the current maintenance turn is exempt. Unknown/incomplete evidence means skip. A remaining cursor beyond page two is an expected bounded-check limit, not an error.

Require <IDLE_MINUTES> minutes since recent ordinary finished work. Use actual read_thread completedAt timestamps, normalizing seconds/milliseconds. This automation's own status-only checks do not reset that interval. Recent work or insufficient idle evidence means skip quietly.

Choose the latest relevant local chat in the inspected scope, discounting maintenance updates. If eligible, execute Windows PowerShell with the installed script <ABSOLUTE_SCRIPT_PATH>, -ThreadId <CHOSEN_CHAT_UUID> -Execute -AutomationId <AUTOMATION_ID>. Use no ForceClose and leave the default TEMP log path. Then finish this turn promptly. A worker PID proves dispatch only, not restart success. The helper relaunches after the saved tree is empty, without a fixed 20-second pause. Do not kill processes or improvise another restart method if it fails.
```
