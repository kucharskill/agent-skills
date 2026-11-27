<# Dry run by default. Eligibility checks belong to the invoking agent. #>
[CmdletBinding()]
param(
    [ValidatePattern('^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')]
    [string]$ThreadId,
    [switch]$Execute,
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
        [pscustomobject]@{ Pid = [int]$item.ProcessId; ParentPid = [int]$item.ParentProcessId
            Created = Get-CreatedTicks $item; Name = $item.Name; Depth = $entry.Depth }
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
    if (!$app.CloseMainWindow()) { throw 'The desktop did not accept a close request.' }
    if (!$app.WaitForExit(30000)) { throw 'Desktop close was cancelled or timed out.' }
}

function Stop-SavedTree($Plan) {
    foreach ($saved in @($Plan.Tree | Where-Object { $_.Pid -ne $Plan.RootPid } | Sort-Object Depth -Descending)) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($saved.Pid)"
        if (!$current) { continue }
        if ((Get-CreatedTicks $current) -ne $saved.Created) { continue }
        $handle = Get-Process -Id $saved.Pid -ErrorAction SilentlyContinue
        if (!$handle) { continue }
        # Keep the original process handle for waiting, even if its numeric PID is later reused.
        $null = $handle.Handle
        try { Stop-Process -InputObject $handle -Force -ErrorAction Stop }
        catch { if (!$handle.HasExited) { throw } }
        if (!$handle.WaitForExit(5000)) { throw "Process did not exit: $($saved.Pid)" }
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
    Write-Event 'closed' $null
    try {
        Stop-SavedTree $Plan
        Write-Event 'cleaned' $null
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
    if (!$LogPath) { $script:LogPath = Join-Path (Get-Location).Path ('.tmp/codex-idle-restart/' + [guid]::NewGuid().ToString() + '.jsonl') }
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
