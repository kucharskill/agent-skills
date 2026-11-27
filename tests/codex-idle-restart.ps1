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
        CreationDate = ([datetime]'2026-01-01T00:00:00Z').AddSeconds($Seconds) }
}

$processes = @((Fixture 100 1 10), (Fixture 101 100 11), (Fixture 102 100 12),
    (Fixture 103 101 13), (Fixture 104 100 14), (Fixture 999 100 1), (Fixture 200 2 20))
$tree = @(Get-SavedTree $processes 100)
Assert-Equal @($tree.Pid) @(100,101,102,104,103) 'snapshot includes descendants, excludes stale parent references and unrelated processes'
try { $null = Get-SavedTree $processes 12345; throw 'Expected missing-root failure' }
catch { if ($_.Exception.Message -notmatch 'Expected one desktop') { throw } }
Write-Output 'PASS: missing root is rejected'

# Mock OS mutations. These tests must not touch any actual process.
$script:live = @{ 101 = $processes[1]; 102 = (Fixture 102 100 50); 103 = $processes[3] }
$script:stopped = [System.Collections.Generic.List[int]]::new()
function Get-CimInstance { param($ClassName,$Filter); return $script:live[[int]($Filter -replace 'ProcessId=','')] }
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
Remove-Item Function:Get-CimInstance,Function:Get-Process,Function:Stop-Process

$script:events = [System.Collections.Generic.List[string]]::new()
function Write-Event { param($Event,$Details); $script:events.Add("log:$Event") }
function Close-Desktop { param($Plan); $script:events.Add('close') }
function Stop-SavedTree { param($Plan); $script:events.Add('kill-tree') }
function Start-Sleep { param($Seconds); $script:events.Add("delay:$Seconds") }
function Start-Desktop { param($Plan); $script:events.Add('launch') }
Invoke-RestartPlan $plan
Assert-Equal @($script:events.ToArray()) @('log:snapshot','close','log:closed','kill-tree','log:cleaned','delay:20','launch','log:launched') 'snapshot, close, cleanup, 20-second delay, launch occur in the requested order'

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
$fixtureRoot | Add-Member NoteProperty CommandLine '"ChatGPT.exe"'
$script:fixtureProcesses = @($fixtureRoot, (Fixture 101 100 11))
function Get-CimInstance { return $script:fixtureProcesses }
function New-CimInstance { param($ClassName,[switch]$ClientOnly,$Property); return $Property }
function Invoke-CimMethod {
    param($ClassName,$MethodName,$Arguments)
    $script:dispatch = $Arguments
    return @{ ReturnValue = 0; ProcessId = 424242 }
}
$script:ThreadId = '00000000-0000-0000-0000-000000000001'
$script:Execute = $true
$script:Worker = $false
$script:LogPath = Join-Path $PSScriptRoot '../.tmp/codex-idle-restart-tests/dispatch.jsonl'
$null = Invoke-Main
Assert-Equal $script:dispatch.ProcessStartupInformation.ShowWindow ([uint16]0) 'detached worker is hidden'
if ($script:dispatch.CommandLine -notmatch 'restart-codex\.ps1" -Worker' -or
    $script:dispatch.CommandLine -notmatch '-ExpectedCreated \d+' -or
    $script:dispatch.CommandLine -notmatch '-LogPath "') { throw 'Detached command is incomplete.' }
Write-Output 'PASS: detached dispatch carries the source script, root identity, thread, and quoted log path'
Write-Output 'All restart tests passed. No real process was closed, killed, or launched.'
