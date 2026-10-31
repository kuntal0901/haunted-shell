# Haunted Shell

*A ghost possesses your terminal.*

Haunted Shell is a PowerShell module that lets a ghost live in your prompt. After you run a command, a small open-weight model running **on your own laptop** reads the command and whether it worked, and the ghost whispers one eerie line back.

```
PS D:\code> gti status
gti : The term 'gti' is not recognized as the name of a cmdlet...
PS D:\code>
  ~ You reached for git and grasped only fog; I know what your fingers meant.

PS D:\code> npm install
npm ERR! code ERESOLVE
PS D:\code>

    +  R.I.P.  npm install  +
    Here lies npm install, so eager, so brave,
    Its node_modules dug a bottomless grave,
    La Catrina just laughed at the dependency tree,
    Now it rests in the panteon, finally free.
```

(Example output: the ghost says something different every time.)

No cloud, no API key, no account. It works with the Wi-Fi off, and nothing you type ever leaves your machine.

## What the ghost does

| Feature | What happens |
| --- | --- |
| **Whispers** | Every command gets a one-line eerie comment, right under its output. |
| **Typo possession** | Type a command that does not exist (`gti`, `pyhton`, `claer`) and the ghost finds the real command you meant and hints at it, in character. |
| **Calavera mode** | About half of failed commands earn a *calavera literaria*: a four-line rhyming mock-epitaph, the Dia de los Muertos tradition. |
| **Ofrenda** | Run `ofrenda` to build a small altar for every command that died in this session, with a short remembrance written for them. |
| **Privacy guard** | Commands that look like they hold secrets (`password`, `token`, `apikey`, `Bearer`, long random strings) are never sent to the model at all. |

After each command the prompt shows `~ the ghost stirs...` for a moment (about 3 seconds on a laptop CPU) while the model writes, then the whisper lands right under the command it is about. Impatient? **Press any key** to skip the wait; the whisper then appears at a later prompt instead. Set `GHOST_WAIT` to `0` if you never want to wait. If Ollama is off, the ghost simply stays quiet.

## Setup on Windows (about 10 minutes)

You need Windows 10 or 11 and about 3 GB of free disk. No GPU is needed: it runs fine on a normal laptop CPU with 8 GB of RAM or more.

**1. Install Ollama.** Download it from <https://ollama.com/download/windows> and run the installer, or in PowerShell:

```powershell
winget install --id Ollama.Ollama -e
```

Ollama starts in the system tray. It is the open-source runtime that runs the model locally.

**2. Get Haunted Shell.** Put this `haunted-shell` folder anywhere, for example `D:\hacktoberfest-2026\haunted-shell`.

**3. Run the installer.** Open PowerShell in that folder and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

It checks Ollama, downloads the model (`llama3.2:3b`, about 2 GB, once), copies the module into your Documents folder, and adds `Import-Module HauntedShell` to your PowerShell profile. If your computer blocks scripts, it offers to allow them for your user only (`RemoteSigned`), which is needed for any PowerShell profile to load.

**4. Open a new PowerShell window** and check everything works:

```powershell
Test-Ghost
```

You should see three green `[ok]` lines and a first whisper. The very first whisper loads the model into memory and can take 10 to 30 seconds; after that the model stays loaded for 30 minutes.

**5. Haunt yourself.** Try `gti status`, then press Enter on an empty line a couple of times. Run something that fails, like `Get-Item nope`. Then run `ofrenda`.

## Commands

| Command | What it does |
| --- | --- |
| `summon` / `Enable-Ghost` | Brings the ghost back after banishing it |
| `banish` / `Disable-Ghost` | Sends the ghost away and restores your normal prompt |
| `ofrenda` / `Show-Ofrenda` | Builds an ofrenda for this session's dead commands |
| `Enable-Calavera` / `Disable-Calavera` | Turns rhyming epitaphs on or off |
| `Set-GhostConfig -Model qwen2.5:3b -Chance 0.5` | Changes settings for this session |
| `Get-GhostConfig` | Shows the current settings |
| `Test-Ghost` | Checks Ollama and the model, and times one whisper |

## Settings

Set these in your profile, above the `Import-Module HauntedShell` line, to keep them. Open the profile with `notepad $PROFILE.CurrentUserAllHosts`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `GHOST_MODEL` | `llama3.2:3b` | Any model you have pulled with Ollama |
| `GHOST_CHANCE` | `1` | Share of successful commands that get a whisper (0 to 1); failures always get one |
| `GHOST_WAIT` | `15` | Longest the prompt waits for a whisper, in seconds; `0` never waits |
| `GHOST_CALAVERA` | `1` | `0` turns calavera mode off |
| `GHOST_CALAVERA_CHANCE` | `0.5` | Share of failed commands that get a calavera instead of a whisper |
| `GHOST_TIMEOUT` | `20` | Seconds to wait for the model before giving up quietly |
| `GHOST_IGNORE` | (empty) | Extra regex; matching commands are never sent |
| `GHOST_COLOR` | `Magenta` | Any PowerShell console colour |
| `GHOST_URL` | `http://localhost:11434` | Where Ollama listens |
| `GHOST_AUTOSTART` | `1` | `0` loads the module without summoning the ghost |

## Swapping the model

The model is one setting. Pull another and point the ghost at it:

```powershell
ollama pull qwen2.5:3b
$env:GHOST_MODEL = 'qwen2.5:3b'; Import-Module HauntedShell -Force
```

| Model | Size | Notes |
| --- | --- | --- |
| `llama3.2:3b` | ~2.0 GB | Default; good balance of speed and character |
| `qwen2.5:3b` | ~1.9 GB | Similar speed, a little more playful |
| `gemma3:4b` | ~3.3 GB | Best writing, noticeably slower on CPU |
| `qwen2.5:1.5b` | ~1.0 GB | Fastest; for older laptops or battery mode |

The ghost's personality lives in `HauntedShell\prompts.json`. Edit it to give your ghost a different voice; no code changes needed. (After editing, re-run `install.ps1 -SkipModel` to copy it into place.)

## Bash and zsh (Linux, macOS, WSL)

A smaller version for bash and zsh lives in `bash/haunted.sh`. It needs `curl` and either `jq` or `python3`. Add this to `~/.bashrc` or `~/.zshrc`:

```bash
source /path/to/haunted-shell/bash/haunted.sh
```

It has whispers, typo possession and calaveras (no ofrenda). `ghost_off` and `ghost_on` toggle it. It is tested on bash; zsh support is written but less tested.

## How it works

1. The module wraps your existing `prompt` function. Each time the prompt draws, it reads the last command from history, whether it succeeded (`$?`, `$LASTEXITCODE` and new entries in `$Error`), and prints any whisper that has finished.
2. If the command passes the privacy guard, it starts a request on a separate PowerShell runspace, then shows a small "the ghost stirs" animation until the whisper is ready (at most `GHOST_WAIT` seconds, and any key skips it).
3. The background runspace calls Ollama's local HTTP API at `localhost:11434` with a short prompt and a cap of 50 to 90 tokens. For a typo, it first scans your PATH, aliases and functions for the closest real command name, so the model gets the right answer to hint at.
4. Only one whisper is written at a time, so the CPU never gets a pile-up of requests.

It works on Windows PowerShell 5.1 and PowerShell 7 and uses only built-in .NET pieces.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `(the ghost cannot reach Ollama ...)` | Start the Ollama app from the Start menu, or run `ollama serve`. Then `Test-Ghost`. |
| Nothing happens at all | Check the profile loaded: `Get-Module HauntedShell`. If it is missing, run `Get-ExecutionPolicy -List` and re-run the installer. |
| The wait after each command feels long | Use `qwen2.5:1.5b`, lower `GHOST_CHANCE`, or set `GHOST_WAIT` to `0` so whispers arrive in the background. |
| Accented letters look wrong | Use Windows Terminal, or set your console font to Consolas or Cascadia. |
| Whispers never appear with oh-my-posh or Starship | Fixed in the module: it re-wraps your theme's prompt when the shell is idle. Run `install.ps1 -SkipModel` again to update. |
| Too chatty | `Set-GhostConfig -Chance 0.3`, or `Disable-Calavera`. |

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This removes the module and the profile lines. Ollama stays installed; remove the model with `ollama rm llama3.2:3b`.

## Built with

- [Ollama](https://github.com/ollama/ollama) (MIT) to run models locally
- [Llama 3.2 3B](https://www.llama.com/) by Meta, an open-weight model (Llama 3.2 Community License)
- PowerShell

MIT licensed. Made for the *Ghost in the Machine* challenge, Halloween and Dia de los Muertos 2026.
