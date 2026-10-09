#!/usr/bin/env bash
# install.sh — link these dotfiles into ~. Safe to re-run.
# Existing links are repointed; real files/dirs in the way are moved to <name>.bak-<timestamp>.
# Usage: ./install.sh [--dry-run]
# update.sh runs it on every update, so each step only acts on what's missing
# or stale.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"
DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
run()  { if ((DRY)); then echo "    [dry-run] $*"; else "$@"; fi; }

# --- change log -------------------------------------------------------------
# Every change made inside $HOME is recorded here so uninstall.sh can put the
# machine back the way it was. Kept outside the repo: it describes this Mac.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
MANIFEST="$STATE_DIR/install.json"
LOG="$STATE_DIR/install-$STAMP.log"
RECORDS=()
PRE_B=""   # formulae installed before this run
PRE_C=""   # casks installed before this run
BINS=""    # absolute paths of the binaries we built, for uninstall to remove
DEPS=""    # alfred workflow dependency check results, for the manifest

# Everything this run prints also lands in the log, so a failed brew install can
# be read back afterwards. Skipped on a dry run, which must not write anything.
if ((DRY)); then
  LOG=""
else
  mkdir -p "$STATE_DIR"
  exec > >(tee -a "$LOG") 2>&1
fi

# record <action> <path> <type> <detail> <sha256> <mode> <our-target>
#   action   link | copy | remove | backup
#   type     absent | symlink | file | dir
#   detail   the old symlink target, or the .bak path we moved it to
#   sha256   checksum of the displaced file, so a restore can be verified
#   mode     its permission bits
#   target   what we put there, so uninstall can tell ours from yours
# Fields are separated by \x1f, not tab: tab counts as IFS whitespace, so bash
# collapses runs of it and a record with an empty middle field would shift left.
SEP=$'\x1f'
record() {
  RECORDS+=("$1$SEP$2$SEP$3$SEP${4:-}$SEP${5:-}$SEP${6:-}$SEP${7:-}")
}

# prior_of <path>: "<type>|<detail>|<sha256>|<mode>" (| = \x1f) for what's there now
prior_of() {
  if [[ -L "$1" ]]; then
    printf 'symlink%s%s%s%s' "$SEP" "$(readlink "$1")" "$SEP" "$SEP"
  elif [[ -d "$1" ]]; then
    printf 'dir%s%s%s%s%s' "$SEP" "$1.bak-$STAMP" "$SEP" "$SEP" "$(stat -f '%Lp' "$1" 2>/dev/null)"
  elif [[ -e "$1" ]]; then
    printf 'file%s%s%s%s%s%s' "$SEP" "$1.bak-$STAMP" \
      "$SEP" "$(shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1)" \
      "$SEP" "$(stat -f '%Lp' "$1" 2>/dev/null)"
  else
    printf 'absent%s%s%s' "$SEP" "$SEP" "$SEP"
  fi
}

# backup <path>: move a real file/dir out of the way
backup() {
  warn "backing up $1 -> $1.bak-$STAMP"
  run mv "$1" "$1.bak-$STAMP"
}

# link <source in repo> <destination>
link() {
  local src="$DOTFILES/$1" dst="$2"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    echo "    ok  $dst"
    return
  fi
  local -a P
  IFS="$SEP" read -r -a P <<<"$(prior_of "$dst")"
  run mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    echo "    fix $dst (was -> ${P[1]:-})"
    run rm "$dst"
  elif [[ -e "$dst" ]]; then
    backup "$dst"
  fi
  echo "    new $dst -> $src"
  run ln -s "$src" "$dst"
  record link "$dst" "${P[0]:-}" "${P[1]:-}" "${P[2]:-}" "${P[3]:-}" "$src"
}

# capture_versions: what everything was at install time, so a specific version
# can be put back later. Written as TSV for write_manifest to fold in.
capture_versions() {
  local out="$1"
  {
    printf 'macos\t%s\n'  "$(sw_vers -productVersion 2>/dev/null)"
    printf 'build\t%s\n'  "$(sw_vers -buildVersion 2>/dev/null)"
    printf 'arch\t%s\n'   "$(uname -m 2>/dev/null)"
    printf 'dotfiles_commit\t%s\n' "$(git -C "$DOTFILES" rev-parse HEAD 2>/dev/null)"
    [[ -d "${CLI_TOOLS:-}/.git" ]] &&
      printf 'cli_tools_commit\t%s\n' "$(git -C "$CLI_TOOLS" rev-parse HEAD 2>/dev/null)"
    command -v brew >/dev/null && printf 'brew\t%s\n' "$(brew --version 2>/dev/null | head -1)"
    command -v go   >/dev/null && printf 'go\t%s\n'   "$(go version 2>/dev/null)"
    command -v vim  >/dev/null && printf 'vim\t%s\n'   "$(vim --version 2>/dev/null | head -1)"
    command -v uv   >/dev/null && printf 'uv\t%s\n'    "$(uv --version 2>/dev/null)"
    command -v ya   >/dev/null && printf 'yazi\t%s\n'  "$(ya --version 2>/dev/null)"
    true
  } > "$out"
}

# write_manifest: append this run's records, as JSON, atomically
write_manifest() {
  ((${#RECORDS[@]})) || { echo "    no changes to record"; return 0; }
  if ((DRY)); then
    echo "    [dry-run] would record ${#RECORDS[@]} change(s) in $MANIFEST"
    return 0
  fi
  mkdir -p "$(dirname "$MANIFEST")"
  local vfile bfile cfile
  vfile="$(mktemp)"; bfile="$(mktemp)"; cfile="$(mktemp)"
  capture_versions "$vfile"
  if command -v brew >/dev/null; then
    brew list --versions        > "$bfile" 2>/dev/null || true
    brew list --cask --versions > "$cfile" 2>/dev/null || true
  fi
  printf '%s\n' "${RECORDS[@]}" |
    MANIFEST="$MANIFEST" STAMP="$STAMP" DOTFILES="$DOTFILES" LOG="$LOG" \
    VFILE="$vfile" BFILE="$bfile" CFILE="$cfile" \
    PRE_B="$PRE_B" PRE_C="$PRE_C" BINS="$BINS" DEPS="$DEPS" \
    CLI_TOOLS="${CLI_TOOLS:-}" python3 -c '
import json, os, sys

path = os.environ["MANIFEST"]
actions = []
for line in sys.stdin.read().splitlines():
    if not line.strip():
        continue
    action, p, ptype, detail, sha, mode, target = (line.split("\x1f") + [""] * 7)[:7]
    prior = {"type": ptype}
    if ptype == "symlink":
        prior["target"] = detail
    elif ptype in ("file", "dir"):
        prior["backup"] = detail
    if sha:
        prior["sha256"] = sha
    if mode:
        prior["mode"] = mode
    entry = {"action": action, "path": p, "prior": prior}
    if target:
        entry["target"] = target
    actions.append(entry)


def kv(path):
    out = {}
    try:
        with open(path) as f:
            for ln in f:
                parts = ln.rstrip("\n").split("\t" if "\t" in ln else " ", 1)
                if len(parts) == 2 and parts[0]:
                    out[parts[0]] = parts[1].strip()
    except OSError:
        pass
    return out


versions = kv(os.environ.get("VFILE", ""))
post_f = kv(os.environ.get("BFILE", ""))
post_c = kv(os.environ.get("CFILE", ""))
pre_f = kv(os.environ.get("PRE_B", ""))
pre_c = kv(os.environ.get("PRE_C", ""))

# Record the state after, plus exactly what changed, so a restore knows what it
# may remove (added) and what it would have to downgrade (changed).
versions["formulae"] = post_f
versions["casks"] = post_c
versions["added"] = {
    "formulae": sorted(set(post_f) - set(pre_f)),
    "casks": sorted(set(post_c) - set(pre_c)),
}
versions["changed"] = {
    "formulae": {k: {"from": pre_f[k], "to": post_f[k]}
                 for k in set(pre_f) & set(post_f) if pre_f[k] != post_f[k]},
    "casks": {k: {"from": pre_c[k], "to": post_c[k]}
              for k in set(pre_c) & set(post_c) if pre_c[k] != post_c[k]},
}

try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError
except (FileNotFoundError, ValueError, json.JSONDecodeError):
    data = {}
data.setdefault("schema", 1)
data.setdefault("runs", [])
def deps_of(path):
    """{workflow: {dep: present|missing}} from the dependency check"""
    out = {}
    try:
        with open(path) as f:
            for ln in f:
                parts = ln.rstrip("\n").split("\t")
                if len(parts) == 3:
                    out.setdefault(parts[0], {})[parts[1]] = parts[2]
    except OSError:
        pass
    return out


deps = deps_of(os.environ.get("DEPS", ""))


def lines(path):
    try:
        with open(path) as f:
            return sorted({ln.strip() for ln in f if ln.strip()})
    except OSError:
        return []


data["runs"].append({
    "stamp": os.environ["STAMP"],
    "dotfiles": os.environ["DOTFILES"],
    "log": os.environ.get("LOG", ""),
    "cli_tools": os.environ.get("CLI_TOOLS", ""),
    "binaries": lines(os.environ.get("BINS", "")),
    "alfred_deps": deps,
    "versions": versions,
    "actions": actions,
})

tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
missing = sum(1 for w in deps.values() for v in w.values() if v == "missing")
print("    recorded %d workflow dependency check(s), %d missing" % (
    sum(len(w) for w in deps.values()), missing))
print("    recorded %d file change(s); %d package(s) added, %d changed"
      % (len(actions),
         len(versions["added"]["formulae"]) + len(versions["added"]["casks"]),
         len(versions["changed"]["formulae"]) + len(versions["changed"]["casks"])))
print("    manifest: %s" % path)
'
  rm -f "$vfile" "$bfile" "$cfile" "$PRE_B" "$PRE_C" "$BINS" "$DEPS"
  echo "    log: $LOG"
}

# --- homebrew + packages ---------------------------------------------------
say homebrew
if ! command -v brew >/dev/null; then
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    warn "Homebrew missing. Install it, then re-run:"
    echo '      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  fi
fi
if command -v brew >/dev/null; then
  # snapshot first: "what this run added" is post minus pre, and uninstall.sh
  # needs that to know what it may remove.
  if ((DRY)); then
    echo "    [dry-run] would snapshot installed formulae/casks"
  else
    PRE_B="$(mktemp)"; PRE_C="$(mktemp)"
    brew list --versions        > "$PRE_B" 2>/dev/null || true
    brew list --cask --versions > "$PRE_C" 2>/dev/null || true
    echo "    snapshot: $(wc -l <"$PRE_B" | tr -d ' ') formulae, $(wc -l <"$PRE_C" | tr -d ' ') casks already installed"
  fi
  echo "    brew bundle (see Brewfile)"
  run brew bundle install --file="$DOTFILES/Brewfile" --no-upgrade --verbose
else
  warn "skipping Brewfile: no brew on PATH"
fi

# --- rust (rustup is in the Brewfile; it ships no toolchain) ----------------
# Homebrew's rustup is keg-only: cargo/rustc live in its opt/bin, which zshrc
# adds to PATH. Put it on this script's PATH too, so cli-tools' Rust crates
# build below. The toolchain itself lands in ~/.rustup.
say rust
RUSTUP_BIN="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/rustup/bin"
[[ -d "$RUSTUP_BIN" ]] && PATH="$RUSTUP_BIN:$PATH"
if command -v rustup >/dev/null; then
  if rustup toolchain list 2>/dev/null | grep -q '^stable'; then
    echo "    ok  stable toolchain"
  else
    echo "    rustup default stable"
    run rustup default stable || warn "rust toolchain install failed; run: rustup default stable"
  fi
else
  warn "rustup missing: run brew bundle (Brewfile), then re-run"
fi

# --- gh extensions (gh itself is in the Brewfile) ---------------------------
say "gh extensions"
GH_EXTENSIONS=(dlvhdr/gh-dash dlvhdr/gh-enhance)
if command -v gh >/dev/null; then
  installed="$(gh extension list 2>/dev/null | cut -f2)"
  for ext in "${GH_EXTENSIONS[@]}"; do
    if grep -qx "$ext" <<<"$installed"; then
      echo "    ok  $ext"
    else
      echo "    gh extension install $ext"
      run gh extension install "$ext" || warn "$ext install failed (gh auth login, then re-run)"
    fi
  done
else
  warn "gh missing: run brew bundle (Brewfile), then re-run"
fi

# --- zsh -------------------------------------------------------------------
say zsh
link zsh/zshrc "$HOME/.zshrc"
if [[ ! -e "$HOME/.zshrc.local" ]]; then
  echo "    new ~/.zshrc.local from example (edit it)"
  run cp "$DOTFILES/zsh/zshrc.local.example" "$HOME/.zshrc.local"
  record copy "$HOME/.zshrc.local" absent "" "" "" "$DOTFILES/zsh/zshrc.local.example"
fi

# --- cli-tools (separate repo: my own go utilities) -------------------------
CLI_TOOLS="$HOME/Documents/cli-tools"
say cli-tools
CLI_TOOLS_REPO="https://github.com/malikwashington/cli-tools.git"
if [[ -d "$CLI_TOOLS/.git" ]]; then
  echo "    pull $CLI_TOOLS"
  run git -C "$CLI_TOOLS" pull --ff-only || warn "pull failed; leaving the checkout as-is"
elif [[ -e "$CLI_TOOLS" ]]; then
  warn "$CLI_TOOLS exists but isn't a git checkout; skipping"
else
  echo "    clone $CLI_TOOLS_REPO"
  run git clone "$CLI_TOOLS_REPO" "$CLI_TOOLS"
fi
# Each tool is its own crate/module. Build whatever is there by whichever
# toolchain it needs — go and rust now, more later. Both install into
# directories zsh/zshrc already has on PATH.
#
# Found by searching for manifests rather than by a fixed layout, so
# cli-tools/go/<tool> and cli-tools/Rust/<tool> both work, and so would a
# regrouping later.
if ((DRY)); then
  echo "    [dry-run] build each module/crate under $CLI_TOOLS"
else
  BINS="$(mktemp)"
  built=0; failed=0
  while IFS= read -r manifest; do
    [[ -n "$manifest" ]] || continue
    d="$(dirname "$manifest")"
    name="${d#"$CLI_TOOLS"/}"
    if [[ -f "$d/go.mod" ]]; then
      if ! command -v go >/dev/null; then
        warn "$name needs go: run brew bundle (Brewfile), then re-run"; failed=$((failed+1)); continue
      fi
      # ask go where the binary lands rather than guessing from the directory
      target="$(cd "$d" && go list -f '{{.Target}}' . 2>/dev/null || true)"
      if (cd "$d" && go install .) 2>/dev/null; then
        echo "    built $name (go)"
        [[ -n "$target" ]] && echo "$target" >> "$BINS"
        built=$((built+1))
      else
        warn "$name failed to build; run: cd $d && go install ."
        failed=$((failed+1))
      fi
    elif [[ -f "$d/Cargo.toml" ]]; then
      if ! command -v cargo >/dev/null; then
        warn "$name needs cargo: brew install rustup && rustup default stable, then re-run"; failed=$((failed+1)); continue
      fi
      if (cd "$d" && cargo install --path . --quiet) 2>/dev/null; then
        echo "    built $name (rust)"
        # cargo installs into $CARGO_HOME/bin under the package name
        pkg="$(sed -n 's/^name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$d/Cargo.toml" | head -1)"
        echo "${CARGO_HOME:-$HOME/.cargo}/bin/${pkg:-$name}" >> "$BINS"
        built=$((built+1))
      else
        warn "$name failed to build; run: cd $d && cargo install --path ."
        failed=$((failed+1))
      fi
    fi
  done < <(find "$CLI_TOOLS" -maxdepth 4 -type f \
             \( -name go.mod -o -name Cargo.toml \) \
             -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/vendor/*' \
             2>/dev/null | sort)
  echo "    $built built, $failed failed"
fi

# --- vim -------------------------------------------------------------------
say vim
# vim reads ~/.vim/vimrc, but ~/.vimrc would take precedence: remove the old link
if [[ -L "$HOME/.vimrc" ]]; then
  echo "    rm  ~/.vimrc (old link, vim now reads ~/.vim/vimrc)"
  record remove "$HOME/.vimrc" symlink "$(readlink "$HOME/.vimrc")" "" "" ""
  run rm "$HOME/.vimrc"
elif [[ -e "$HOME/.vimrc" ]]; then
  record backup "$HOME/.vimrc" file "$HOME/.vimrc.bak-$STAMP" \
    "$(shasum -a 256 "$HOME/.vimrc" 2>/dev/null | cut -d' ' -f1)" \
    "$(stat -f '%Lp' "$HOME/.vimrc" 2>/dev/null)" ""
  backup "$HOME/.vimrc"
fi
# carry over file-browser history before ~/.vim is moved aside
if [[ -d "$HOME/.vim" && ! -L "$HOME/.vim" && -f "$HOME/.vim/.netrwhist" && ! -e "$DOTFILES/vim/.netrwhist" ]]; then
  run cp "$HOME/.vim/.netrwhist" "$DOTFILES/vim/.netrwhist"
fi
link vim "$HOME/.vim"
if command -v vim >/dev/null; then
  echo "    installing plugins"
  run vim -N -u "$DOTFILES/vim/vimrc" -i NONE -es -c 'PlugInstall --sync' -c 'PlugClean!' -c 'qa!' </dev/null >/dev/null 2>&1 || warn "PlugInstall failed; open vim to retry"
fi

# --- git (delta is the pager; Brewfile installs it) -------------------------
# Shared settings go to ~/.config/git/config, which git reads *before*
# ~/.gitconfig. ~/.gitconfig is never touched: it keeps each machine's identity
# and credential helpers (and on a work Mac, whatever IT manages), and it wins.
say git
GIT_XDG="${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
if [[ -e "$GIT_XDG" && ! -L "$GIT_XDG" ]]; then
  warn "$GIT_XDG already exists; leaving it alone. To use the shared settings, add:"
  echo "      [include]"
  echo "          path = $DOTFILES/git/gitconfig"
else
  link git/gitconfig "$GIT_XDG"
fi
if [[ -L "$HOME/.gitconfig" && "$(readlink "$HOME/.gitconfig")" == "$DOTFILES/git/gitconfig" ]]; then
  warn "~/.gitconfig links to the shared file (an older install did this); it should be"
  warn "this machine's own file — restore it from ~/.gitconfig.bak-* by hand"
fi

# --- tmux ------------------------------------------------------------------
say tmux
link tmux/tmux.conf "$HOME/.config/tmux/tmux.conf"

# --- karabiner (whole dir: its GUI saves by replacing karabiner.json) -------
say karabiner
link karabiner "$HOME/.config/karabiner"

# --- yazi (files only: flavors install into ~/.config/yazi and aren't tracked) -
say yazi
link yazi/theme.toml "$HOME/.config/yazi/theme.toml"
link yazi/package.toml "$HOME/.config/yazi/package.toml"
link yazi/init.lua     "$HOME/.config/yazi/init.lua"
link yazi/yazi.toml    "$HOME/.config/yazi/yazi.toml"
link yazi/keymap.toml  "$HOME/.config/yazi/keymap.toml"
if command -v ya >/dev/null; then
  echo "    ya pkg install"
  run ya pkg install >/dev/null || warn "ya pkg install failed"
else
  warn "yazi not installed: brew install yazi, then re-run"
fi

# --- bettercmdtab (Cmd+Tab replacement; the cask is in the Brewfile) --------
# Stays open until Return/Esc, h/j/k/l to move, a visible highlight. The
# karabiner rule "BetterCmdTab: ..." relies on the stay-open settings: it maps
# h/j/k/l to arrows while Cmd is held, because the window strip only takes arrows.
say bettercmdtab
BCT_ID=pro.bettercmdtab.BetterCmdTab
# key type value [comment]; booleans read back from defaults as 1/0
BCT_PREFS=(
  "Switcher.stayOpenOnRelease bool 1"
  "Switcher.stayOpenOnQuickTap bool 1"
  "Switcher.vimNavigationEnabled bool 1"
  "Switcher.panelOpacity int 100"         # solid panel: the pale selection highlight shows up better
  "Switcher.boldSelectedLabel bool 1"
  "Switcher.showApplicationNames bool 1"
)
if [[ -d /Applications/BetterCmdTab.app ]]; then
  bct_stale=()
  for spec in "${BCT_PREFS[@]}"; do
    read -r key type value <<<"$spec"
    [[ "$(defaults read "$BCT_ID" "$key" 2>/dev/null)" == "$value" ]] || bct_stale+=("$spec")
  done
  if ((${#bct_stale[@]} == 0)); then
    echo "    ok  settings"
  else
    bct_running=0
    pgrep -f BetterCmdTab.app >/dev/null && bct_running=1
    # it rewrites its preferences on quit, so write them while it's closed
    ((bct_running)) && run osascript -e "quit app id \"$BCT_ID\""
    ((DRY)) || while pgrep -f BetterCmdTab.app >/dev/null; do sleep 0.2; done
    for spec in "${bct_stale[@]}"; do
      read -r key type value <<<"$spec"
      [[ $type == bool ]] && { ((value)) && value=true || value=false; }
      run defaults write "$BCT_ID" "$key" "-$type" "$value"
    done
    echo "    ${#bct_stale[@]} setting(s) applied (grant it Accessibility in System Settings if asked)"
    ((bct_running)) && run open -b "$BCT_ID"
  fi
else
  warn "BetterCmdTab not installed: run brew bundle (Brewfile), then re-run"
fi

# --- alfred ----------------------------------------------------------------
say alfred
ALFRED_DIR="$HOME/Library/Application Support/Alfred"
ALFRED_PREFS="$ALFRED_DIR/Alfred.alfredpreferences"
REPO_PREFS="$DOTFILES/alfred/Alfred.alfredpreferences"
if [[ -L "$ALFRED_PREFS" && "$(readlink "$ALFRED_PREFS")" == "$REPO_PREFS" ]]; then
  echo "    ok  $ALFRED_PREFS"
else
  alfred_running=0
  if pgrep -x Alfred >/dev/null; then
    alfred_running=1
    echo "    quitting Alfred"
    run osascript -e 'quit app id "com.runningwithcrayons.Alfred"'
    ((DRY)) || while pgrep -x Alfred >/dev/null; do sleep 0.2; done
  fi
  # keep this Mac's local settings (hotkey etc.): Alfred stores them per machine id
  if [[ -d "$ALFRED_PREFS/preferences/local" && ! -L "$ALFRED_PREFS" ]]; then
    for d in "$ALFRED_PREFS/preferences/local"/*/; do
      id="$(basename "$d")"
      [[ -e "$REPO_PREFS/preferences/local/$id" ]] && continue
      echo "    keep this Mac's Alfred settings ($id)"
      run cp -R "$d" "$REPO_PREFS/preferences/local/$id"
    done
  fi
  link alfred/Alfred.alfredpreferences "$ALFRED_PREFS"
  if ((alfred_running)); then run open -b com.runningwithcrayons.Alfred; fi
fi
# mp3book — the workflow shells out to it (private repo; https so a read-only
# token is enough, rather than handing the machine an ssh key)
MP3BOOK_REPO="git+https://github.com/malikwashington/mp3book"
if ! command -v mp3book >/dev/null; then
  if command -v uv >/dev/null; then
    echo "    uv tool install mp3book"
    run uv tool install "$MP3BOOK_REPO" || warn "mp3book install failed (gh auth login, or a read-only token?)"
  else
    warn "mp3book missing: uv tool install $MP3BOOK_REPO"
  fi
fi

# --- alfred workflow dependencies ------------------------------------------
# Each workflow shells out to things Alfred can't install. Without them a
# workflow links fine and then fails silently, so name what's missing and say
# which workflow it belongs to. Everything here is in the Brewfile, so a
# miss means brew bundle didn't run or didn't finish.
say "alfred dependencies"
ALFRED_DEPS=(
  "mp3book|mp3book ffmpeg ffprobe"
  "clc|insect"
  "Calculate Anything|php"
  "Homebrew|brew"
  "desk|python3"
  "Mouseless Messenger|sqlite3"
  "BlueScope|blueutil"
  "Search Alfred Workflows|python3"
  "Menu Bar Search|swift"             # builds its helper on first run
  "Dash|Dash.app"                     # from Setapp, so brew can't supply it
)
((DRY)) || DEPS="$(mktemp)"
dep_missing=0
for spec in "${ALFRED_DEPS[@]}"; do
  wf="${spec%%|*}"
  miss=()
  for dep in ${spec#*|}; do
    # a *.app dep is an application, looked for where Setapp and casks put them
    if [[ "$dep" == *.app ]]; then
      found=0
      for d in /Applications /Applications/Setapp "$HOME/Applications"; do
        [[ -d "$d/$dep" ]] && found=1
      done
    else
      command -v "$dep" >/dev/null && found=1 || found=0
    fi
    if ((found)); then
      [[ -n "$DEPS" ]] && printf '%s\t%s\tpresent\n' "$wf" "$dep" >> "$DEPS"
    else
      miss+=("$dep")
      [[ -n "$DEPS" ]] && printf '%s\t%s\tmissing\n' "$wf" "$dep" >> "$DEPS"
    fi
  done
  if ((${#miss[@]})); then
    warn "$wf needs: ${miss[*]}"
    dep_missing=$((dep_missing + ${#miss[@]}))
  else
    echo "    ok  $wf"
  fi
done
if ((dep_missing)); then
  warn "$dep_missing dependency(ies) missing — run brew bundle, or see the Brewfile (apps: install from Setapp)"
else
  echo "    all workflow dependencies present"
fi
# Mouseless Messenger reads ~/Library/Messages/chat.db, which no package can
# provide: Alfred needs Full Disk Access. Not testable from here — macOS grants
# that per application, so this shell being unable to read the file says nothing
# about whether Alfred can. Stated once rather than checked.
echo "    note: Mouseless Messenger needs Full Disk Access for Alfred (grant once, in System Settings)"

# --- stale links ------------------------------------------------------------
# A file removed from this repo (the old iTerm2 config, say) leaves a link to
# nothing on machines an older install.sh set up. Only links into this repo
# whose target is gone are removed.
say "stale links"
stale=0
while IFS= read -r l; do
  t="$(readlink "$l")"
  [[ "$t" == "$DOTFILES"/* && ! -e "$l" ]] || continue
  echo "    rm  $l (pointed at ${t#"$DOTFILES"/}, no longer in the repo)"
  record remove "$l" symlink "$t" "" "" ""
  run rm "$l"; stale=$((stale+1))
done < <(find "$HOME" "$HOME/.config" "$HOME/Library/Application Support/iTerm2" \
           -maxdepth 3 -type l 2>/dev/null | sort -u)
((stale)) || echo "    none"

say record
write_manifest

say done
((DRY)) && echo "    (dry run: nothing changed)"
cat <<'EOF'
    If Karabiner or Alfred can't read their settings, grant them access in
    System Settings > Privacy & Security > Files and Folders (this repo is in
    ~/Documents). Mouseless Messenger needs Full Disk Access for Alfred
    instead — it reads the Messages database directly.
EOF
