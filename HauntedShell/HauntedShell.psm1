# HauntedShell - a ghost possesses your PowerShell prompt.
# Every whisper comes from an open-weight model running locally in Ollama.
# Works on Windows PowerShell 5.1 and PowerShell 7. Keep this file ASCII-only
# so Windows PowerShell 5.1 reads it correctly without a BOM.

# ---------------------------------------------------------------- settings --

function Get-EnvOrDefault([string]$Name, [string]$Default) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value
}

$script:Ghost = [ordered]@{
    Enabled        = $true
    Model          = Get-EnvOrDefault 'GHOST_MODEL' 'llama3.2:3b'
    Url            = (Get-EnvOrDefault 'GHOST_URL' 'http://localhost:11434').TrimEnd('/')
    Chance         = [double](Get-EnvOrDefault 'GHOST_CHANCE' '1')
    WaitSec        = [double](Get-EnvOrDefault 'GHOST_WAIT' '15')
    Calavera       = (Get-EnvOrDefault 'GHOST_CALAVERA' '1') -ne '0'
    CalaveraChance = [double](Get-EnvOrDefault 'GHOST_CALAVERA_CHANCE' '0.5')
    TimeoutSec     = [int](Get-EnvOrDefault 'GHOST_TIMEOUT' '20')
    Color          = Get-EnvOrDefault 'GHOST_COLOR' 'Magenta'
    Ignore         = Get-EnvOrDefault 'GHOST_IGNORE' ''
}

$script:Prompts = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'prompts.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# Commands that look like they carry secrets are never sent, not even to the local model.
$script:SecretPattern = '(?i)(pass(word|wd)?\b|secret|token|api[_-]?key|bearer|authorization|credential|private[_-]?key|securestring|-----BEGIN|ssh-rsa|connectionstring)|[A-Za-z0-9+/_\-]{32,}'

# The ghost's own commands and screen clearing are not worth haunting.
$script:SkipPattern = '^(summon|banish|ofrenda|Enable-Ghost|Disable-Ghost|Set-GhostConfig|Get-GhostConfig|Enable-Calavera|Disable-Calavera|Show-Ofrenda|Test-Ghost|Import-Module|Remove-Module|cls|clear|exit)\b'

# Well-known commands, used to guess what a typo really meant.
$script:CommonNames = @(
    'git', 'npm', 'npx', 'node', 'python', 'py', 'pip', 'docker', 'code', 'ollama', 'winget', 'choco',
    'cd', 'ls', 'dir', 'cat', 'echo', 'mkdir', 'rm', 'cp', 'mv', 'pwd', 'cls', 'clear', 'curl', 'ssh',
    'Get-ChildItem', 'Set-Location', 'Get-Content', 'Set-Content', 'Get-Process', 'Stop-Process',
    'Get-Service', 'Get-Help', 'Get-Command', 'Select-String', 'Where-Object', 'ForEach-Object',
    'Copy-Item', 'Move-Item', 'Remove-Item', 'New-Item', 'Invoke-WebRequest', 'Test-Path', 'Write-Host'
)

# ------------------------------------------------------------------- state --

$script:Job = $null
$script:Runspace = $null
$script:OriginalPrompt = $null
$script:WarnedDown = $false
$script:Rng = New-Object System.Random
$script:Recent = New-Object System.Collections.Generic.List[string]
$script:Dead = New-Object System.Collections.Generic.List[string]
$script:LastHistoryId = 0
$lastHistory = Get-History -Count 1
if ($lastHistory) { $script:LastHistoryId = $lastHistory.Id }
$script:LastErrorRef = $null
if ($global:Error.Count -gt 0) { $script:LastErrorRef = $global:Error[0] }

# ------------------------------------------------------------------ worker --

# Runs on a background runspace, so it cannot see anything in this module.
# Everything it needs comes in as parameters; it always returns one object.
$script:WorkerScript = {
    param($Url, $Model, $System, $Prompt, $NumPredict, $TimeoutSec, $Temperature, $Typed, $Names)

    # Edit distance with swaps (gti -> git is 1). A flat array and plain
    # index variables keep it parseable by Windows PowerShell 5.1.
    function Get-Distance([string]$a, [string]$b) {
        $n = $a.Length
        $m = $b.Length
        $w = $m + 1
        $d = New-Object 'int[]' (($n + 1) * $w)
        for ($i = 0; $i -le $n; $i++) { $d[$i * $w] = $i }
        for ($j = 0; $j -le $m; $j++) { $d[$j] = $j }
        for ($i = 1; $i -le $n; $i++) {
            for ($j = 1; $j -le $m; $j++) {
                $here = $i * $w + $j
                $up = $here - $w
                $left = $here - 1
                $diag = $up - 1
                $cost = 1
                if ($a.Substring($i - 1, 1) -ceq $b.Substring($j - 1, 1)) { $cost = 0 }
                $best = $d[$up] + 1
                $other = $d[$left] + 1
                if ($other -lt $best) { $best = $other }
                $other = $d[$diag] + $cost
                if ($other -lt $best) { $best = $other }
                if ($i -gt 1 -and $j -gt 1) {
                    if ($a.Substring($i - 1, 1) -ceq $b.Substring($j - 2, 1) -and $a.Substring($i - 2, 1) -ceq $b.Substring($j - 1, 1)) {
                        $other = $d[$diag - $w - 1] + 1
                        if ($other -lt $best) { $best = $other }
                    }
                }
                $d[$here] = $best
            }
        }
        return $d[$n * $w + $m]
    }

    try {
        # Typo possession: find the closest real command before asking the model.
        if ($Typed) {
            $candidates = New-Object System.Collections.Generic.List[string]
            foreach ($name in $Names) { $candidates.Add([string]$name) }
            $exts = @()
            if ($env:PATHEXT) { $exts = $env:PATHEXT.ToLower().Split(';') }
            foreach ($dir in $env:PATH.Split([IO.Path]::PathSeparator)) {
                if (-not $dir -or -not [IO.Directory]::Exists($dir)) { continue }
                try { $files = [IO.Directory]::GetFiles($dir) } catch { continue }
                foreach ($file in $files) {
                    if ($exts.Count -gt 0) {
                        if ($exts -contains [IO.Path]::GetExtension($file).ToLower()) {
                            $candidates.Add([IO.Path]::GetFileNameWithoutExtension($file))
                        }
                    } else {
                        $candidates.Add([IO.Path]::GetFileName($file))
                    }
                }
            }
            $typedLower = $Typed.ToLower()
            $bestName = $null; $bestScore = [int]::MaxValue
            foreach ($candidate in $candidates) {
                $lower = $candidate.ToLower()
                if ($lower -eq $typedLower) { continue }
                if ([Math]::Abs($lower.Length - $typedLower.Length) -gt 2) { continue }
                $score = Get-Distance $typedLower $lower
                if ($score -lt $bestScore) { $bestScore = $score; $bestName = $candidate }
            }
            $limit = [Math]::Max(1, [Math]::Floor($typedLower.Length / 3))
            $guess = ''
            if ($bestName -and $bestScore -le $limit) { $guess = "They almost certainly meant '$bestName'." }
            $Prompt = $Prompt.Replace('{guess}', $guess)
        }

        $payload = @{
            model      = $Model
            prompt     = $Prompt
            stream     = $false
            keep_alive = '30m'
            options    = @{ num_predict = $NumPredict; temperature = $Temperature; top_p = 0.95 }
        }
        if ($System) { $payload.system = $System }
        $bytes = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 5 -Compress))

        $request = [Net.HttpWebRequest]::Create("$Url/api/generate")
        $request.Method = 'POST'
        $request.ContentType = 'application/json; charset=utf-8'
        $request.Timeout = $TimeoutSec * 1000
        $request.ReadWriteTimeout = $TimeoutSec * 1000
        $request.Proxy = $null
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Close()

        $response = $request.GetResponse()
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd()
        $reader.Close(); $response.Close()

        $answer = $body | ConvertFrom-Json
        return [pscustomobject]@{ Ok = $true; Text = [string]$answer.response; Error = $null }
    } catch {
        return [pscustomobject]@{ Ok = $false; Text = $null; Error = $_.Exception.Message }
    }
}

function Get-GhostRunspace {
    if ($script:Runspace -and $script:Runspace.RunspaceAvailability -eq 'Available') { return $script:Runspace }
    if ($script:Runspace) { try { $script:Runspace.Dispose() } catch { } }
    $script:Runspace = [runspacefactory]::CreateRunspace()
    $script:Runspace.Open()
    return $script:Runspace
}

function Start-GhostJob {
    param([string]$Kind, [string]$System, [string]$Prompt, [int]$NumPredict = 60,
          [string]$Command = '', [string]$Typed = '', [int]$TimeoutSec = 0, [double]$Temperature = 0.9)
    if ($script:Job -and $script:Job.Kind -eq 'warmup') {
        # Let the warm-up finish on its own; it only loads the model.
        $script:Job = $null
        $script:Runspace = $null
    }
    if ($script:Job) { return }
    if ($TimeoutSec -le 0) { $TimeoutSec = $script:Ghost.TimeoutSec }
    $names = @()
    if ($Typed) { $names = @($script:CommonNames) + @(Get-Alias | ForEach-Object Name) + @(Get-ChildItem function: | ForEach-Object Name) }
    $ps = [powershell]::Create()
    $ps.Runspace = Get-GhostRunspace
    [void]$ps.AddScript($script:WorkerScript.ToString()).AddParameters(@{
        Url = $script:Ghost.Url; Model = $script:Ghost.Model; System = $System; Prompt = $Prompt
        NumPredict = $NumPredict; TimeoutSec = $TimeoutSec; Temperature = $Temperature
        Typed = $Typed; Names = [string[]]$names
    })
    $script:Job = @{
        PS = $ps; Handle = $ps.BeginInvoke(); Kind = $Kind; Command = $Command
        Started = Get-Date; TimeoutSec = $TimeoutSec
    }
}

# Collects a finished whisper, if any, and prints it. Never waits.
function Receive-GhostJob {
    $job = $script:Job
    if (-not $job) { return }
    if (-not $job.Handle.IsCompleted) {
        if (((Get-Date) - $job.Started).TotalSeconds -gt ($job.TimeoutSec + 5)) {
            try { [void]$job.PS.BeginStop($null, $null) } catch { }
            $script:Runspace = $null
            $script:Job = $null
        }
        return
    }
    $script:Job = $null
    $result = $null
    try { $result = $job.PS.EndInvoke($job.Handle) | Select-Object -Last 1 } catch { }
    $job.PS.Dispose()

    if (-not $result -or -not $result.Ok) {
        if (-not $script:WarnedDown) {
            $script:WarnedDown = $true
            $reason = 'no answer'
            if ($result) { $reason = $result.Error }
            Write-Host "  (the ghost cannot reach Ollama at $($script:Ghost.Url): $reason. Run Test-Ghost for help.)" -ForegroundColor DarkGray
        }
        return
    }
    $script:WarnedDown = $false
    switch ($job.Kind) {
        'warmup'   { }
        'calavera' { Write-GhostCalavera -Command $job.Command -Text $result.Text }
        default    { Write-GhostWhisper -Text $result.Text }
    }
}

# --------------------------------------------------------------- printing --

function Format-GhostText([string]$Text, [int]$MaxLines = 1) {
    if (-not $Text) { return @() }
    # Drop emoji and markdown stars: Windows PowerShell 5.1 consoles show emoji as '??'.
    $clean = $Text -replace '[\uD800-\uDFFF\u2600-\u27BF\uFE0F\u200D]', '' -replace '\*', ''
    $lines = @($clean -split "`r?`n" | ForEach-Object {
        $_.Trim().Trim('"', [char]0x201C, [char]0x201D) -replace '^(ghost|the ghost)\s*:\s*', ''
    } | Where-Object { $_ })
    if ($lines.Count -gt $MaxLines) { $lines = $lines[0..($MaxLines - 1)] }
    return , $lines
}

function Write-GhostWhisper([string]$Text) {
    $line = Format-GhostText $Text 1
    if ($line.Count -eq 0) { return }
    $words = $line[0]
    if ($words.Length -gt 220) { $words = $words.Substring(0, 217) + '...' }
    Write-Host "  ~ $words" -ForegroundColor $script:Ghost.Color
}

function Write-GhostCalavera([string]$Command, [string]$Text) {
    $lines = Format-GhostText $Text 4
    if ($lines.Count -eq 0) { return }
    $name = $Command
    if ($name.Length -gt 40) { $name = $name.Substring(0, 37) + '...' }
    Write-Host ''
    Write-Host "    +  R.I.P.  $name  +" -ForegroundColor DarkGray
    foreach ($line in $lines) { Write-Host "    $line" -ForegroundColor $script:Ghost.Color }
    Write-Host ''
}

function Write-GhostNote([string]$Text) {
    Write-Host "  $Text" -ForegroundColor DarkGray
}

# ------------------------------------------------------------ prompt hook --

function Test-GhostSecret([string]$Text) {
    if ($Text -match $script:SecretPattern) { return $true }
    if ($script:Ghost.Ignore -and $Text -match $script:Ghost.Ignore) { return $true }
    return $false
}

function Invoke-GhostTick([bool]$LastOk, $LastExit) {
    if (-not $script:Ghost.Enabled) { return }
    Receive-GhostJob

    $history = Get-History -Count 1
    if (-not $history -or $history.Id -eq $script:LastHistoryId) {
        # An empty Enter: let the user know a whisper is on its way.
        if ($script:Job -and $script:Job.Kind -ne 'warmup') { Write-GhostNote '...the ghost is still whispering...' }
        return
    }
    $script:LastHistoryId = $history.Id

    $newError = $null
    if ($global:Error.Count -gt 0 -and -not [object]::ReferenceEquals($global:Error[0], $script:LastErrorRef)) {
        $newError = $global:Error[0]
    }
    if ($global:Error.Count -gt 0) { $script:LastErrorRef = $global:Error[0] } else { $script:LastErrorRef = $null }

    $command = ($history.CommandLine -replace '\s+', ' ').Trim()
    if (-not $command -or $command -match $script:SkipPattern) { return }
    if (Test-GhostSecret $command) { return }
    if ($command.Length -gt 300) { $command = $command.Substring(0, 300) + '...' }

    $failed = (-not $LastOk) -or ($null -ne $newError)
    $exit = 'it failed'
    if ($LastExit -and $LastExit -ne 0 -and -not $newError) { $exit = "exit code $LastExit" }
    if ($newError) {
        $message = ($newError.Exception.Message -split "`r?`n")[0]
        if ($message.Length -gt 160) { $message = $message.Substring(0, 160) }
        if (-not (Test-GhostSecret $message)) { $exit = "error: $message" }
    }

    $recentText = ''
    if ($script:Recent.Count -gt 0) { $recentText = 'Earlier commands: ' + ($script:Recent -join ' | ') }
    $script:Recent.Add($command)
    while ($script:Recent.Count -gt 3) { $script:Recent.RemoveAt(0) }
    if ($failed) { $script:Dead.Add($command) }

    if ($script:Job -and $script:Job.Kind -ne 'warmup') { return }   # One ghost at a time.

    $p = $script:Prompts
    if ($newError -and $newError.FullyQualifiedErrorId -like 'CommandNotFoundException*') {
        $typed = [string]$newError.TargetObject
        if (-not $typed) { $typed = ($command -split ' ')[0] }
        Start-GhostJob -Kind 'possession' -System $p.system -Prompt $p.possession.Replace('{typed}', $typed) -Typed $typed -NumPredict 50
    } elseif ($failed -and $script:Ghost.Calavera -and $script:Rng.NextDouble() -lt $script:Ghost.CalaveraChance) {
        $text = $p.calavera.Replace('{command}', $command).Replace('{exit}', $exit)
        Start-GhostJob -Kind 'calavera' -System $p.calavera_system -Prompt $text -Command $command -NumPredict 90 -TimeoutSec ($script:Ghost.TimeoutSec + 15)
    } elseif ($failed) {
        $text = $p.whisper_fail.Replace('{command}', $command).Replace('{exit}', $exit).Replace('{recent}', $recentText)
        Start-GhostJob -Kind 'whisper' -System $p.system -Prompt $text -NumPredict 50
    } elseif ($script:Rng.NextDouble() -lt $script:Ghost.Chance) {
        $text = $p.whisper_ok.Replace('{command}', $command).Replace('{recent}', $recentText)
        Start-GhostJob -Kind 'whisper' -System $p.system -Prompt $text -NumPredict 50
    }
    Wait-GhostJob
}

# Holds the prompt for a few seconds so the whisper lands right under the
# command it is about. Any key skips the wait; the whisper then shows later.
function Wait-GhostJob {
    $job = $script:Job
    if (-not $job -or $job.Kind -eq 'warmup' -or $script:Ghost.WaitSec -le 0) { return }
    $frames = @('.  ', '.. ', '...')
    $frame = 0
    $label = '  ~ the ghost stirs'
    while (-not $job.Handle.IsCompleted) {
        if (((Get-Date) - $job.Started).TotalSeconds -ge $script:Ghost.WaitSec) { break }
        $skip = $false
        try { $skip = [Console]::KeyAvailable } catch { }
        if ($skip) { break }
        Write-Host ("`r" + $label + $frames[$frame % 3]) -NoNewline -ForegroundColor DarkGray
        $frame++
        Start-Sleep -Milliseconds 150
    }
    if ($frame -gt 0) { Write-Host ("`r" + (' ' * ($label.Length + 3)) + "`r") -NoNewline }
    Receive-GhostJob
}

$script:GhostPrompt = {
    $ghostOk = $global:?
    $ghostExit = $global:LASTEXITCODE
    $ghostErrors = $global:Error.Count
    try { Invoke-GhostTick -LastOk $ghostOk -LastExit $ghostExit } catch { }
    # Errors the ghost caught itself must not land in your $Error or look like a failed command.
    while ($global:Error.Count -gt $ghostErrors) { $global:Error.RemoveAt(0) }
    $global:LASTEXITCODE = $ghostExit
    # Hand the original prompt the same $? it would have seen (oh-my-posh and
    # Starship colour the prompt by it). A failed no-op sets $? to false.
    if (-not $ghostOk) { Write-Error -Message 'ghost' -ErrorAction Ignore }
    if ($script:OriginalPrompt) { & $script:OriginalPrompt } else { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
}

function Install-GhostPrompt {
    if ($script:OriginalPrompt) { return }
    $current = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
    if ($current) { $script:OriginalPrompt = $current.ScriptBlock }
    else { $script:OriginalPrompt = { "PS $($executionContext.SessionState.Path.CurrentLocation)> " } }
    Set-Item -Path function:global:prompt -Value $script:GhostPrompt
}

# Prompt themes such as oh-my-posh and Starship often load after this module
# and replace the prompt function. Whenever the shell is idle, wrap the new
# prompt again so the ghost survives them.
function Repair-GhostPrompt {
    if (-not $script:Ghost.Enabled) { return }
    $current = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
    if ($current -and $current.ScriptBlock.ToString().Contains('Invoke-GhostTick')) { return }
    $script:OriginalPrompt = $null
    Install-GhostPrompt
}

$script:IdleWatch = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    $ghostModule = Get-Module HauntedShell
    if ($ghostModule) { & $ghostModule { Repair-GhostPrompt } }
}

function Uninstall-GhostPrompt {
    if (-not $script:OriginalPrompt) { return }
    Set-Item -Path function:global:prompt -Value $script:OriginalPrompt
    $script:OriginalPrompt = $null
}

# --------------------------------------------------------------- commands --

function Enable-Ghost {
    <#
    .SYNOPSIS
    Summons the ghost into this terminal (alias: summon).
    #>
    $script:Ghost.Enabled = $true
    Install-GhostPrompt
    Start-GhostJob -Kind 'warmup' -System '' -Prompt '' -NumPredict 1 -TimeoutSec 180
    Write-GhostNote 'A cold draft moves through the terminal. The ghost is here. (banish to send it away)'
}

function Disable-Ghost {
    <#
    .SYNOPSIS
    Banishes the ghost and restores your normal prompt (alias: banish).
    #>
    $script:Ghost.Enabled = $false
    Uninstall-GhostPrompt
    Write-GhostNote 'The candles gutter out. The ghost is gone... for now.'
}

function Enable-Calavera { $script:Ghost.Calavera = $true; Write-GhostNote 'Calavera mode on: failed commands may earn a rhyming epitaph.' }
function Disable-Calavera { $script:Ghost.Calavera = $false; Write-GhostNote 'Calavera mode off.' }

function Get-GhostConfig { [pscustomobject]$script:Ghost }

function Set-GhostConfig {
    <#
    .SYNOPSIS
    Changes the ghost's settings for this session. Put $env:GHOST_* lines in your profile to keep them.
    .EXAMPLE
    Set-GhostConfig -Model qwen2.5:3b -Chance 0.5
    #>
    param([string]$Model, [string]$Url, [double]$Chance = -1, [double]$CalaveraChance = -1, [int]$TimeoutSec = 0, [double]$WaitSec = -1, [string]$Color)
    if ($Model) { $script:Ghost.Model = $Model }
    if ($Url) { $script:Ghost.Url = $Url.TrimEnd('/') }
    if ($Chance -ge 0) { $script:Ghost.Chance = $Chance }
    if ($CalaveraChance -ge 0) { $script:Ghost.CalaveraChance = $CalaveraChance }
    if ($TimeoutSec -gt 0) { $script:Ghost.TimeoutSec = $TimeoutSec }
    if ($WaitSec -ge 0) { $script:Ghost.WaitSec = $WaitSec }
    if ($Color) { $script:Ghost.Color = $Color }
    Get-GhostConfig
}

function Invoke-GhostNow([string]$System, [string]$Prompt, [int]$NumPredict, [int]$TimeoutSec) {
    & $script:WorkerScript -Url $script:Ghost.Url -Model $script:Ghost.Model -System $System -Prompt $Prompt `
        -NumPredict $NumPredict -TimeoutSec $TimeoutSec -Temperature 0.9 -Typed '' -Names @()
}

function Show-Ofrenda {
    <#
    .SYNOPSIS
    Builds a small ofrenda for the commands that died in this session (alias: ofrenda).
    #>
    $p = $script:Prompts
    $dead = @($script:Dead | Select-Object -Unique | Select-Object -Last 12)
    Write-Host ''
    Write-Host '        *   i   *   i   *   i   *   i   *' -ForegroundColor DarkYellow
    Write-Host '      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~' -ForegroundColor DarkGray
    if ($dead.Count -eq 0) {
        $result = Invoke-GhostNow -System $p.system -Prompt $p.ofrenda_empty -NumPredict 50 -TimeoutSec 60
        if ($result.Ok) { Write-GhostWhisper $result.Text } else { Write-GhostNote "The ghost is silent: $($result.Error)" }
        Write-Host ''
        return
    }
    Write-Host '        En memoria de:' -ForegroundColor DarkGray
    foreach ($command in $dead) { Write-Host "          + $command" -ForegroundColor Gray }
    Write-Host ''
    Write-GhostNote 'Lighting the candles...'
    $result = Invoke-GhostNow -System $p.ofrenda_system -Prompt $p.ofrenda.Replace('{dead}', ($dead -join "`n")) -NumPredict 140 -TimeoutSec 90
    if (-not $result.Ok) { Write-GhostNote "The candles will not light: $($result.Error)"; return }
    foreach ($line in (Format-GhostText $result.Text 6)) { Write-Host "        $line" -ForegroundColor $script:Ghost.Color }
    Write-Host '      ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~' -ForegroundColor DarkGray
    Write-Host '        *   i   *   i   *   i   *   i   *' -ForegroundColor DarkYellow
    Write-Host ''
}

function Test-Ghost {
    <#
    .SYNOPSIS
    Checks that Ollama is running, the model is pulled, and times one whisper.
    #>
    $url = $script:Ghost.Url
    $model = $script:Ghost.Model
    Write-Host "Ollama URL : $url"
    Write-Host "Model      : $model"
    try {
        $request = [Net.HttpWebRequest]::Create("$url/api/tags")
        $request.Timeout = 3000
        $request.Proxy = $null
        $response = $request.GetResponse()
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        $tags = $reader.ReadToEnd() | ConvertFrom-Json
        $reader.Close(); $response.Close()
    } catch {
        Write-Host "[x] Ollama is not answering. Start the Ollama app (or run 'ollama serve') and try again." -ForegroundColor Red
        return
    }
    Write-Host '[ok] Ollama is running' -ForegroundColor Green
    $names = @($tags.models | ForEach-Object { $_.name })
    $wanted = $model
    if ($wanted -notmatch ':') { $wanted = "$wanted`:latest" }
    if ($names -notcontains $wanted) {
        Write-Host "[x] Model '$model' is not pulled. Run: ollama pull $model" -ForegroundColor Red
        if ($names.Count -gt 0) { Write-Host "    Models you have: $($names -join ', ')" }
        return
    }
    Write-Host "[ok] Model '$model' is available" -ForegroundColor Green
    Write-Host '... asking the ghost (the first call loads the model and can take a while)'
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $prompt = $script:Prompts.whisper_ok.Replace('{command}', 'Test-Ghost').Replace('{recent}', '')
    $result = Invoke-GhostNow -System $script:Prompts.system -Prompt $prompt -NumPredict 50 -TimeoutSec 180
    $watch.Stop()
    if (-not $result.Ok) { Write-Host "[x] The model did not answer: $($result.Error)" -ForegroundColor Red; return }
    Write-GhostWhisper $result.Text
    Write-Host ('[ok] Whisper took {0:N1} s' -f $watch.Elapsed.TotalSeconds) -ForegroundColor Green
}

Set-Alias -Name summon -Value Enable-Ghost
Set-Alias -Name banish -Value Disable-Ghost
Set-Alias -Name ofrenda -Value Show-Ofrenda

$ExecutionContext.SessionState.Module.OnRemove = {
    if ($script:IdleWatch) { Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue; Remove-Job -Job $script:IdleWatch -Force -ErrorAction SilentlyContinue }
    Uninstall-GhostPrompt
    if ($script:Runspace) { try { $script:Runspace.Dispose() } catch { } }
}

Export-ModuleMember -Function Enable-Ghost, Disable-Ghost, Enable-Calavera, Disable-Calavera, Get-GhostConfig,
    Set-GhostConfig, Show-Ofrenda, Test-Ghost -Alias summon, banish, ofrenda

if ((Get-EnvOrDefault 'GHOST_AUTOSTART' '1') -ne '0') { Enable-Ghost }
