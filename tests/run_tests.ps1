param([string]$Godot = "godot")
$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$totalChecks = 0
$failedSuites = @()
foreach ($testFile in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.gd' | Sort-Object Name)) {
    $testOutput = (& $Godot --headless --path $projectRoot --script $testFile.FullName 2>&1 | Out-String)
    $testExit = $LASTEXITCODE
    $summary = [regex]::Match($testOutput, '(?m)^.+: (\d+) checks, (\d+) failures\.')
    if ($summary.Success) { $totalChecks += [int]$summary.Groups[1].Value }
    if ($testExit -ne 0 -or $testOutput -match 'SCRIPT ERROR:|ERROR:' -or -not $summary.Success -or [int]$summary.Groups[2].Value -ne 0) {
        $failedSuites += $testFile.Name
        Write-Output $testOutput
    } else { Write-Output $summary.Value }
}
Write-Output "$totalChecks checks; $($failedSuites.Count) failed suites."
if ($failedSuites.Count -gt 0) { throw "Failed: $($failedSuites -join ', ')" }
