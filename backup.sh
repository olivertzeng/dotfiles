sudo pacman -Syu
sudo pacman -Sy - < packages/pkglist.txt
debtap -u
git clone https://aur.archlinux.org/yay-git.git
cd yay-git
makepkg -si      
cd
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
yay -Sy - < packages/aurlist.txt
yay -Syu
gh auth login
git clone git@github.com:olivertzeng/Silica.git
git clone git@github.com:olivertzeng/dotfiles.git
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
cp dotfiles/vimrc ~/.vimrc
cp dotfiles/zshrc ~/.zshrc
sudo cp dotfiles/paccache.timer /dotfiles /etc/systemd/system/paccache.timer
sudo cp dotfiles/paccache.hook /usr/share/libalpm/hooks/paccache.hook
echo "export THEOS=~/theos" >> ~/.profile
curl -LO https://github.com/CRKatri/llvm-project/releases/download/swift-5.3.2-RELEASE/swift-5.3.2-RELEASE-ubuntu20.04.tar.zst
TMP=$(mktemp -d)
tar -xvf swift-5.3.2-RELEASE-ubuntu20.04.tar.zst -C $TMP
mkdir -p $THEOS/toolchain/linux/iphone $THEOS/toolchain/swift
mv $TMP/swift-5.3.2-RELEASE-ubuntu20.04/* $THEOS/toolchain/linux/iphone/
ln -s $THEOS/toolchain/linux/iphone $THEOS/toolchain/swift
rm -r swift-5.3.2-RELEASE-ubuntu20.04.tar.zst $TMP
# Cleaning Up
sudo pacman -Sc
sudo pacman -Scc
yay -Sc
yay -Scc
sudo pacman -Rns $(pacman -Qtdq)
rmlint
sudo rm -rf ~/.cache/*
sh -c /home/olivertzeng/rmlint.sh
