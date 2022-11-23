sudo pacman -Sy  --needed rmlint ncdu bleachbit cowsay lolcat fortune-mod qemu libvirt virt-manager bridge-utils bison ebtables edk2-ovmf mlocate docker trash-cli npm nodejs rsync perl unzip base-devel pacman-contrib git svn openssh gettext libnautilus-extension gimp telegram-desktop sl wget discord ibus ibus-chewing vim curl flatpak netctl 
sudo pacman -Syu
debtap -u
git clone https://aur.archlinux.org/yay-git.git
cd yay-git
makepkg -si      
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
yay -Syu
yay -Sy kalu checkra1n-gui checkra1n-cli zstd debtap stacer-bin timeshift pamac-nosnap appimagelauncher
git clone https://github.com/hkbakke/bash-insulter.git bash-insulter
cp bash-insulter/src/bash.command-not-found /etc/
gh auth login
git clone git@github.com:olivertzeng/Silica.git
git clone git@github.com:olivertzeng/dotfiles.git
cd dotfiles
sudo cp vimrc ~/.vimrc
cp zshrc ~/.zshrc
sudo cp paccache.timer /dotfiles /etc/systemd/system/paccache.timer
sudo cp paccache.hook /usr/share/libalpm/hooks/paccache.hook
cd
echo "export THEOS=~/theos" >> ~/.profile
git clone --recursive https://github.com/theos/theos.git $THEOS
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
curl -LO https://github.com/CRKatri/llvm-project/releases/download/swift-5.3.2-RELEASE/swift-5.3.2-RELEASE-ubuntu20.04.tar.zst
TMP=$(mktemp -d)
tar -xvf swift-5.3.2-RELEASE-ubuntu20.04.tar.zst -C $TMP
mkdir -p $THEOS/toolchain/linux/iphone $THEOS/toolchain/swift
mv $TMP/swift-5.3.2-RELEASE-ubuntu20.04/* $THEOS/toolchain/linux/iphone/
ln -s $THEOS/toolchain/linux/iphone $THEOS/toolchain/swift
rm -r swift-5.3.2-RELEASE-ubuntu20.04.tar.zst $TMP
curl -LO https://github.com/theos/sdks/archive/master.zip
TMP=$(mktemp -d)
unzip master.zip -d $TMP
mv $TMP/sdks-master/*.sdk $THEOS/sdks
rm -r master.zip $TMP
sudo pacman -Sc
sudo pacman -Scc
yay -Sc
yay -Scc
sudo pacman -Rns $(pacman -Qtdq)
rmlint
sudo rm -rf ~/.cache/*
sh -c /home/olivertzeng/rmlint.sh
