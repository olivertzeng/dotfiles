#!/bin/bash

pacman -S --noconfirm --needed gum reflector git
timedatectl set-ntp true
timedatectl set-timezone Asia/Taipei
cfdisk /dev/nvme0n1
mkfs.fat -F32 /dev/nvme0n1p1
mkswap /dev/nvme0n1p2
mkfs.btrfs -f /dev/nvme0n1p3
swapon /dev/nvme0n1p2
mount /dev/nvme0n1p3 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot/efi
reflector -c Taiwan -f 12 -n 12 -l 12 --download-timeout 60 -p rsync --save /etc/pacman.d/mirrorlist
cp ~/dotfiles/pacman.conf /etc
pacstrap -K /mnt $(cat packages/pkglist.txt | xargs)
genfstab -U /mnt >>/mnt/etc/fstab

# chroot the arch system as new system's root
arch-chroot /mnt
cd
git clone https://github.com/olivertzeng/dotfiles
cd dotfiles
cp pacman.conf /etc
cp paccache.timer /etc/systemd/system
cp paccache.hook /usr/share/libalpm/hooks
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
hwclock -w
cd
gum confirm "Are packages fine?" || exit 1
yes | pacman -Sc
yes | pacman -Scc
passwd
useradd -mG $(cat /etc/group | cut -d ':' -f1 | xargs | tr -s '[:blank:]' ',') -s $(which zsh) olivertzeng
passwd olivertzeng
EDITOR=nvim
visudo
chmod 777 r.sh
su olivertzeng
bash restore.sh
nvim /etc/locale.gen
echo "LANG=zh_TW.UTF-8" >/etc/locale.conf
echo "LC_TIME=C.UTF-8" >>/etc/locale.conf
echo "ArchBTW" >/etc/hostname
cat >>/etc/hosts <<EOL
127.0.0.1	localhost
::1		localhost
127.0.1.1	ArchBTW
EOL
echo "XMODIFIERS=@im=fcitx" >>/etc/environment
grub-install --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/efi
locale-gen
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable NetworkManager sddm sshd thermald auto-cpufreq
