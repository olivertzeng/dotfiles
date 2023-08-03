sudo pacman -Sc
sudo pacman -Scc
yay -Sc
yay -Scc
sudo pacman -Rns $(pacman -Qtdq)
sudo rm ~/.cache/*
