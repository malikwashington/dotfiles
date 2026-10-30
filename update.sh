#!/usr/bin/env bash
# update.sh — sync this machine with the setup used elsewhere: pull this repo
# (linked configs are live at once) and install whatever the Brewfile lists
# that isn't here yet. It doesn't upgrade anything, and it doesn't run
# install.sh; run that yourself on a fresh Mac or for new links.
#
# What it will NEVER do, on any machine:
#   - use sudo, or change system settings, launch agents or login items
#   - touch ~/.gitconfig, ~/.ssh, the keychain, 1Password, or gh's login
#     (no `gh auth`, no `op`, no `ssh-add`, no credential helpers)
#   - prompt for a password: git runs with prompts off and a repo it can't
#     reach with the access the machine already has is skipped
#
# Everything it prints is also written to ~/.local/state/dotfiles/update-*.log,
# so there is a record of exactly what ran.
#
# Usage: ./update.sh [--dry-run]
#   --dry-run    show what would happen
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
# configs are symlinks into this repo, so a pull is live at once
((MOVED)) && echo "    pulled; linked configs are live now"

# --- homebrew: install what the Brewfile lists but isn't here ----------------
# Only what's missing. Nothing already installed is upgraded, and install.sh
# isn't run: no links, plugins, toolchains or app settings are touched.
if command -v brew >/dev/null; then
  say homebrew
  have_f="$(brew list --formula -1 2>/dev/null)"; have_c="$(brew list --cask -1 2>/dev/null)"
  missing=""
  while read -r kind name _; do
    name="${name//\"/}"; name="${name%,}"
    case "$kind" in
      brew) grep -qx "${name##*/}" <<<"$have_f" || missing+="formula $name"$'\n' ;;
      cask) grep -qx "${name##*/}" <<<"$have_c" || missing+="cask $name"$'\n' ;;
    esac
  done < <(grep -E '^(brew|cask) "' "$DOTFILES/Brewfile")
  missing="${missing%$'\n'}"
  if [[ -n "$missing" ]]; then
    echo "    installing Brewfile entries missing here:"
    echo "$missing" | sed 's/^/      /'
    run brew bundle install --file="$DOTFILES/Brewfile" --no-upgrade --quiet \
      || { warn "brew bundle had failures"; FAILED+=("brew bundle"); }
  else
    echo "    everything in the Brewfile is installed"
  fi
else
  warn "no brew on PATH; nothing installed"
fi

# --- summary ----------------------------------------------------------------
say done
if ((${#FAILED[@]})); then
  warn "${#FAILED[@]} step(s) had problems: ${FAILED[*]}"
fi
((DRY)) && echo "    (dry run: nothing changed)"
[[ -n "$LOG" ]] && echo "    log: $LOG"
exit 0
