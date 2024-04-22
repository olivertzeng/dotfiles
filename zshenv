s() {
    if sudo -n true 2> /dev/null; then
        sudo "$@"
    else
        gum input --prompt "密碼？？？" --password | sudo -S -p '' "$@"
    fi
}
. "$HOME/.cargo/env"
