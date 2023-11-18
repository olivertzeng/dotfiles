#!/bin/bash

pacman -S --noconfirm --needed gum reflector git
timedatectl set-ntp true
timedatectl set-timezone Asia/Taipei
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
hwclock -w
cfdisk /dev/nvme0n1 || exit 1
mkfs.fat -F32 /dev/nvme0n1p1 || exit 1
mkswap /dev/nvme0n1p2 || exit 1
mkfs.btrfs -f /dev/nvme0n1p3 || exit 1
swapon /dev/nvme0n1p2 || exit 1
mount /dev/nvme0n1p3 /mnt || exit 1
mount --mkdir /dev/nvme0n1p1 /mnt/boot/efi
gum confirm "Do you want to continue installing Arch?" || exit 0
reflector -c Taiwan -f 12 -n 12 -l 10 --download-timeout 60 --save /etc/pacman.d/mirrorlist
cp ~/dotfiles/pacman.conf /etc
pacstrap -K /mnt $(cat ~/dotfiles/packages/pkglist.txt | xargs)
genfstab -U /mnt >> /mnt/etc/fstab
gum confirm "Do Arch chroot?" || exit 0

# chroot the arch system as new system's root
arch-chroot /mnt
cd
git clone https://github.com/olivertzeng/dotfiles
cd dotfiles
cp pacman.conf /etc
cp paccache.timer /etc/systemd/system
cp paccache.hook /usr/share/libalpm/hooks
cd
gum confirm "Are packages fine?" || exit 1
yes | pacman -Sc
yes | pacman -Scc
passwd
useradd -mG wheel,audio,video,storage,i2c,avahi,git,usbmux,flatpak,rtkit,sddm,polkitd,tss,colord -s $(which zsh) olivertzeng
passwd olivertzeng
EDITOR=nvim
visudo
nvim /etc/locale.gen
echo "LANG=zh_TW.UTF-8" > /etc/locale.conf
echo "ArchBTW" > /etc/hostname
cat >> /etc/hosts << EOL
127.0.0.1	localhost
::1		localhost
127.0.1.1	ArchBTW
EOL
echo "XMODIFIERS=@im=fcitx" >> /etc/environment 
refind-install --usedefault /dev/nvme0n1p1 --alldrivers
rm -rf ~/cache/*
locale-gen
mkrlconf
systemctl enable bluetooth sddm NetworkManager
su olivertzeng

exit
unmount -a