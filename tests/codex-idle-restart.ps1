$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../codex-idle-restart/scripts/restart-codex.ps1')

function Assert-Equal($Actual, $Expected, [string]$Label) {
    if (($Actual | ConvertTo-Json -Compress -Depth 8) -ne ($Expected | ConvertTo-Json -Compress -Depth 8)) {
        throw "Failed: $Label"
    }
    Write-Output "PASS: $Label"
}
function Fixture([int]$Id, [int]$Parent, [int]$Seconds) {
    [pscustomobject]@{ ProcessId = $Id; ParentProcessId = $Parent; Name = 'fixture.exe'
        CommandLine = 'node fixture.js --token example-secret'; WorkingSetSize = 1000; PrivatePageCount = 2000
        CreationDate = ([datetime]'2026-01-01T00:00:00Z').AddSeconds($Seconds) }
}

$processes = @((Fixture 100 1 10), (Fixture 101 100 11), (Fixture 102 100 12),
    (Fixture 103 101 13), (Fixture 104 100 14), (Fixture 999 100 1), (Fixture 200 2 20))
$tree = @(Get-SavedTree $processes 100)
Assert-Equal @($tree.Pid) @(100,101,102,104,103) 'snapshot includes descendants, excludes stale parent references and unrelated processes'
Assert-Equal $tree[0].CommandLine 'node fixture.js --token [REDACTED]' 'snapshot records commands with common credential flags redacted'
Assert-Equal (Protect-CommandLine 'node x.js --mcp-secret "example secret" --control-token-file settings.txt PASSWORD=example https://example.test/?token=example') 'node x.js --mcp-secret [REDACTED] --control-token-file settings.txt PASSWORD=[REDACTED] https://example.test/?token=[REDACTED]' 'command redaction preserves unrelated flags and masks quoted credentials and URL tokens'
Assert-Equal (Get-MemoryTotals $tree).WorkingSetBytes ([long]5000) 'snapshot totals working sets'
Assert-Equal (Get-MemoryTotals $tree).PrivateBytes ([long]10000) 'snapshot totals private committed bytes separately'
Assert-Equal (Get-MemoryTotals @()).Count 0 'empty survivor list has zero processes'
$defaultLog = Get-DefaultLogPath
if (!$defaultLog.StartsWith([System.IO.Path]::GetTempPath()) -or $defaultLog -notmatch 'codex-idle-restart[\\/]restart-.*\.jsonl$') { throw 'Default log must be under system TEMP.' }
Write-Output 'PASS: default log path uses system TEMP without creating a file'
try { $null = Get-SavedTree $processes 12345; throw 'Expected missing-root failure' }
catch { if ($_.Exception.Message -notmatch 'Expected one desktop') { throw } }
Write-Output 'PASS: missing root is rejected'

# Mock OS mutations. These tests must not touch any actual process.
$script:live = @{ 101 = $processes[1]; 102 = (Fixture 102 100 50); 103 = $processes[3] }
$script:stopped = [System.Collections.Generic.List[int]]::new()
$script:cleanupEvents = [System.Collections.Generic.List[object]]::new()
function Write-Event { param($Event,$Details); $script:cleanupEvents.Add($Details) }
function Get-CimInstance {
    param($ClassName,$Filter)
    if (!$Filter) { return @($script:live.Values) }
    return $script:live[[int]($Filter -replace 'ProcessId=','')]
}
function Get-Process {
    param($Id,$ErrorAction)
    $fake = [pscustomobject]@{ Id = [int]$Id; Handle = 1; HasExited = $false }
    $fake | Add-Member ScriptMethod WaitForExit { param($Timeout); return $true }
    return $fake
}
function Stop-Process { param($InputObject,[switch]$Force,$ErrorAction); $script:stopped.Add($InputObject.Id) }
$plan = [pscustomobject]@{ RootPid = 100; Tree = $tree; ThreadId = '00000000-0000-0000-0000-000000000001' }
Stop-SavedTree $plan
Assert-Equal @($script:stopped.ToArray()) @(103,101) 'cleanup is child-first and skips exited processes, reused PIDs, root, and unrelated processes'
Assert-Equal @($script:cleanupEvents | Where-Object Action -eq 'terminated' | ForEach-Object { $_.Process.Pid }) @(103,101) 'cleanup log identifies forced terminations'
Assert-Equal @($script:cleanupEvents | Where-Object Action -eq 'pid_reused' | ForEach-Object { $_.Pid }) @(102) 'cleanup log identifies reused PIDs'
Assert-Equal @((Get-SavedSurvivors $plan).Pid | Sort-Object) @(101,103) 'survivor measurements match process identity, not just PID'
Remove-Item Function:Get-CimInstance,Function:Get-Process,Function:Stop-Process

$script:events = [System.Collections.Generic.List[string]]::new()
$script:eventDetails = @{}
function Write-Event { param($Event,$Details); $script:events.Add("log:$Event"); $script:eventDetails[$Event] = $Details }
function Close-Desktop { param($Plan); $script:events.Add('close') }
function Stop-SavedTree { param($Plan); $script:events.Add('kill-tree') }
function Start-Sleep { param($Seconds); $script:events.Add("delay:$Seconds") }
function Start-Desktop { param($Plan); $script:events.Add('launch') }
$script:survivorCalls = 0
function Get-SavedSurvivors {
    param($Plan)
    $script:survivorCalls++
    if ($script:survivorCalls -eq 1) { return [pscustomobject]@{ Pid = 101; WorkingSetBytes = 200; PrivateBytes = 400 } }
    return @()
}
Invoke-RestartPlan $plan
Assert-Equal @($script:events.ToArray()) @('log:snapshot','close','log:closed','kill-tree','log:cleaned','delay:20','launch','log:launched') 'snapshot, close, cleanup, 20-second delay, launch occur in the requested order'
Assert-Equal $script:eventDetails.cleaned.WorkingSetDecreaseBytes ([long]5000) 'log reports saved-tree memory decrease before relaunch'
Assert-Equal $script:eventDetails.cleaned.CleanupWorkingSetDecreaseBytes ([long]200) 'log separates remaining-process cleanup from normal desktop closure'
Assert-Equal $script:eventDetails.cleaned.AfterCleanup.Count 0 'log records no remaining saved process identities'

$script:events.Clear()
function Close-Desktop { param($Plan); throw 'cancelled' }
try { Invoke-RestartPlan $plan; throw 'Expected cancellation' }
catch { if ($_.Exception.Message -ne 'cancelled') { throw } }
Assert-Equal @($script:events.ToArray()) @('log:snapshot') 'cancelled close prevents cleanup and launch'

$script:events.Clear()
function Close-Desktop { param($Plan); $script:events.Add('close') }
function Stop-SavedTree { param($Plan); throw 'access denied' }
try { Invoke-RestartPlan $plan; throw 'Expected cleanup failure' }
catch { if ($_.Exception.Message -ne 'access denied') { throw } }
Assert-Equal @($script:events.ToArray()) @('log:snapshot','close','log:closed','log:cleanup_failed','delay:20','launch') 'cleanup failure restores the app after 20 seconds without claiming a clean restart'

# Exercise dispatch with mocked WMI, without creating any worker.
. (Join-Path $PSScriptRoot '../codex-idle-restart/scripts/restart-codex.ps1')
$fixtureRoot = Fixture 100 1 10
$fixtureRoot.Name = 'ChatGPT.exe'
$fixtureRoot | Add-Member NoteProperty ExecutablePath 'C:\Program Files\WindowsApps\OpenAI.Codex_TEST\app\ChatGPT.exe'
$fixtureRoot.CommandLine = '"ChatGPT.exe"'
$script:fixtureProcesses = @($fixtureRoot, (Fixture 101 100 11))
function Get-CimInstance { return $script:fixtureProcesses }
function New-CimInstance { param($ClassName,[switch]$ClientOnly,$Property); return $Property }
function Invoke-CimMethod {
    param($ClassName,$MethodName,$Arguments)
    $script:dispatch = $Arguments
    return @{ ReturnValue = 0; ProcessId = 424242 }
}
$script:ThreadId = '00000000-0000-0000-0000-000000000001'
$script:Execute = $false
$script:Worker = $false
$script:LogPath = Join-Path $PSScriptRoot ('../.tmp/codex-idle-restart-tests/dry-' + [guid]::NewGuid().ToString() + '/log.jsonl')
$dry = Invoke-Main | ConvertFrom-Json
Assert-Equal $dry.RootPid 100 'dry run still returns the process snapshot'
Assert-Equal (Test-Path -LiteralPath (Split-Path -Parent $script:LogPath)) $false 'dry run does not create a log file or directory'
$script:Execute = $true
$script:Worker = $false
$script:LogPath = Join-Path $PSScriptRoot '../.tmp/codex-idle-restart-tests/dispatch.jsonl'
$null = Invoke-Main
Assert-Equal $script:dispatch.ProcessStartupInformation.ShowWindow ([uint16]0) 'detached worker is hidden'
if ($script:dispatch.CommandLine -notmatch 'restart-codex\.ps1" -Worker' -or
    $script:dispatch.CommandLine -notmatch '-ExpectedCreated \d+' -or
    $script:dispatch.CommandLine -notmatch '-LogPath "') { throw 'Detached command is incomplete.' }
Write-Output 'PASS: detached dispatch carries the source script, root identity, thread, and quoted log path'
Write-Event 'synthetic_test' @{ CommandLine = Protect-CommandLine 'node test.js --token synthetic'; Memory = Get-MemoryTotals $tree }
$logged = Get-Content -LiteralPath $script:LogPath -Tail 1 | ConvertFrom-Json
Assert-Equal $logged.Details.CommandLine 'node test.js --token [REDACTED]' 'JSONL log round-trips commands without common credential values'
Assert-Equal $logged.Details.Memory.PrivateBytes ([long]10000) 'JSONL log preserves byte totals'
Write-Output 'All restart tests passed. No real process was closed, killed, or launched.'
