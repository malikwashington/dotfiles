# Brewfile — everything a fresh Mac needs. Installed by ./install.sh via `brew bundle`.
#
# Add or remove a line, then re-run ./install.sh (it's idempotent).
# To sync this file from what's actually installed:  brew bundle dump --force
# To see what's installed but not listed here:       brew bundle cleanup
# To uninstall everything not listed here:           brew bundle cleanup --force

# ---------- shell ----------
brew "zsh-autosuggestions"          # greyed-out suggestion; Tab accepts it (see zsh/zshrc)
brew "zsh-syntax-highlighting"
brew "zsh-you-should-use"            # reminds you when an alias exists for what you typed
brew "starship"                     # prompt
brew "zoxide"                       # z — frecency-ranked cd
brew "direnv"                       # per-directory env via .envrc
brew "fzf"                          # fuzzy finder; powers ctrl-r and fcd()

# ---------- core cli ----------
brew "eza"                          # ls
brew "bat"                          # cat
brew "fd"                           # find
brew "ripgrep"                      # grep
brew "htop"
brew "wget"
brew "httpie"
brew "jq"
brew "glow"                         # render markdown in the terminal
brew "yazi"                         # file manager; y() wrapper in zsh/zshrc
brew "tmux"

# ---------- git ----------
brew "git"
brew "git-delta"                    # diff pager (git/gitconfig sets core.pager = delta)
brew "lazygit"
brew "gh"

# ---------- languages / version managers ----------
brew "pyenv"                        # python
brew "uv"                           # python packaging; also `uv tool install`
brew "pipx"
brew "fnm"                          # node
brew "node"
brew "go"
brew "rustup"
brew "php"                          # required by Alfred's Calculate Anything workflow

# ---------- agents / ai ----------
brew "herdr"                        # agent multiplexer; aliased to `h`

# ---------- my own go tools ----------
# logq, notify and portkill live in github.com/malikwashington/cli-tools and are
# built from source by install.sh. They're bare modules ("module portkill"), not
# fetchable paths, so brew/go install can't resolve them by name.

# ---------- alfred workflow dependencies ----------
# These are what the workflows shell out to. Without them a workflow links
# fine and then fails silently, so install.sh verifies them by name.
brew "ffmpeg"                       # mp3book: ffprobe for chapter lengths, ffmpeg to build the .m4b
brew "insect"                       # clc: the calculator it pipes the query into
brew "blueutil"                     # BlueScope: Bluetooth on/off/connect from the command line
# php (above) is Calculate Anything; brew itself is the Homebrew workflow.
# Dash (the Dash workflow) comes from Setapp; install.sh checks it's there.

# ---------- apps ----------
cask "ghostty"                      # terminal (GPU-accelerated)
cask "bettercmdtab"                 # Cmd+Tab replacement: stays open after Cmd is released, hjkl to move
cask "1password-cli"                # op — bin/sheet reads its creds from 1Password
cask "copilot-cli"                  # aliased to `co`
# cask "docker-desktop"            # off for now; re-enable when you want Docker back

# ---------- fonts (nerd fonts: starship and yazi need the glyphs) ----------
cask "font-fira-code-nerd-font"
cask "font-jetbrains-mono-nerd-font"
