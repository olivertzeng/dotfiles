#!/bin/bash

pacman -S --noconfirm gum reflector
timedatectl set-ntp true
cfdisk /dev/nvme0n1 || exit 1
mkfs.fat -F32 /dev/nvme0n1p1 || exit 1
mkswap /dev/nvme0n1p2 || exit 1
mkfs.btrfs -f /dev/nvme0n1p3 || exit 1
swapon /dev/nvme0n1p2 || exit 1
mount /dev/nvme0n1p3 /mnt || exit 1
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi
gum confirm "Do you want to continue installing Arch?" || exit 0
reflector -c Taiwan -f 12 -l 10 --cache-timeout 60 --download-timeout 60 -n 12 --save /etc/pacman.d/mirrorlist
cp ~/dotfiles/pacman.conf /etc
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers amd-ucode neovim refind refind-docs git pacman-contrib linux-firmware-qlogic
genfstab -U /mnt >> /mnt/etc/fstab
gum confirm "Do Arch chroot?" || exit 0

# chroot the arch system as new system's root
arch-chroot /mnt
cd
git clone https://github.com/olivertzeng/dotfiles
cp dotfiles/pacman.conf /etc
cp dotfiles/paccache.timer /etc/systemd/system
cp dotfiles/paccache.hook /usr/share/libalpm/hooks
pacman -Syyu --needed --noconfirm - < dotfiles/packages/pkglist.txt || exit 1
gum confirm "Are packages fine?" || exit 1
yes | pacman -Sc
yes | pacman -Scc
curl -s 'https://liquorix.net/install-liquorix.sh' | sh
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
hwclock --systohc
passwd
useradd -m -G wheel,audio,video,storage -s /usr/bin/zsh olivertzeng
passwd olivertzeng
echo "Please uncomment %wheel ALL=(ALL) ALL"
sleep 5
EDITOR=nvim visudo
nvim /etc/locale.gen
echo "LANG=zh_TW.UTF-8" > /etc/locale.conf
echo "ArchBTW" > /etc/hostname
cat >> /etc/hosts << EOL
127.0.0.1	localhost
::1		localhost
127.0.1.1	ArchBTW
EOL
cat >> /etc/environment << EOL
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=fcitx
EOL
echo 'Remember to run `bash -c  "$(wget -qO- https://git.io/vQgMr)"`
after installing Arch!'
refind-install --usedefault /dev/nvme0n1p1 &
rm ~/.cache/* &
locale-gen &
wait
systemctl enable bluetooth sddm NetWorkManager
unmount -a