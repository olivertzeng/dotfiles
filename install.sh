#!/bin/bash

pacman -S gum
cd
timedatectl set-ntp true
cfdisk /dev/nvme0n1 || exit 1
umount -a
gum confirm "Do you want to continue installing Arch?" || exit 0
mkfs.fat -F32 /dev/nvme0n1p1
mkfs.btrfs -f /dev/nvme0n1p3 || exit 1
mkswap /dev/nvme0n1p2 || exit 1
swapon /dev/nvme0n1p2 || exit 1
mount /dev/nvme0n1p3 /mnt || exit 1
mkdir -p /mnt/boot/efi
mount /dev/nvme0n1p1 /mnt/boot/efi
pacman -Syy --noconfirm reflector
reflector -c Taiwan -f 12 -l 10 --cache-timeout 60 --download-timeout 60 -n 12 --save /etc/pacman.d/mirrorlist
pacstrap -K /mnt base linux linux-firmware linux-headers amd-ucode neovim refind refind-docs git pacman-contrib eza fzf
genfstab -U /mnt >> /mnt/etc/fstab
gum confirm "Do Arch chroot?" || exit 0
arch-chroot /mnt
git clone https://github.com/olivertzeng/dotfiles
pacman --noconfirm - < dotfiles/packages/pkglist.txt || exit 1
gum confirm "Are packages fine?" || exit 1
yes y | pacman -Sc
yes y | pacman -Scc
curl -s 'https://liquorix.net/install-liquorix.sh' | sh
ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime
hwclock --systohc
passwd
useradd -m -G wheel,audio,video,storage -s /usr/bin/zsh olivertzeng
passwd olivertzeng
echo "Please uncomment %wheel ALL=(ALL) ALL"
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
gum confirm "Are AUR okay?" || exit 1
yes y | yay -Sc
yes y | yay -Scc
cp ~/dotfiles/vimrc ~/.vimrc
cp ~/dotfiles/zshrc ~/.zshrc
cp ~/dotfiles/zsh_plugins.txt ~/.zsh_plugins.txt
cp ~/dotfiles/init.lua ~/.config/nvim/init.lua
(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> $HOME/.zprofile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
zsh
brew install powerlevel10k
cargo install cargo-cache
p10k configure
exit
exit
cp -r ~/dotfiles/templates ~/.config/nvim/templates
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
echo "ArchBTW" > /etc/hostname
cat > /etc/hosts << EOL
127.0.0.1	localhost
::1		localhost
127.0.1.1	ArchBTW
EOL
echo 'Remember to run `bash -c  "$(wget -qO- https://git.io/vQgMr)"`
after installing Arch!'
refind-install --usedefault /dev/nvme0n1p1
systemctl enable bluetooth sddm NetWorkManager
rm ~/.cache/*
exit
unmount -a
