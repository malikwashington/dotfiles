# dotfiles

Personal config, symlinked into `~`. Machine-specific bits go in `~/.zshrc.local` (untracked).

## Install

```sh
git clone https://github.com/malikwashington/dotfiles.git ~/Documents/dotfiles
~/Documents/dotfiles/install.sh --dry-run   # preview
~/Documents/dotfiles/install.sh
```

`install.sh` installs everything in [`Brewfile`](Brewfile) first (Homebrew itself is the only
prerequisite), then links the configs. To change what a fresh Mac gets, edit `Brewfile` and
re-run. `brew bundle dump --force` rewrites it from what's currently installed;
`brew bundle cleanup` lists what's installed but no longer tracked.

GitHub CLI extensions are listed in `GH_EXTENSIONS` in `install.sh` (currently
[`gh-dash`](https://github.com/dlvhdr/gh-dash), run as `gh dash`, and
[`gh-enhance`](https://github.com/dlvhdr/gh-enhance), a GitHub Actions TUI run as `gh enhance`); missing ones are installed.

It also clones [`cli-tools`](https://github.com/malikwashington/cli-tools) to
`~/Documents/cli-tools` (or pulls it if already there) and builds the tools in it.
They're grouped by language — `cli-tools/go/<tool>`, `cli-tools/Rust/<tool>` — and
each is found by looking for its `go.mod` or `Cargo.toml` rather than by a fixed
path, so adding a tool needs no change here. Go builds land in `$GOPATH/bin`, Rust
in `$CARGO_HOME/bin`, both already on `PATH`. A tool that fails to build is
reported and skipped rather than stopping the install.

## Updating

```sh
./update.sh --dry-run   # preview
./update.sh             # pull the repos, upgrade brew/rust/uv/gh extensions/vim/yazi
```

Safe on a work Mac: it never uses sudo, never touches `~/.gitconfig`, `~/.ssh`,
the keychain, 1Password or gh's login, and never prompts for a password (a repo
it can't reach with the access the machine already has is skipped). On an
MDM-enrolled Mac it installs nothing new: Brewfile entries that are missing are
listed, not installed. `--managed` / `--personal` override the detection. Each
run is logged to `~/.local/state/dotfiles/update-<timestamp>.log`.

## Undoing it

`install.sh` records every change it makes in `$HOME` to
`~/.local/state/dotfiles/install.json`, and tees each run to a log beside it.

```sh
./uninstall.sh --dry-run   # preview
./uninstall.sh             # configs back to original, cli-tools and its binaries removed
./uninstall.sh --full      # also remove the Homebrew packages this repo installed
```

`signoff` (a zsh function) does the same plus dropping every credential, for
walking away from a machine: `signoff`, `signoff --full`, `-y` to skip the prompt.

Safe to re-run (e.g. after pulling, or if the repo moves): links are repointed, anything in the way is moved to `<name>.bak-<timestamp>`, and this Mac's Alfred local settings are copied into the repo before Alfred is linked. The manual equivalent:

```sh
git clone https://github.com/malikwashington/dotfiles.git ~/Documents/dotfiles
cd ~/Documents/dotfiles

# packages
brew bundle install --file=Brewfile

# zsh
ln -sf ~/Documents/dotfiles/zsh/zshrc ~/.zshrc

# git (shared settings only; ~/.gitconfig stays this machine's own)
mkdir -p ~/.config/git
ln -sf ~/Documents/dotfiles/git/gitconfig ~/.config/git/config
cp -n zsh/zshrc.local.example ~/.zshrc.local   # then edit

# vim (missing plugins install automatically on first launch)
ln -s ~/Documents/dotfiles/vim ~/.vim   # vim reads ~/.vim/vimrc; plugins land in vim/plugged (ignored)

# tmux
mkdir -p ~/.config/tmux && ln -sf ~/Documents/dotfiles/tmux/tmux.conf ~/.config/tmux/tmux.conf

# yazi (brew install yazi; flavors are fetched from package.toml, not tracked)
mkdir -p ~/.config/yazi && ln -sf ~/Documents/dotfiles/yazi/theme.toml ~/.config/yazi/theme.toml && ln -sf ~/Documents/dotfiles/yazi/package.toml ~/.config/yazi/package.toml
ya pkg install

# karabiner — link the whole dir (Karabiner's GUI saves by replacing
# karabiner.json, which breaks a file-level symlink). Do this before first launch.
ln -s ~/Documents/dotfiles/karabiner ~/.config/karabiner

# alfred (quit Alfred first; then relaunch; Calculate Anything needs `brew install php`). 1Password workflow: reinstall from the Alfred Gallery.
rm -rf ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences
ln -s ~/Documents/dotfiles/alfred/Alfred.alfredpreferences ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences
```

## Layout

| dir | linked to |
|---|---|
| `zsh/` | `~/.zshrc` |
| `vim/` | `~/.vim` (whole dir) |
| `git/` | `~/.config/git/config` (delta, colours; never `~/.gitconfig`, which keeps each machine's identity and credentials) |
| `tmux/` | `~/.config/tmux/tmux.conf` |
| `yazi/` | `~/.config/yazi/{theme,package}.toml` (flavors installed via `ya pkg install`) |
| `karabiner/` | `~/.config/karabiner` (whole dir) |
| `hidutil/` | not installed — reference only (see below) |
| `alfred/` | `~/Library/Application Support/Alfred/Alfred.alfredpreferences` |

## Alfred notes

Tracked workflows: mp3book (mine), Alfred Gallery, BlueScope, Calculate Anything, clc, Dash, desk, Go to Here, Homebrew, Menu Bar Search, Mouseless Messenger, Search Alfred Workflows, and Temporary Email. Calculate Anything is deprecated upstream and carries local fixes, so it is kept in full. Gitignored, reinstall by hand: 1Password (from the Gallery) and Emoji picker (~59MB; from [GitHub](https://github.com/devnoname120/alfred-emoji-picker)). Dash workflow needs Dash.app, installed through Setapp, not Homebrew.
The `mp3book` workflow needs the `mp3book` tool: `uv tool install mp3book`.

## Keyboard (Karabiner)

| Keys | Does |
|---|---|
| Caps Lock tap / hold | Escape (tap within 200ms) / Control (with another key) |
| Shift + Caps Lock | real Caps Lock |
| Both Shifts held | symbol/number layer (QWERTY row → 1–0, home row → brackets and operators) |
| Left Control + H / L | switch Space left / right (Ctrl+← / →) |
| Left Control + K / J | Mission Control / current app's windows (Ctrl+↑ / ↓) |
| ⌘⇥ (BetterCmdTab) | switcher stays open; H/J/K/L move, Return picks, Esc cancels |
| ⌘⇥, keep ⌘ held, J | the app's windows; H/L step, release ⌘ to pick, Esc goes back |

Caps Lock's Control is left alone, so Ctrl+H/J/K/L keep their terminal meanings
when typed with Caps Lock. Only the physical left Control key gets the Space and
Mission Control bindings. BetterCmdTab's settings are applied by `install.sh`.

## hidutil notes

`hidutil/com.local.KeyRemapping.plist` is kept for reference and is **not** installed by `install.sh`. It's a LaunchAgent that swaps Caps Lock and Escape at login using macOS's built-in `hidutil`, without Karabiner. To use it by hand:

```sh
cp hidutil/com.local.KeyRemapping.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.KeyRemapping.plist
```
