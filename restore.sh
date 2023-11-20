git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote &
yay -S --rebuild --answerclean A --answerdiff N $(checkrebuild | cut -d$'\t' -f2)
yes | yay -Sc
yes | yay -Scc
cp ~/dotfiles/zshrc ~/.zshrc
cp ~/dotfiles/zsh_plugins.txt ~/.zsh_plugins.txt
mkdir ~/.config/nvim
cp ~/dotfiles/init.lua ~/.config/nvim
cp -r ~/dotfiles/templates ~/.config/nvim/templates
bash -c  "$(wget -qO- https://git.io/vQgMr)"
zsh
brew install powerlevel10k gcc
cargo install cargo-cache
sudo ufw enable
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw reload
