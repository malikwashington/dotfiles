# dotfiles

Personal config, symlinked into `~`. Machine-specific bits go in `~/.zshrc.local` (untracked).

## Install on a new Mac

```sh
git clone git@github.com:malikwashington/dotfiles.git ~/dotfiles
cd ~/dotfiles

# zsh (requires oh-my-zsh: https://ohmyz.sh)
ln -sf ~/dotfiles/zsh/zshrc ~/.zshrc
cp -n zsh/zshrc.local.example ~/.zshrc.local   # then edit

# vim (run :PlugInstall on first launch)
ln -sf ~/dotfiles/vim/vimrc ~/.vimrc
mkdir -p ~/.vim/autoload && ln -sf ~/dotfiles/vim/autoload/plug.vim ~/.vim/autoload/plug.vim

# tmux
mkdir -p ~/.config/tmux && ln -sf ~/dotfiles/tmux/tmux.conf ~/.config/tmux/tmux.conf

# yazi (brew install yazi; flavors are fetched from package.toml, not tracked)
mkdir -p ~/.config/yazi && ln -sf ~/dotfiles/yazi/theme.toml ~/.config/yazi/theme.toml && ln -sf ~/dotfiles/yazi/package.toml ~/.config/yazi/package.toml
ya pkg install

# karabiner
mkdir -p ~/.config/karabiner && ln -sf ~/dotfiles/karabiner/karabiner.json ~/.config/karabiner/karabiner.json

# hidutil key remap (loads at login)
cp hidutil/com.local.KeyRemapping.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.local.KeyRemapping.plist

# alfred (quit Alfred first; then relaunch). 1Password workflow: reinstall from the Alfred Gallery.
rm -rf ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences
ln -s ~/dotfiles/alfred/Alfred.alfredpreferences ~/Library/Application\ Support/Alfred/Alfred.alfredpreferences
```

## Layout

| dir | linked to |
|---|---|
| `zsh/` | `~/.zshrc` |
| `vim/` | `~/.vimrc`, `~/.vim/autoload/plug.vim` |
| `tmux/` | `~/.config/tmux/tmux.conf` |
| `yazi/` | `~/.config/yazi/{theme,package}.toml` (flavors installed via `ya pkg install`) |
| `karabiner/` | `~/.config/karabiner/karabiner.json` |
| `hidutil/` | `~/Library/LaunchAgents/` (copied, not linked) |
| `alfred/` | `~/Library/Application Support/Alfred/Alfred.alfredpreferences` |

## Alfred notes

Tracked workflows: mp3book (mine), clc, Temporary Email, and Calculate Anything. Calculate Anything is deprecated upstream and carries local fixes, so it is kept in full. The 1Password workflow is gitignored; install it from the Gallery.
The `mp3book` workflow needs the `mp3book` tool: `uv tool install mp3book`.
