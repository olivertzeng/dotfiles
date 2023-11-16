cd
git clone https://aur.archlinux.org/yay.git &
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote &
wait
cd yay
makepkg -si      
cd ..
rm -rf yay
yes "" | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
yay -Syyu --noconfirm $(cat -/dotfiles/packages/aurlist.txt | xargs)
yay -S --rebuild --answerclean A --answerdiff N $(checkrebuild | cut -d$'\t' -f2)
gum confirm "Are AUR okay?" || exit 1
yes | yay -Sc
yes | yay -Scc
cp ~/dotfiles/zshrc ~/.zshrc
cp ~/dotfiles/zsh_plugins.txt ~/.zsh_plugins.txt
cp ~/dotfiles/init.lua ~/.config/nvim/init.lua
cp -r ~/dotfiles/templates ~/.config/nvim/templates
(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> $HOME/.zprofile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
bash -c  "$(wget -qO- https://git.io/vQgMr)"
zsh
brew install powerlevel10k gcc
cargo install cargo-cache
sudo ufw enable
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw reload