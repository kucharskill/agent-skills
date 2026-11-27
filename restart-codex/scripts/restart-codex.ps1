<# Dry run by default. Eligibility checks belong to the invoking agent. #>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')]
    [string]$ThreadId,
    [switch]$Execute,
    [switch]$ForceClose,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,79}$')][string]$AutomationId,
    [ValidateRange(0,60)][int]$DispatchDelaySeconds = 5,
    [string]$LogPath,
    [switch]$Worker,
    [int]$DesktopPid,
    [long]$ExpectedCreated
)
$ErrorActionPreference = 'Stop'

function Get-CreatedTicks($Process) {
    return $Process.CreationDate.ToUniversalTime().Ticks.ToString()
}

function Protect-CommandLine([string]$Command) {
    if (!$Command) { return $null }
    $flags = '(?i)(--?(?:mcp-secret|password|passwd|token|access-token|api-key|secret)(?:=|\s+))("[^"]*"|''[^'']*''|\S+)'
    $value = [regex]::Replace($Command, $flags, '$1[REDACTED]')
    $value = [regex]::Replace($value, '(?i)(\b(?:API_KEY|ACCESS_TOKEN|PASSWORD|SECRET)\s*=\s*)("[^"]*"|''[^'']*''|[^\s&]+)', '$1[REDACTED]')
    return [regex]::Replace($value, '(?i)([?&](?:access_token|api_key|token|password)=)[^&#\s"'']+', '$1[REDACTED]')
}

function Get-ProcessDetails($Process) {
    [pscustomobject]@{ Pid = [int]$Process.ProcessId; ParentPid = [int]$Process.ParentProcessId
        Created = Get-CreatedTicks $Process; Name = $Process.Name
        CommandLine = Protect-CommandLine $Process.CommandLine
        WorkingSetBytes = $(if ($null -ne $Process.WorkingSetSize) { [long]$Process.WorkingSetSize } else { $null })
        PrivateBytes = $(if ($null -ne $Process.PrivatePageCount) { [long]$Process.PrivatePageCount } else { $null }) }
}

function Get-MemoryTotals([object[]]$Records) {
    $rows = @($Records | Where-Object { $null -ne $_ })
    [pscustomobject]@{ Count = $rows.Count
        WorkingSetBytes = [long](($rows | Measure-Object WorkingSetBytes -Sum).Sum)
        PrivateBytes = [long](($rows | Measure-Object PrivateBytes -Sum).Sum)
        MissingWorkingSet = @($rows | Where-Object { $null -eq $_.WorkingSetBytes }).Count
        MissingPrivateBytes = @($rows | Where-Object { $null -eq $_.PrivateBytes }).Count }
}

function Get-DefaultLogPath {
    return Join-Path ([System.IO.Path]::GetTempPath()) ('codex-idle-restart/restart-' + [datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ') + '-' + [guid]::NewGuid().ToString() + '.jsonl')
}

function Get-SavedSurvivors($Plan) {
    $live = @{}
    foreach ($item in @(Get-CimInstance Win32_Process)) { $live[[int]$item.ProcessId] = $item }
    foreach ($saved in $Plan.Tree) {
        $item = $live[[int]$saved.Pid]
        if ($item -and (Get-CreatedTicks $item) -eq $saved.Created) { Get-ProcessDetails $item }
    }
}

function Get-SavedTree([object[]]$Processes, [int]$RootId) {
    $root = @($Processes | Where-Object { $_.ProcessId -eq $RootId })
    if ($root.Count -ne 1) { throw 'Expected one desktop root process.' }
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue(@{ Process = $root[0]; Depth = 0 })
    $seen = @{}
    while ($queue.Count) {
        $entry = $queue.Dequeue()
        $item = $entry.Process
        if ($seen.ContainsKey([int]$item.ProcessId)) { throw 'Invalid process-tree cycle.' }
        $seen[[int]$item.ProcessId] = $true
        $details = Get-ProcessDetails $item
        $details | Add-Member NoteProperty Depth $entry.Depth
        $details
        foreach ($child in @($Processes | Where-Object {
            $_.ParentProcessId -eq $item.ProcessId -and $_.CreationDate -ge $item.CreationDate
        })) { $queue.Enqueue(@{ Process = $child; Depth = $entry.Depth + 1 }) }
    }
}

function Find-Desktop([object[]]$Processes) {
    $roots = @($Processes | Where-Object {
        $_.Name -eq 'ChatGPT.exe' -and $_.ExecutablePath -match '\\OpenAI\.Codex_[^\\]+\\app\\ChatGPT\.exe$' -and
        $_.CommandLine -notmatch '--type='
    })
    if ($roots.Count -ne 1) { throw "Expected one Codex desktop instance; found $($roots.Count)." }
    return $roots[0]
}

function Write-Event([string]$Event, $Details) {
    $record = @{ Time = [datetime]::UtcNow.ToString('o'); Event = $Event; Details = $Details
        AutomationId = $AutomationId; Mode = $(if ($AutomationId) { 'scheduled' } else { 'manual' }) }
    $line = ConvertTo-Json -InputObject $record -Depth 7 -Compress
    [System.IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Focus-DesktopForQuit($App, [IntPtr]$ExpectedWindow = [IntPtr]::Zero) {
    $window = $App.MainWindowHandle
    if ($window -eq [IntPtr]::Zero) { return $false }
    if ($ExpectedWindow -ne [IntPtr]::Zero -and $window -ne $ExpectedWindow) { return $false }
    if (!('CodexQuitNative' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CodexQuitNative {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint processId);
}
'@
    }
    $null = [CodexQuitNative]::ShowWindow($window, 9)
    $null = [CodexQuitNative]::SetForegroundWindow($window)
    $foreground = [CodexQuitNative]::GetForegroundWindow()
    [uint32]$foregroundPid = 0
    $null = [CodexQuitNative]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
    return $foreground -eq $window -and $foregroundPid -eq $App.Id
}

function Send-DesktopQuitShortcut {
    $shell = New-Object -ComObject WScript.Shell
    try { $shell.SendKeys('^q') }
    finally { $null = [System.Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

function Request-DesktopQuit($App, [IntPtr]$ExpectedWindow = [IntPtr]::Zero) {
    # The installed Windows app binds Ctrl+Q to Electron's real Quit command.
    if (!(Focus-DesktopForQuit $App $ExpectedWindow)) { return $false }
    Send-DesktopQuitShortcut
    return $true
}

function Restore-DesktopWindow($Desktop, [string]$Uri) {
    $app = Get-Process -Id $Desktop.ProcessId
    if ($app.MainWindowHandle -ne [IntPtr]::Zero) { return }
    # Normal single-instance activation restores a tray-only app, without closing it.
    Write-Event 'window_restore_requested' @{ Pid = $Desktop.ProcessId }
    Start-Process -FilePath $Desktop.ExecutablePath -ArgumentList $Uri
    for ($attempt = 0; $attempt -lt 25; $attempt++) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($Desktop.ProcessId)"
        if (!$current -or (Get-CreatedTicks $current) -ne (Get-CreatedTicks $Desktop)) { throw 'Desktop changed while restoring its window.' }
        $app.Refresh()
        if ($app.MainWindowHandle -ne [IntPtr]::Zero) { return }
        Start-Sleep -Milliseconds 200
    }
    throw 'The desktop window could not be restored from the tray.'
}

function Close-Desktop($Plan) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($Plan.RootPid)"
    if (!$current -or (Get-CreatedTicks $current) -ne $Plan.RootCreated) { throw 'Desktop root changed.' }
    $app = Get-Process -Id $Plan.RootPid
    $null = $app.Handle
    $quitWindow = $app.MainWindowHandle
    $attempt = 0
    # Two real Quit requests: at the start and after 15 seconds. Allow 45 seconds total.
    foreach ($waitMs in @(15000, 30000)) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($Plan.RootPid)"
        if (!$current) { return }
        if ((Get-CreatedTicks $current) -ne $Plan.RootCreated) { throw 'Desktop root identity changed during graceful close.' }
        $app.Refresh()
        $accepted = Request-DesktopQuit $app $quitWindow
        $attempt++
        Write-Event 'graceful_close_request' @{ Pid = $Plan.RootPid; Attempt = $attempt; Accepted = $accepted; Method = 'Ctrl+Q'; WaitMilliseconds = $waitMs }
        if ($app.WaitForExit($waitMs)) { return }
    }
    if (!$ForceClose) { throw 'Desktop close was cancelled or timed out.' }
    # Explicit opt-in only: close-to-tray can leave the desktop root running.
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($Plan.RootPid)"
    if (!$current) { return }
    if ((Get-CreatedTicks $current) -ne $Plan.RootCreated) { throw 'Desktop root identity changed; refusing forced close.' }
    Write-Event 'root_force_close' (Get-ProcessDetails $current)
    Stop-Process -InputObject $app -Force -ErrorAction Stop
    if (!$app.WaitForExit(5000)) { throw 'Desktop root did not exit after explicit forced close.' }
}

function Stop-SavedTree($Plan) {
    # One bulk read avoids a CIM round trip for every already-exited descendant.
    $live = @{}
    foreach ($item in @(Get-CimInstance Win32_Process)) { $live[[int]$item.ProcessId] = $item }
    foreach ($saved in @($Plan.Tree | Where-Object { $_.Pid -ne $Plan.RootPid } | Sort-Object Depth -Descending)) {
        $current = $live[[int]$saved.Pid]
        if (!$current) { Write-Event 'process_cleanup' @{ Action = 'already_exited'; Pid = $saved.Pid }; continue }
        if ((Get-CreatedTicks $current) -ne $saved.Created) {
            Write-Event 'process_cleanup' @{ Action = 'pid_reused'; Pid = $saved.Pid }; continue
        }
        # Revalidate only live candidates immediately before a possible termination.
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($saved.Pid)"
        if (!$current) { Write-Event 'process_cleanup' @{ Action = 'already_exited'; Pid = $saved.Pid }; continue }
        if ((Get-CreatedTicks $current) -ne $saved.Created) {
            Write-Event 'process_cleanup' @{ Action = 'pid_reused'; Pid = $saved.Pid }; continue
        }
        $handle = Get-Process -Id $saved.Pid -ErrorAction SilentlyContinue
        if (!$handle) { Write-Event 'process_cleanup' @{ Action = 'already_exited'; Pid = $saved.Pid }; continue }
        $details = Get-ProcessDetails $current
        # Keep the original process handle for waiting, even if its numeric PID is later reused.
        $null = $handle.Handle
        try { Stop-Process -InputObject $handle -Force -ErrorAction Stop }
        catch { if (!$handle.HasExited) { throw } }
        if (!$handle.WaitForExit(5000)) { throw "Process did not exit: $($saved.Pid)" }
        Write-Event 'process_cleanup' @{ Action = 'terminated'; Process = $details }
    }
}

function Start-Desktop($Plan) {
    if (!(Test-Path -LiteralPath $Plan.Executable -PathType Leaf)) { throw 'Captured desktop executable is unavailable.' }
    $alreadyRunning = @(Get-CimInstance Win32_Process | Where-Object {
        $_.ExecutablePath -eq $Plan.Executable -and $_.CommandLine -notmatch '--type='
    })
    if ($alreadyRunning.Count) { throw 'A desktop instance is already running; not launching another.' }
    Start-Process -FilePath $Plan.Executable -ArgumentList $Plan.Uri
}

function Invoke-RestartPlan($Plan) {
    Write-Event 'snapshot' $Plan
    Close-Desktop $Plan
    $remainingAfterClose = @(Get-SavedSurvivors $Plan)
    Write-Event 'closed' @{ Survivors = $remainingAfterClose; Memory = Get-MemoryTotals $remainingAfterClose }
    try {
        Stop-SavedTree $Plan
        $remainingAfterCleanup = @(Get-SavedSurvivors $Plan)
        if ($remainingAfterCleanup.Count) {
            Write-Event 'cleanup_incomplete' @{ Pids = @($remainingAfterCleanup.Pid) }
            throw 'Saved process identities are still running; relaunch blocked.'
        }
        $before = Get-MemoryTotals $Plan.Tree
        $afterClose = Get-MemoryTotals $remainingAfterClose
        $afterCleanup = Get-MemoryTotals $remainingAfterCleanup
        Write-Event 'cleaned' @{ Before = $before; AfterClose = $afterClose; AfterCleanup = $afterCleanup
            WorkingSetDecreaseBytes = $before.WorkingSetBytes - $afterCleanup.WorkingSetBytes
            PrivateBytesDecreaseBytes = $before.PrivateBytes - $afterCleanup.PrivateBytes
            CleanupWorkingSetDecreaseBytes = $afterClose.WorkingSetBytes - $afterCleanup.WorkingSetBytes
            CleanupPrivateBytesDecreaseBytes = $afterClose.PrivateBytes - $afterCleanup.PrivateBytes
            Note = 'Saved process identities only, before relaunch. Working sets share pages; differences are estimates, not measured net RAM savings.' }
    } catch {
        Write-Event 'cleanup_failed' @{ Message = $_.Exception.Message }
        throw
    }
    Start-Desktop $Plan
    Write-Event 'launched' @{ ThreadId = $Plan.ThreadId }
}

function Invoke-Main {
    if (!$ThreadId) { throw '-ThreadId is required.' }
    if ($env:OS -ne 'Windows_NT') { throw 'This script requires Windows.' }
    if ($Worker) {
        if (!$DesktopPid -or !$ExpectedCreated -or ![System.IO.Path]::IsPathRooted($LogPath)) { throw 'Invalid worker arguments.' }
        Start-Sleep -Seconds $DispatchDelaySeconds
    }
    $all = @(Get-CimInstance Win32_Process)
    $desktop = Find-Desktop $all
    if ($Worker -and ($desktop.ProcessId -ne $DesktopPid -or (Get-CreatedTicks $desktop) -ne $ExpectedCreated.ToString())) {
        throw 'Desktop was replaced before the worker started.'
    }
    if ($Worker) {
        Restore-DesktopWindow $desktop "codex://threads/$ThreadId"
        # Activation may create renderers. Include them before saving the tree.
        $all = @(Get-CimInstance Win32_Process)
        $desktop = Find-Desktop $all
        if ($desktop.ProcessId -ne $DesktopPid -or (Get-CreatedTicks $desktop) -ne $ExpectedCreated.ToString()) {
            throw 'Desktop was replaced during window activation.'
        }
    }
    $tree = @(Get-SavedTree $all $desktop.ProcessId)
    $plan = [pscustomobject]@{ RootPid = [int]$desktop.ProcessId; RootCreated = Get-CreatedTicks $desktop
        Executable = $desktop.ExecutablePath; ThreadId = $ThreadId; Uri = "codex://threads/$ThreadId"; Tree = $tree }
    if ($Worker) {
        if ($tree.Pid -contains $PID) { throw 'Worker must be detached from the desktop tree.' }
        Invoke-RestartPlan $plan
        return
    }
    if (!$Execute) { $plan | ConvertTo-Json -Depth 6; return }
    if (!$LogPath) { $script:LogPath = Get-DefaultLogPath }
    $script:LogPath = [System.IO.Path]::GetFullPath($script:LogPath)
    $null = [System.IO.Directory]::CreateDirectory((Split-Path -Parent $script:LogPath))
    $powershell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    foreach ($path in @($PSCommandPath,$script:LogPath,$powershell)) {
        if ($path -match '["\r\n]') { throw 'Unsupported quote or newline in a launch path.' }
    }
    $command = '"' + $powershell + '" -NoProfile -NonInteractive -File "' + $PSCommandPath +
        '" -Worker -ThreadId ' + $ThreadId + ' -DesktopPid ' + $plan.RootPid +
        ' -ExpectedCreated ' + $plan.RootCreated + ' -DispatchDelaySeconds ' + $DispatchDelaySeconds +
        ' -LogPath "' + $script:LogPath + '"'
    if ($ForceClose) { $command += ' -ForceClose' }
    if ($AutomationId) { $command += ' -AutomationId ' + $AutomationId }
    $startup = New-CimInstance -ClassName Win32_ProcessStartup -ClientOnly -Property @{ ShowWindow = [uint16]0 }
    $result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = $command; CurrentDirectory = (Get-Location).Path; ProcessStartupInformation = $startup
    }
    if ($result.ReturnValue -ne 0) { throw "Detached worker launch failed: $($result.ReturnValue)" }
    @{ WorkerPid = $result.ProcessId; LogPath = $script:LogPath; Dispatched = $true } | ConvertTo-Json -Compress
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-Main }
    catch {
        if ($Worker -and $LogPath) { try { Write-Event 'failed' @{ Message = $_.Exception.Message } } catch {} }
        Write-Error $_.Exception.Message
        exit 1
    }
}
