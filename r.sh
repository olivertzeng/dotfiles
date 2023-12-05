bash -c  "$(wget -qO- https://git.io/vQgMr)"
sudo ufw enable
sudo ufw allow 1714:1764/udp
sudo ufw allow 1714:1764/tcp
sudo ufw reload
