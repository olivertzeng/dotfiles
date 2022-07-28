sudo pacman -Sy  --needed obs-studio rmlint ncdu bleachbit cowsay lolcat fortune-mod spectacle samba qemu libvirt virt-manager bridge-utils bison ebtables edk2-ovmf mlocate docker trash-cli npm nodejs rsync perl unzip base-devel pacman-contrib git svn openssh gettext lokalize libnautilus-extension gimp retroarch telegram-desktop vlc mpv sl xboard nautilus wget discord handbrake arduino virtualbox ibus ibus-chewing ibus-typing-booster vim vi virtualbox-guest-iso virtualbox-guest-utils virtualbox-guest-utils virtualbox-host-dkms virtualbox-sdk curl flatpak netctl dialog
sudo pacman -Syu
sudo pacman -R dolphin
npm install -g weather-cli
debtap -u
git clone https://aur.archlinux.org/yay-git.git
cd yay-git
makepkg -si      
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
yay -Syu
yay -Sy kalu tuxmath scratch-desktop checkra1n-gui checkra1n-cli zstd citra-canary-bin debtap google-chrome spotify spotify-adblock stacer-bin timeshift yakyak-git pamac-nosnap xscreensaver-aerial xscreensaver-arch-logo xmountains aerial-2k-videos aerial-4k-videos altserver-bin altserver-gui backintime appimagelauncher
git clone https://github.com/hkbakke/bash-insulter.git bash-insulter
cp bash-insulter/src/bash.command-not-found /etc/
gh auth login
git clone git@github.com:olivertzeng/Silica.git
git clone git@github.com:olivertzeng/dotfiles.git
sudo cd dotfiles
sudo cp vimrc ~/.vimrc
cp s.sh ~/s.sh
cp sh.sh ~/sh.sh
cp zshrc ~/.zshrc
sudo cp paccache.timer /dotfiles /etc/systemd/system/paccache.timer
sudo cp paccache.hook /usr/share/libalpm/hooks/paccache.hook
gconftool-2 --load terminal-color-scheme.xml
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
yay -S  proton yuzu darling
