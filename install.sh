#!/bin/bash

pacman -S --noconfirm gum parallel reflector
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
pacstrap -K /mnt base base-devel linux linux-firmware linux-headers amd-ucode neovim refind refind-docs git pacman-contrib eza fzf
genfstab -U /mnt >> /mnt/etc/fstab
gum confirm "Do Arch chroot?" || exit 0

# chroot the arch system as new system's root
arch-chroot /mnt
cd
git clone https://github.com/olivertzeng/dotfiles
cp dotfiles/pacman.conf /etc
cp dotfiles/paccache.timer /etc/systemd/system
cp dotfiles/paccache.hook /usr/share/libalpm/hooks
pacman --noconfirm - < dotfiles/packages/pkglist.txt || exit 1
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
su olivertzeng
cd
git clone https://github.com/olivertzeng/dotfiles.git &
git clone https://aur.archlinux.org/yay.git &
git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote &
wait
cd yay
makepkg -si      
cd ..
rm -rf yay
yes "" | /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
yay -Syyu --noconfirm - < ~/dotfiles/packages/aurlist.txt
gum confirm "Are AUR okay?" || exit 1
yes | yay -Sc
yes | yay -Scc
ls .* | parallel cp {} ~/
cp ~/dotfiles/init.lua ~/.config/nvim/init.lua
cp -r ~/dotfiles/templates ~/.config/nvim/templates
(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> $HOME/.zprofile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
zsh
brew install powerlevel10k gcc
cargo install cargo-cache
p10k configure
exit
exit
ufw enable
ufw allow 1714:1764/udp
ufw allow 1714:1764/tcp
ufw reload
nvim /etc/locale.gen
echo "LANG=zh_TW.UTF-8" > /etc/locale.conf
echo "ArchBTW" > /etc/hostname
cat > /etc/hosts << EOL
127.0.0.1	localhost
::1		localhost
127.0.1.1	ArchBTW
EOL
echo 'Remember to run `bash -c  "$(wget -qO- https://git.io/vQgMr)"`
after installing Arch!'
refind-install --usedefault /dev/nvme0n1p1 &
rm ~/.cache/* &
locale-gen &
wait
systemctl enable bluetooth sddm NetWorkManager
unmount -a