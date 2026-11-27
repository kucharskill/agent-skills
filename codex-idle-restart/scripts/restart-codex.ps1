<# Dry run by default. Eligibility checks belong to the invoking agent. #>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')]
    [string]$ThreadId,
    [switch]$Execute,
    [switch]$ForceClose,
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
    $record = @{ Time = [datetime]::UtcNow.ToString('o'); Event = $Event; Details = $Details }
    $line = ConvertTo-Json -InputObject $record -Depth 7 -Compress
    [System.IO.File]::AppendAllText($script:LogPath, $line + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Close-Desktop($Plan) {
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($Plan.RootPid)"
    if (!$current -or (Get-CreatedTicks $current) -ne $Plan.RootCreated) { throw 'Desktop root changed.' }
    $app = Get-Process -Id $Plan.RootPid
    $null = $app.Handle
    $attempt = 0
    # Two graceful requests: at the start and after 15 seconds. Allow 45 seconds total.
    foreach ($waitMs in @(15000, 30000)) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($Plan.RootPid)"
        if (!$current) { return }
        if ((Get-CreatedTicks $current) -ne $Plan.RootCreated) { throw 'Desktop root identity changed during graceful close.' }
        $app.Refresh()
        $accepted = $app.CloseMainWindow()
        $attempt++
        Write-Event 'graceful_close_request' @{ Pid = $Plan.RootPid; Attempt = $attempt; Accepted = $accepted; WaitMilliseconds = $waitMs }
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
    foreach ($saved in @($Plan.Tree | Where-Object { $_.Pid -ne $Plan.RootPid } | Sort-Object Depth -Descending)) {
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
        # Restore the visible app after a partial cleanup failure, without claiming success.
        Start-Sleep -Seconds 20
        Start-Desktop $Plan
        throw
    }
    Start-Sleep -Seconds 20
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
