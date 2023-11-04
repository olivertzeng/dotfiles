#!/bin/bash

cd
timedatectl set-ntp true
cfdisk /dev/name0n1
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.btrfs /dev/nvme0n1p3
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2
mount /dev/nvme0n1p3 /mnt
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi
pacman -Syy --noconfirm reflector
reflector -c Taiwan -f 12 -l 10 --cache-timeout 60 --download-timeout 60 -n 12 --save /etc/pacman.d/mirrorlist
pacstrap -K /mnt base linux linux-firmware linux-headers amd-ucode neovim refind refind-docs git
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
pacman --noconfirm - < ~/dotfiles/packages/pkglist.txt
pacman -Sc
pacman -Scc
git clone https://github.com/olivertzeng/dotfiles
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
hwclock --systohc
passwd
useradd -m -G wheel,audio,video,storage -s /usr/bin/zsh olivertzeng
passwd olivertzeng
echo "Please uncomment the %wheel ALL=(ALL) ALL"
sleep 5
EDITOR=nvim visudo
su olivertzeng
git clone https://github.com/olivertzeng/dotfiles.git
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si      
cd ..
rm -rf yay
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
yay -Syyu --noconfirm - < ~/dotfiles/packages/aurlist.txt
yes y | yay -Sc
yes y | yay -Scc
git clone https://github.com/olivertzeng/dotfiles.git
cp ~/dotfiles/vimrc ~/.vimrc
cp ~/dotfiles/zshrc ~/.zshrc
cp ~/dotfiles/zsh_plugins.txt ~/.zsh_plugins.txt
cp ~/dotfiles/init.lua ~/.config/nvim/init.lua
curl -s 'https://liquorix.net/install-liquorix.sh' | sh
(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> $HOME/.zprofile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
zsh
brew install powerlevel10k
cargo install cargo-cache
p10k configure
exit
exit
cp ~/dotfiles/templates ~/.config/nvim/templates
cp ~/dotfiles/pacman.conf /etc/
cp ~/dotfiles/paccache.timer /etc/systemd/system/paccache.timer
cp ~/dotfiles/paccache.hook /usr/share/libalpm/hooks/paccache.hook
ufw enable
ufw allow 1714:1764/udp
ufw allow 1714:1764/tcp
ufw reload
nvim /etc/locale.gen
echo "LANG=zh_TW.UTF-8" > /etc/locale.conf
locale-gen
echo "ArchGang" > /etc/hostname
echo 'Remember to run `bash -c  "$(wget -qO- https://git.io/vQgMr)"`
after installing Arch!'
refind-install --usedefault /dev/nvme0n1p1
systemctl enable bluetooth sddm NetWorkManager
rm ~/.cache/*
exit
unmount -a
