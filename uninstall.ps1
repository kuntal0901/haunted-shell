# Haunted Shell uninstaller.
# Run from this folder:  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
# Ollama and the models stay installed. Remove a model with: ollama rm llama3.2:3b

$BlockStart = '# >>> haunted-shell >>>'
$BlockEnd = '# <<< haunted-shell <<<'
$docs = [Environment]::GetFolderPath('MyDocuments')
if (-not $docs) { $docs = Join-Path $HOME 'Documents' }

foreach ($shellDir in @('WindowsPowerShell', 'PowerShell')) {
    $profilePath = Join-Path $docs "$shellDir\profile.ps1"
    if (Test-Path -LiteralPath $profilePath) {
        $keep = New-Object System.Collections.Generic.List[string]
        $inside = $false
        foreach ($line in @(Get-Content -LiteralPath $profilePath)) {
            if ($line -eq $BlockStart) { $inside = $true; continue }
            if ($line -eq $BlockEnd) { $inside = $false; continue }
            if (-not $inside) { $keep.Add($line) }
        }
        Set-Content -LiteralPath $profilePath -Value $keep
    }
    $target = Join-Path $docs "$shellDir\Modules\HauntedShell"
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
}

Remove-Module HauntedShell -ErrorAction SilentlyContinue
Write-Host 'The ghost has been laid to rest. Open a new PowerShell window to see your old prompt.' -ForegroundColor DarkMagenta
