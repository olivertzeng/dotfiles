git clone https://aur.archlinux.org/yay-git
cd yay-git
makepkg -si
cd ..
rm -rf yay-git
yay --needed -Syu $(cat packages/aurlist.txt | xargs)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
yes | yay -Sc
yes | yay -Scc
cp zshrc ~/.zshrc
cp zsh_plugins.txt ~/.zsh_plugins.txt
cp -r nvim ~/.config
source ~/.zshrc
brew install powerlevel10k pipx gcc
