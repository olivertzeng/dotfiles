git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si      
cd
rm -rf yay
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
yay -Syyu - < ~/dotfiles/packages/aurlist.txt
git clone https://github.com/olivertzeng/dotfiles.git
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
	https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
bash -c  "$(wget -qO- https://git.io/vQgMr)"
cp ~/dotfiles/vimrc ~/.vimrc
cp ~/dotfiles/zshrc ~/.zshrc
cp ~/dotfiles/zsh_plugins.txt ~/.zsh_plugins.txt
sudo cp ~/dotfiles/pacman.conf /etc/
sudo cp ~/dotfiles/paccache.timer /etc/systemd/system/paccache.timer
sudo cp ~/dotfiles/paccache.hook /usr/share/libalpm/hooks/paccache.hook
sudo pacman -Syyu - < ~/dotfiles/packages/pkglist.txt
p10k configure
sudo ufw enable
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw reload
