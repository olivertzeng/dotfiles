sudo pacman -Syu
sudo pacman -Sy - < packages/pkglist.txt
git clone https://aur.archlinux.org/yay
cd yay-git
makepkg -si      
cd
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
yay -Sy - < packages/aurlist.txt
yay -Syu
git clone git@github.com:olivertzeng/dotfiles.git
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
cp dotfiles/vimrc ~/.vimrc
cp dotfiles/zshrc ~/.zshrc
sudo cp dotfiles/paccache.timer /dotfiles /etc/systemd/system/paccache.timer
sudo cp dotfiles/paccache.hook /usr/share/libalpm/hooks/paccache.hook
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
