git clone https://aur.archlinux.org/yay-git
cd yay-git
makepkg -si
cd ..
rm -rf yay-git
yay --needed -Syu $(cat packages/aurlist.txt | xargs)
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
yes | yay -Sc
yes | yay -Scc
cp -r nvim ~/.config
cp activate-linux.sh ~/
cp clang-format ~/.clang-format
cp gitconfig ~/.gitconfig
cp pip.conf ~/.config/pip
cp theme.sh ~/
cp topgrade.toml ~/.config
cp zsh_plugins.txt ~/.zsh_plugins.txt
cp zshbookmarks ~/.zshbookmarks
cp zshenv ~/.zshenv
cp zshrc ~/.zshrc
source ~/.zshrc
rm ~/.gnupg/{S.keyboxd,public-keys.d/pubring.db.lock}
