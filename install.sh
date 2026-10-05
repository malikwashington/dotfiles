#!/usr/bin/env bash
# install.sh — link these dotfiles into ~. Safe to re-run.
# Existing links are repointed; real files/dirs in the way are moved to <name>.bak-<timestamp>.
# Usage: ./install.sh [--dry-run]
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d%H%M%S)"
DRY=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY=1

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
run()  { if ((DRY)); then echo "    [dry-run] $*"; else "$@"; fi; }

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
  run mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" ]]; then
    echo "    fix $dst (was -> $(readlink "$dst"))"
    run rm "$dst"
  elif [[ -e "$dst" ]]; then
    backup "$dst"
  fi
  echo "    new $dst -> $src"
  run ln -s "$src" "$dst"
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
  echo "    brew bundle (see Brewfile)"
  run brew bundle install --file="$DOTFILES/Brewfile" --no-upgrade
else
  warn "skipping Brewfile: no brew on PATH"
fi

# --- zsh -------------------------------------------------------------------
say zsh
link zsh/zshrc "$HOME/.zshrc"
if [[ ! -e "$HOME/.zshrc.local" ]]; then
  echo "    new ~/.zshrc.local from example (edit it)"
  run cp "$DOTFILES/zsh/zshrc.local.example" "$HOME/.zshrc.local"
fi

# --- vim -------------------------------------------------------------------
say vim
# vim reads ~/.vim/vimrc, but ~/.vimrc would take precedence: remove the old link
if [[ -L "$HOME/.vimrc" ]]; then
  echo "    rm  ~/.vimrc (old link, vim now reads ~/.vim/vimrc)"
  run rm "$HOME/.vimrc"
elif [[ -e "$HOME/.vimrc" ]]; then
  backup "$HOME/.vimrc"
fi
# carry over file-browser history before ~/.vim is moved aside
if [[ -d "$HOME/.vim" && ! -L "$HOME/.vim" && -f "$HOME/.vim/.netrwhist" && ! -e "$DOTFILES/vim/.netrwhist" ]]; then
  run cp "$HOME/.vim/.netrwhist" "$DOTFILES/vim/.netrwhist"
fi
link vim "$HOME/.vim"
if command -v vim >/dev/null; then
  echo "    installing plugins"
  run vim -N -u "$DOTFILES/vim/vimrc" -i NONE -es -c 'PlugInstall --sync' -c 'qa!' </dev/null >/dev/null 2>&1 || warn "PlugInstall failed; open vim to retry"
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
if command -v ya >/dev/null; then
  echo "    ya pkg install"
  run ya pkg install >/dev/null || warn "ya pkg install failed"
else
  warn "yazi not installed: brew install yazi, then re-run"
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

say done
((DRY)) && echo "    (dry run: nothing changed)"
cat <<'EOF'
    If Karabiner or Alfred can't read their settings, grant them access
    in System Settings > Privacy & Security > Files and Folders (this repo is in ~/Documents).
EOF
