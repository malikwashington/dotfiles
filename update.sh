#!/usr/bin/env bash
# update.sh — bring this machine's tools and the repos up to date. Safe to run
# on a managed (work) Mac: it only updates what is already installed.
#
# What it will NEVER do, on any machine:
#   - use sudo, or change system settings, launch agents or login items
#   - touch ~/.gitconfig, ~/.ssh, the keychain, 1Password, or gh's login
#     (no `gh auth`, no `op`, no `ssh-add`, no credential helpers)
#   - prompt for a password: git runs with prompts off and a repo it can't
#     reach with the access the machine already has is skipped
#   - relink configs (that's install.sh's job)
# On a managed Mac (MDM-enrolled) it also never installs anything new: Brewfile
# entries that are missing are listed, not installed.
#
# Everything it prints is also written to ~/.local/state/dotfiles/update-*.log,
# so there is a record of exactly what ran.
#
# Usage: ./update.sh [--dry-run] [--managed | --personal]
#   --dry-run    show what would happen
#   --managed    treat this Mac as managed even if it isn't MDM-enrolled
#   --personal   treat it as personal (installs missing Brewfile entries)
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"
DRY=0 MODE=""
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY=1 ;;
    --managed)    MODE=managed ;;
    --personal)   MODE=personal ;;
    *) echo "usage: $0 [--dry-run] [--managed | --personal]" >&2; exit 2 ;;
  esac
done

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
run()  { if ((DRY)); then echo "    [dry-run] $*"; else "$@"; fi; }

# no git or gh prompt may ever appear; a missing credential is a skip, not a question
export GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=never GH_PROMPT_DISABLED=1
export HOMEBREW_NO_ENV_HINTS=1

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
if ((DRY)); then
  LOG=""
else
  mkdir -p "$STATE_DIR"
  LOG="$STATE_DIR/update-$STAMP.log"
  exec > >(tee -a "$LOG") 2>&1
fi

if [[ -z "$MODE" ]]; then
  if profiles status -type enrollment 2>/dev/null | grep -q 'MDM enrollment: Yes'; then
    MODE=managed
  else
    MODE=personal
  fi
fi
say "mode: $MODE$( [[ $MODE == managed ]] && echo ' (updates only; nothing new is installed)')"

FAILED=()

# pull <dir>: fast-forward only, never over local changes. Sets MOVED=1 if HEAD changed.
pull() {
  local dir="$1" before after
  MOVED=0
  [[ -d "$dir/.git" ]] || return 0
  if [[ -n "$(git -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)" ]]; then
    warn "$dir has local changes; not pulling"; return 0
  fi
  if ((DRY)); then echo "    [dry-run] git -C $dir pull --ff-only"; return 0; fi
  before="$(git -C "$dir" rev-parse HEAD)"
  if ! git -C "$dir" pull --ff-only --quiet; then
    warn "couldn't pull $dir (no access with this machine's existing credentials, or it diverged); skipped"
    FAILED+=("pull $dir"); return 0
  fi
  after="$(git -C "$dir" rev-parse HEAD)"
  if [[ "$before" != "$after" ]]; then
    git -C "$dir" log --oneline "$before..$after" | sed 's/^/    /'; MOVED=1
  else
    echo "    up to date"
  fi
}

# --- dotfiles ----------------------------------------------------------------
say dotfiles
pull "$DOTFILES"
# configs are symlinks into this repo, so a pull is already live — except new
# links install.sh would create, which it reports rather than doing itself
if ((MOVED)); then
  echo "    pulled; linked configs (zsh, vim, tmux, karabiner, git, alfred…) are live now"
  echo "    if a commit added a new link, run ./install.sh for it"
fi

# --- cli-tools: pull, and rebuild only if something changed -------------------
CLI_TOOLS="$HOME/Documents/cli-tools"
if [[ -d "$CLI_TOOLS/.git" ]]; then
  say cli-tools
  pull "$CLI_TOOLS"
  if ((MOVED)); then
    while IFS= read -r manifest; do
      d="$(dirname "$manifest")"; name="${d#"$CLI_TOOLS"/}"
      if [[ -f "$d/go.mod" ]] && command -v go >/dev/null; then
        if ((DRY)) || (cd "$d" && go install .) 2>/dev/null; then echo "    built $name"
        else warn "$name failed to build"; FAILED+=("build $name"); fi
      elif [[ -f "$d/Cargo.toml" ]] && command -v cargo >/dev/null; then
        if ((DRY)) || (cd "$d" && cargo install --path . --quiet) 2>/dev/null; then echo "    built $name"
        else warn "$name failed to build"; FAILED+=("build $name"); fi
      fi
    done < <(find "$CLI_TOOLS" -maxdepth 4 -type f \( -name go.mod -o -name Cargo.toml \) \
               -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/vendor/*' 2>/dev/null | sort)
  fi
fi

# --- homebrew: upgrade what's installed; add missing only on a personal Mac ---
if command -v brew >/dev/null; then
  say homebrew
  run brew update --quiet || { warn "brew update failed"; FAILED+=("brew update"); }
  # casks that update themselves (auto_updates) are left to their own updaters
  run brew upgrade || { warn "brew upgrade had failures"; FAILED+=("brew upgrade"); }
  # what the Brewfile lists but isn't installed at all (outdated ≠ missing)
  have_f="$(brew list --formula -1 2>/dev/null)"; have_c="$(brew list --cask -1 2>/dev/null)"
  missing=""
  while read -r kind name _; do
    name="${name//\"/}"; name="${name%,}"
    case "$kind" in
      brew) grep -qx "${name##*/}" <<<"$have_f" || missing+="formula $name"$'\n' ;;
      cask) grep -qx "$name" <<<"$have_c" || missing+="cask $name"$'\n' ;;
    esac
  done < <(grep -E '^(brew|cask) "' "$DOTFILES/Brewfile")
  missing="${missing%$'\n'}"
  if [[ -n "$missing" ]]; then
    if [[ $MODE == managed ]]; then
      warn "in the Brewfile but not installed here (left alone on a managed Mac):"
      echo "$missing" | sed 's/^/      /'
      echo "    install any your IT allows with: brew install [--cask] <name>"
    else
      echo "    installing Brewfile entries missing here:"
      echo "$missing" | sed 's/^/      /'
      run brew bundle install --file="$DOTFILES/Brewfile" --no-upgrade --quiet \
        || { warn "brew bundle had failures"; FAILED+=("brew bundle"); }
    fi
  fi
fi

# --- language toolchains and tool managers -------------------------------------
RUSTUP_BIN="${HOMEBREW_PREFIX:-/opt/homebrew}/opt/rustup/bin"
[[ -d "$RUSTUP_BIN" ]] && PATH="$RUSTUP_BIN:$PATH"
if command -v rustup >/dev/null && rustup toolchain list 2>/dev/null | grep -q .; then
  say rust
  run rustup update --no-self-update 2>&1 | grep -E 'updated|unchanged' | sed 's/^/    /' || true
fi
if command -v uv >/dev/null && [[ -n "$(uv tool list 2>/dev/null)" ]]; then
  say "uv tools"
  run uv tool upgrade --all || { warn "uv tool upgrade had failures (a private repo this machine can't reach?)"; FAILED+=("uv tools"); }
fi
if command -v gh >/dev/null && [[ -n "$(gh extension list 2>/dev/null)" ]]; then
  say "gh extensions"
  run gh extension upgrade --all || { warn "gh extension upgrade had failures"; FAILED+=("gh extensions"); }
fi

# --- editor and file-manager plugins -----------------------------------------
if command -v vim >/dev/null && [[ -d "$DOTFILES/vim/plugged" ]]; then
  say "vim plugins"
  run vim -N -u "$DOTFILES/vim/vimrc" -i NONE -es -c 'PlugUpdate --sync' -c 'qa!' </dev/null >/dev/null 2>&1 \
    || { warn "PlugUpdate failed; open vim and run :PlugUpdate"; FAILED+=("vim plugins"); }
fi
if command -v ya >/dev/null; then
  say "yazi packages"
  run ya pkg upgrade >/dev/null || { warn "ya pkg upgrade failed"; FAILED+=("yazi"); }
fi

# --- summary ----------------------------------------------------------------
say done
if ((${#FAILED[@]})); then
  warn "${#FAILED[@]} step(s) had problems: ${FAILED[*]}"
fi
((DRY)) && echo "    (dry run: nothing changed)"
[[ -n "$LOG" ]] && echo "    log: $LOG"
exit 0
