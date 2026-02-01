git clone --depth=1 https://github.com/mattmc3/antidote.git ${ZDOTDIR:-~}/.antidote
yes | yay -Sc
yes | yay -Scc
sh ./link.sh
source ~/.zshrc
pip install --pre -r requirements.txt
rm ~/.gnupg/{S.keyboxd,public-keys.d/pubring.db.lock}
