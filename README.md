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

# karabiner
mkdir -p ~/.config/karabiner && ln -sf ~/dotfiles/karabiner/karabiner.json ~/.config/karabiner/karabiner.json

# hidutil key remap (loads at login)
cp hidutil/com.local.KeyRemapping.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.local.KeyRemapping.plist
```

## Layout

| dir | linked to |
|---|---|
| `zsh/` | `~/.zshrc` |
| `vim/` | `~/.vimrc`, `~/.vim/autoload/plug.vim` |
| `tmux/` | `~/.config/tmux/tmux.conf` |
| `karabiner/` | `~/.config/karabiner/karabiner.json` |
| `hidutil/` | `~/Library/LaunchAgents/` (copied, not linked) |
