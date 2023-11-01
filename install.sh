#!/bin/bash

cd
setfont ter-132b
timedatectl set-ntp true
tput bel
cfdisk
mkfs.fat -F32 /dev/sda1
mkfs.btrfs /dev/sda3
mkswap /dev/sda2
swapon /dev/sda2
mount /dev/sda3 /mnt
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
pacman -Syy reflector
reflector -c Taiwan -f 12 -l 10 --cache-timeout 60 --download-timeout 60 -n 12 --save /etc/pacman.d/mirrorlist
pacstrap -K --noconfirm /mnt - < ~/dotfiles/packages/pkglist.txt
genfstab -U /mnt >> /mnt/etc/fstab
arch-chroot /mnt
pacman -Sc
pacman -Scc
git clone https://github.com/olivertzeng/dotfiles
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
hwclock --systohc
passwd
useradd -m -G wheel,audio,video,storage -s /usr/bin/zsh olivertzeng
tput bel
passwd olivertzeng
tput bel
echo "Please uncomment the %wheel ALL=(ALL) ALL"
sleep 10
EDITOR=nvim visudo
su olivertzeng
git clone https://github.com/olivertzeng/dotfiles.git
git clone https://aur.archlinux.org/yay.git
cd ~/yay
makepkg -si      
cd
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
sh ~/dotfiles/clean.sh
(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> $HOME/.zprofile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
zsh;exit
exit
cp ~/dotfiles/templates ~/.config/nvim/templates
cp ~/dotfiles/pacman.conf /etc/
cp ~/dotfiles/paccache.timer /etc/systemd/system/paccache.timer
cp ~/dotfiles/paccache.hook /usr/share/libalpm/hooks/paccache.hook
ufw enable
ufw allow 1714:1764/udp
ufw allow 1714:1764/tcp
ufw reload
tput bel
nvim /etc/locale.gen
echo "LANG=zh_TW.UTF-8" > /etc/locale.conf
locale-gen
echo "ArchGang" > /etc/hostname
tput bel
echo 'Remember to run `bash -c  "$(wget -qO- https://git.io/vQgMr)`"
after installing Arch!'
systemctl enable bluetooth sddm NetWorkManager
git clone https://github.com/divory100/tasty-grubs.git
cp tasty-grubs/themes/amongus /boot/grub/themes/
grub-install /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg
rm ~/.cache/*
exit
unmount -a
