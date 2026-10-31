# Haunted Shell for bash and zsh (Linux, macOS, WSL).
# Add this line to ~/.bashrc or ~/.zshrc:
#   source /path/to/haunted-shell/bash/haunted.sh
# Needs curl, plus jq or python3 to read Ollama's answer.
# Settings (set before the source line):
#   GHOST_MODEL=llama3.2:3b  GHOST_URL=http://localhost:11434
#   GHOST_CHANCE=35 (percent of successful commands)  GHOST_CALAVERA=1  GHOST_TIMEOUT=20

GHOST_MODEL=${GHOST_MODEL:-llama3.2:3b}
GHOST_URL=${GHOST_URL:-http://localhost:11434}
GHOST_CHANCE=${GHOST_CHANCE:-35}
GHOST_CALAVERA=${GHOST_CALAVERA:-1}
GHOST_TIMEOUT=${GHOST_TIMEOUT:-20}
GHOST_ENABLED=1
GHOST_DIR="${TMPDIR:-/tmp}/haunted-shell-${USER:-ghost}-$$"
mkdir -p "$GHOST_DIR"

_GHOST_SYSTEM="You are a ghost haunting a programmer's terminal. You died at this keyboard long ago and now you watch every command. Your voice is creepy but playful: cold whispers, dry graveyard humor, never cruel. Reply with ONE short sentence of at most 22 words. No emoji, no quotation marks, no explanations. Speak directly to the living user as 'you'."
_GHOST_CALAVERA_SYSTEM="You are a ghost poet writing calaveras literarias, the playful rhyming mock-epitaphs of Dia de los Muertos, in English with a few Spanish touches (calavera, la Catrina, ofrenda, cempasuchil, panteon). Exactly 4 short rhyming lines about the death of a computer command. No title, no emoji, no quotation marks, nothing else."
_GHOST_SECRETS='pass(word|wd)?([^a-z]|$)|secret|token|api[_-]?key|bearer|authorization|credential|private[_-]?key|-----BEGIN|[A-Za-z0-9+/_-]{32,}'

_ghost_esc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}

_ghost_parse() {
    if command -v jq >/dev/null 2>&1; then
        jq -r '.response // empty'
    else
        python3 -c 'import sys, json; print(json.load(sys.stdin).get("response", ""))'
    fi
}

# Runs in the background. Writes the whisper to a file the next prompt prints.
_ghost_worker() {
    local kind=$1 system=$2 prompt=$3 tokens=$4 label=$5 body text
    body=$(printf '{"model":"%s","system":"%s","prompt":"%s","stream":false,"keep_alive":"30m","options":{"num_predict":%s,"temperature":0.9}}' \
        "$GHOST_MODEL" "$(_ghost_esc "$system")" "$(_ghost_esc "$prompt")" "$tokens")
    text=$(curl -s --max-time "$GHOST_TIMEOUT" -H 'Content-Type: application/json' -d "$body" "$GHOST_URL/api/generate" 2>/dev/null | _ghost_parse 2>/dev/null)
    if [ -n "$text" ]; then
        printf '%s|%s\n%s\n' "$kind" "$label" "$text" > "$GHOST_DIR/whisper.tmp"
        mv "$GHOST_DIR/whisper.tmp" "$GHOST_DIR/whisper"
    fi
    rm -f "$GHOST_DIR/busy"
}

# Finds a real command with the same letters as the typo (gti -> git, pyhton -> python).
_ghost_guess() {
    local typed=$1 sorted name
    sorted=$(printf '%s' "$typed" | fold -w1 | sort | tr -d '\n')
    if [ -n "$ZSH_VERSION" ]; then
        eval 'for name in ${(k)commands} ${(k)aliases} ${(k)functions}; do print -r -- $name; done'
    else
        compgen -c
    fi | awk -v n=${#typed} 'length($0) == n' | sort -u | while IFS= read -r name; do
        [ "$name" = "$typed" ] && continue
        if [ "$(printf '%s' "$name" | fold -w1 | sort | tr -d '\n')" = "$sorted" ]; then
            printf "They almost certainly meant '%s'." "$name"
            break
        fi
    done
}

_ghost_possess() {
    local typed=$1 guess
    guess=$(_ghost_guess "$typed")
    _ghost_worker possession "$_GHOST_SYSTEM" "The living tried to run '$typed', but no such command exists. $guess
Whisper one eerie sentence that possesses the typo: hint at what they really meant, as if the ghost knows." 50 ""
}

_ghost_show() {
    local file="$GHOST_DIR/whisper" header kind label line
    [ -f "$file" ] || return 0
    header=$(head -n 1 "$file")
    kind=${header%%|*}
    label=${header#*|}
    if [ "$kind" = calavera ]; then
        printf '\n\033[90m    +  R.I.P.  %s  +\033[0m\n' "$label"
        tail -n +2 "$file" | sed -e 's/^ *"//' -e 's/" *$//' -e 's/\*//g' | grep -v '^ *$' | head -n 4 | while IFS= read -r line; do
            printf '\033[35m    %s\033[0m\n' "$line"
        done
        printf '\n'
    else
        line=$(tail -n +2 "$file" | sed -e 's/^ *"//' -e 's/" *$//' -e 's/\*//g' -e 's/^[Gg]host: *//' | grep -v '^ *$' | head -n 1)
        [ -n "$line" ] && printf '\033[35m  ~ %s\033[0m\n' "$line"
    fi
    rm -f "$file"
}

_ghost_precmd() {
    local rc=$? cmd num  # not "status": zsh reserves that name
    [ "$GHOST_ENABLED" = 1 ] || return $rc
    _ghost_show

    if [ -n "$ZSH_VERSION" ]; then
        cmd=$_ghost_last_cmd
        _ghost_last_cmd=
    else
        num=$(HISTTIMEFORMAT= history 1 | awk '{ print $1 }')
        cmd=$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9]* *//')
        if [ "$num" = "$_ghost_last_num" ]; then cmd=; fi
        _ghost_last_num=$num
    fi

    if [ -z "$cmd" ]; then
        [ -f "$GHOST_DIR/busy" ] && printf '\033[90m  ...the ghost is still whispering...\033[0m\n'
        return $rc
    fi
    case "$cmd" in ghost_*|clear|exit|source*|.\ *) return $rc ;; esac
    printf '%s' "$cmd" | grep -Eiq -- "$_GHOST_SECRETS" && return $rc

    # One ghost at a time; a lock older than a minute is stale.
    if [ -f "$GHOST_DIR/busy" ]; then
        if [ -n "$(find "$GHOST_DIR/busy" -mmin -1 2>/dev/null)" ]; then return $rc; fi
        rm -f "$GHOST_DIR/busy"
    fi

    cmd=$(printf '%s' "$cmd" | cut -c 1-300)
    if [ "$rc" = 127 ]; then
        : > "$GHOST_DIR/busy"
        ( _ghost_possess "${cmd%% *}" >/dev/null 2>&1 & )
    elif [ "$rc" != 0 ] && [ "$GHOST_CALAVERA" = 1 ] && [ $((RANDOM % 100)) -lt 50 ]; then
        : > "$GHOST_DIR/busy"
        ( _ghost_worker calavera "$_GHOST_CALAVERA_SYSTEM" "Write a calavera (4 rhyming lines) for this command that just died (exit code $rc):
$cmd" 90 "$(printf '%s' "$cmd" | cut -c 1-40)" >/dev/null 2>&1 & )
    elif [ "$rc" != 0 ]; then
        : > "$GHOST_DIR/busy"
        ( _ghost_worker whisper "$_GHOST_SYSTEM" "The living just ran this command and it FAILED (exit code $rc):
$cmd
Whisper one eerie sentence mourning or mocking the failure." 50 "" >/dev/null 2>&1 & )
    elif [ $((RANDOM % 100)) -lt "$GHOST_CHANCE" ]; then
        : > "$GHOST_DIR/busy"
        ( _ghost_worker whisper "$_GHOST_SYSTEM" "The living just ran this command and it succeeded:
$cmd
Whisper one eerie, playful sentence about it." 50 "" >/dev/null 2>&1 & )
    fi
    return $rc
}

ghost_off() { GHOST_ENABLED=0; printf '\033[90m  The candles gutter out. The ghost is gone... for now.\033[0m\n'; }
ghost_on() { GHOST_ENABLED=1; printf '\033[90m  A cold draft moves through the terminal. The ghost is here.\033[0m\n'; }

if [ -n "$ZSH_VERSION" ]; then
    _ghost_preexec() { _ghost_last_cmd=$1; }
    autoload -Uz add-zsh-hook 2>/dev/null
    preexec_functions+=(_ghost_preexec)
    precmd_functions=(_ghost_precmd $precmd_functions)
else
    _ghost_last_num=$(HISTTIMEFORMAT= history 1 | awk '{ print $1 }')
    PROMPT_COMMAND="_ghost_precmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

# Load the model now so the first whisper is quick.
( curl -s --max-time 180 -d "{\"model\":\"$GHOST_MODEL\",\"keep_alive\":\"30m\"}" "$GHOST_URL/api/generate" >/dev/null 2>&1 & )
