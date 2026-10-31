*This is a submission for the [Hacktoberfest Open-Source AI Challenge Week 4: Ghost in the Machine](https://dev.to/challenges/hacktoberfest-week4-2026-10-26)*

## What I Built

**Haunted Shell** lets a ghost possess my PowerShell prompt.

Every time I run a command, a ghost reads it and whispers one line back in dim purple text, right under the output. The ghost is an open-weight model running on my own laptop. It's creepy, a bit playful, and it knows what I did:

```
PS C:\Users\kuntal> Test-Ghost
  ~ You invoked me, a spectral presence lingering here, eager to haunt your code, forever trapped in this terminal realm.
```

The theme gave me two ideas, and I built both into the ghost:

- **Halloween: the possession.** When I mistype a command (`gti status`, `pyhton`, `claer`), the ghost *possesses the typo*. It works out which real command I meant and hints at it in character, as if it has been watching my fingers.
- **Día de los Muertos: the calavera and the ofrenda.** When a command dies, it can earn a *calavera literaria*, the playful four-line rhyming epitaph Mexicans write for the living and the dead every November. At the end of the night, `ofrenda` builds a little altar for every command that died in the session, lists them *en memoria*, and writes a short remembrance.

```
PS D:\code> npm install
npm ERR! code ERESOLVE

    +  R.I.P.  npm install  +
    {{PASTE A REAL CALAVERA FROM YOUR TERMINAL HERE}}
```

What inspired it: a terminal is where my code goes to die, so that's where I wanted the ghost to live. Any developer's shell history is basically a graveyard of failed builds, typos and `git push --force` regrets. I wanted something that mourns them with me, in the spirit of a holiday that remembers the dead with humour instead of fear.

## Demo

{{DEMO VIDEO OR GIF LINK: record about 60 seconds of your terminal showing Test-Ghost, a typo (gti status), a failed command that gets a calavera, and ofrenda}}

## Code

{% github {{YOUR_GITHUB_USERNAME}}/haunted-shell %}

The repo has the PowerShell module, a one-command installer for Windows, an uninstaller, and a smaller bash/zsh version for Linux, macOS and WSL.

## How I Built It

**The open pieces:**

- **[Ollama](https://github.com/ollama/ollama)** (MIT) runs the model locally and exposes a small HTTP API on `localhost:11434`.
- **[Llama 3.2 3B](https://www.llama.com/)**, an open-weight model from Meta, is the ghost's voice. It's 2 GB, and on my laptop's CPU it writes a whisper in about 3 seconds.
- **PowerShell** (the module works on Windows PowerShell 5.1 and PowerShell 7, with no extra dependencies).

**How it fits together:**

1. The module wraps the `prompt` function. Every time the prompt draws, it reads the last command from history, works out whether it failed (`$?`, `$LASTEXITCODE` and new entries in `$Error`), and builds a short prompt for the model.
2. The model call runs on a separate PowerShell runspace, so the shell never freezes. While it writes, the prompt shows a small `~ the ghost stirs...` animation. Pressing any key skips the wait, and that whisper shows up at a later prompt instead.
3. Each kind of haunting gets its own system prompt and token cap: one sentence (50 tokens) for whispers, four rhyming lines (90 tokens) for calaveras. The whole personality lives in a `prompts.json` file, so you can rewrite the ghost without touching the code.
4. **Typo possession doesn't trust the model to guess.** Before calling the model, the module scans PATH, aliases and functions for the closest real command, using an edit distance that counts swapped letters (`gti` → `git` is one edit). That answer goes into the prompt, so even a 3B model always hints at the right command.
5. **A privacy guard** checks every command before it goes anywhere. Anything that looks like a secret (`password`, `token`, `apikey`, `Bearer`, long random strings) is never sent, not even to the local model.

A few things I learned along the way:

- **Windows PowerShell 5.1 has its own parser.** My first typo matcher used 2D-array indexing inside a method call, which PowerShell 7 accepts and 5.1 refuses to parse. I rewrote it with a flat array.
- **Prompt themes fight back.** My oh-my-posh theme loads after the module and quietly replaced the ghost's prompt hook. Now the module listens for the shell's `OnIdle` event and re-wraps whatever prompt is active, so it works alongside oh-my-posh or Starship in any load order. It also passes the real `$?` through, so the theme still turns red when a command fails.
- **The model gets warmed up at shell start** with `keep_alive: 30m`, so only the very first whisper pays the cost of loading the model.

Setup takes about 10 minutes:

```powershell
winget install --id Ollama.Ollama -e
powershell -ExecutionPolicy Bypass -File .\install.ps1
# open a new PowerShell window
Test-Ghost
```

## Why Does Open Innovation Matter?

**A terminal is the most private place on a computer.** My shell history has file paths, client project names, server names, the occasional half-typed password, and many `git commit -m "please work"`. I would never stream every command I type to a cloud API just to get a spooky joke back. With an open-weight model running locally, the ghost sees everything and tells no one: nothing leaves my laptop.

**It works with the lights (and the Wi-Fi) off.** There's no account, no API key, no rate limit, and no service that can shut down next year and take my ghost with it. It keeps haunting on a plane.

**It costs nothing to run.** A whisper after every command is hundreds of model calls a day. On a paid API that's a real monthly bill for a joke. Here it's free, forever.

**It runs on a normal laptop.** I built this on a Windows laptop with 16 GB of RAM and Intel Iris Xe graphics, so no GPU at all. A 3B open model on the CPU answers in about 3 seconds, which feels like the ghost is replying to me.

**The ghost is mine to change.** Swapping the brain is one setting: `qwen2.5:1.5b` for an older laptop, `gemma3:4b` for better poetry. The voice is a JSON file. With a closed API I'd be stuck with whatever personality, safety tuning and pricing the provider picked, and whatever model they deprecate next.

**Where open worked better than closed:**

- **Latency I control.** The model stays loaded in memory, so there's no network round trip and no cold start after the first call.
- **Tiny, tuned calls.** I cap output at 50 tokens and tune each kind of haunting separately, with no per-request pricing to worry about.
- **Trust I can explain.** I can tell anyone exactly where their commands go: to a process on their own machine, whose source they can read.

The honest trade-off: a 3B model is less witty than a frontier model, and it takes a few seconds on CPU. For a ghost that only needs one good line at a time, that's the right deal.

## My Agent Session

{{DEVRELAY SESSION LINK, or delete this section}}

## The Spirit of It

{{OPTIONAL: the moment it landed for you. For example the first calavera that made you laugh, or the ofrenda listing a day's worth of your failed commands. Delete this section if you'd rather skip it.}}

## Prize Categories

{{LIST CATEGORIES, or delete this section. See the note in the thread before entering Gemma.}}

Built with Ollama, Llama 3.2 3B and PowerShell. MIT licensed. *En memoria de todos los comandos caídos.*
