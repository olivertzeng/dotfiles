git clone https://aur.archlinux.org/yay-git
cd yay-git
makepkg -si
cd ..
rm -rf yay-git
yay --needed -Syu $(cat packages/aurlist.txt | xargs)
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
yes | yay -Sc
yes | yay -Scc
cp zshrc ~/.zshrc
cp zsh_plugins.txt ~/.zsh_plugins.txt
cp -r nvim ~/.config
source ~/.zshrc
rm ~/.gnupg/{S.keyboxd,public-keys.d/pubring.db.lock}
