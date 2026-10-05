# dotfiles

Personal config, symlinked into `~`. Machine-specific bits go in `~/.zshrc.local` (untracked).

## Install

```sh
git clone git@github.com:malikwashington/dotfiles.git ~/Documents/dotfiles
~/Documents/dotfiles/install.sh --dry-run   # preview
~/Documents/dotfiles/install.sh
```

`install.sh` installs everything in [`Brewfile`](Brewfile) first (Homebrew itself is the only
prerequisite), then links the configs. To change what a fresh Mac gets, edit `Brewfile` and
re-run. `brew bundle dump --force` rewrites it from what's currently installed;
`brew bundle cleanup` lists what's installed but no longer tracked.

Safe to re-run (e.g. after pulling, or if the repo moves): links are repointed, anything in the way is moved to `<name>.bak-<timestamp>`, and this Mac's Alfred local settings are copied into the repo before Alfred is linked. The manual equivalent:

```sh
git clone git@github.com:malikwashington/dotfiles.git ~/Documents/dotfiles
cd ~/Documents/dotfiles

# packages
brew bundle install --file=Brewfile

# zsh
ln -sf ~/Documents/dotfiles/zsh/zshrc ~/.zshrc
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
| `tmux/` | `~/.config/tmux/tmux.conf` |
| `yazi/` | `~/.config/yazi/{theme,package}.toml` (flavors installed via `ya pkg install`) |
| `karabiner/` | `~/.config/karabiner` (whole dir) |
| `hidutil/` | not installed — reference only (see below) |
| `alfred/` | `~/Library/Application Support/Alfred/Alfred.alfredpreferences` |

## Alfred notes

Tracked workflows: mp3book (mine), clc, Temporary Email, and Calculate Anything. Calculate Anything is deprecated upstream and carries local fixes, so it is kept in full. The 1Password workflow is gitignored; install it from the Gallery.
The `mp3book` workflow needs the `mp3book` tool: `uv tool install mp3book`.

## hidutil notes

`hidutil/com.local.KeyRemapping.plist` is kept for reference and is **not** installed by `install.sh`. It's a LaunchAgent that swaps Caps Lock and Escape at login using macOS's built-in `hidutil`, without Karabiner. To use it by hand:

```sh
cp hidutil/com.local.KeyRemapping.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.local.KeyRemapping.plist
```
