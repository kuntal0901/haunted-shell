# Haunted Shell installer for Windows.
# Run from this folder:  powershell -ExecutionPolicy Bypass -File .\install.ps1
# Options: -Model qwen2.5:3b   (pick another model)
#          -SkipModel          (don't run 'ollama pull')

param(
    [string]$Model = 'llama3.2:3b',
    [switch]$SkipModel
)

$ErrorActionPreference = 'Stop'
$BlockStart = '# >>> haunted-shell >>>'
$BlockEnd = '# <<< haunted-shell <<<'

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }

function Test-Ollama {
    try {
        $request = [Net.HttpWebRequest]::Create('http://localhost:11434/api/tags')
        $request.Timeout = 2000
        $request.Proxy = $null
        $request.GetResponse().Close()
        return $true
    } catch { return $false }
}

function Remove-ProfileBlock([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $lines = @(Get-Content -LiteralPath $Path)
    $keep = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($line in $lines) {
        if ($line -eq $BlockStart) { $inside = $true; continue }
        if ($line -eq $BlockEnd) { $inside = $false; continue }
        if (-not $inside) { $keep.Add($line) }
    }
    Set-Content -LiteralPath $Path -Value $keep
}

Say ''
Say '  Haunted Shell installer' Magenta
Say '  ~ something stirs in the terminal ~' DarkMagenta
Say ''

# 1. Ollama ----------------------------------------------------------------
if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
    Say '[..] Ollama is not installed.' Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $answer = Read-Host '     Install it now with winget? (y/n)'
        if ($answer -eq 'y') {
            winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        }
    }
    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        Say '[x] Install Ollama from https://ollama.com/download/windows, then run this script again.' Red
        exit 1
    }
}
Say '[ok] Ollama is installed' Green

if (-not (Test-Ollama)) {
    Say '[..] Starting the Ollama server...' Yellow
    Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden
    for ($i = 0; $i -lt 30 -and -not (Test-Ollama); $i++) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-Ollama)) {
        Say '[x] Ollama did not start. Open the Ollama app from the Start menu, then run this script again.' Red
        exit 1
    }
}
Say '[ok] Ollama is running' Green

# 2. Model -----------------------------------------------------------------
if (-not $SkipModel) {
    Say "[..] Pulling $Model (about 2 GB the first time)..." Yellow
    & ollama pull $Model
    if ($LASTEXITCODE -ne 0) { Say "[x] 'ollama pull $Model' failed." Red; exit 1 }
    Say "[ok] Model $Model is ready" Green
}

# 3. Module (for both Windows PowerShell 5.1 and PowerShell 7) ---------------
$docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $docs) { $docs = Join-Path $HOME 'Documents' }
$source = Join-Path $PSScriptRoot 'HauntedShell'
foreach ($shellDir in @('WindowsPowerShell', 'PowerShell')) {
    $target = Join-Path $docs "$shellDir\Modules\HauntedShell"
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
    try { Get-ChildItem -LiteralPath $target -Recurse -File | Unblock-File } catch { }
}
Say '[ok] Module copied to your Documents\WindowsPowerShell and Documents\PowerShell folders' Green

# 4. Profile ---------------------------------------------------------------
$block = @(
    $BlockStart,
    "`$env:GHOST_MODEL = '$Model'",
    'Import-Module HauntedShell',
    $BlockEnd
)
foreach ($shellDir in @('WindowsPowerShell', 'PowerShell')) {
    $profilePath = Join-Path $docs "$shellDir\profile.ps1"
    New-Item -ItemType Directory -Path (Split-Path $profilePath) -Force | Out-Null
    Remove-ProfileBlock $profilePath
    Add-Content -LiteralPath $profilePath -Value $block
}
Say '[ok] Added Import-Module HauntedShell to your PowerShell profile' Green

# 5. Execution policy (profiles can't load while scripts are blocked) --------
# Look past the Process scope: running this script with -ExecutionPolicy Bypass hides the real policy.
$policy = 'Undefined'
foreach ($scope in @('MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine')) {
    $value = [string](Get-ExecutionPolicy -Scope $scope)
    if ($value -ne 'Undefined') { $policy = $value; break }
}
if ($policy -eq 'Undefined') { $policy = 'Restricted' }
if ($policy -eq 'Restricted' -or $policy -eq 'AllSigned') {
    Say "[..] Your execution policy is '$policy', which stops your profile from loading." Yellow
    $answer = Read-Host '     Set it to RemoteSigned for your user only? (y/n)'
    if ($answer -eq 'y') {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        Say '[ok] Execution policy set to RemoteSigned for your user' Green
    } else {
        Say '     Skipped. The ghost will not load until scripts are allowed.' Yellow
    }
}

Say ''
Say '  Done. Open a NEW PowerShell window and run:  Test-Ghost' Magenta
Say '  Then try a typo like  gti status  and press Enter twice.' DarkMagenta
Say ''
