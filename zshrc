# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

autoload -Uz compinit
compinit
# Set the name of the static .zsh plugins file antidote will generate.
zsh_plugins=${ZDOTDIR:-~}/.zsh_plugins.zsh

# Ensure you have a .zsh_plugins.txt file where you can add plugins.
[[ -f ${zsh_plugins:r}.txt ]] || touch ${zsh_plugins:r}.txt

# Lazy-load antidote.
fpath+=(${ZDOTDIR:-~}/.antidote)
autoload -Uz $fpath[-1]/antidote

# Generate static file in a subshell when .zsh_plugins.txt is updated.
if [[ ! $zsh_plugins -nt ${zsh_plugins:r}.txt ]]; then
  (antidote bundle <${zsh_plugins:r}.txt >|$zsh_plugins)
fi

# completions
if [ -d $HOME/.zsh/comp ]; then
  export fpath="$HOME/.zsh/comp:$fpath"
fi

# Source your static plugins file.
source $zsh_plugins

# source antidote
source ${ZDOTDIR:-~}/.antidote/antidote.zsh

# initialize plugins statically with ${ZDOTDIR:-~}/.zsh_plugins.txt
antidote load

PATH=/bin:/usr/bin:/usr/local/bin:${PATH}
export ARCHFLAGS="-arch x86_64"
export BAT_THEME="gruvbox-dark"
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export GOPATH="$HOME/go"
export LANG=zh_TW.UTF-8
export LC_CTYPE="zh_TW.UTF-8"
export MANPATH="/usr/local/man:$MANPATH"
export PATH="$PATH:$GOPATH/bin:$HOME/.cargo/bin"
export PIPENV_VERBOSITY=-1
export RUNEWIDTH_EASTASIAN=0
export SUDO_PROMPT=" 密碼勒？？？"

# some more aliases
alias -g -- --help-all='-h 2>&1 | bat --language=help --style=plain'
alias -g -- --help='--help 2>&1 | bat --language=help --style=plain'
alias -g -- -h='-h 2>&1 | bat --language=help --style=plain'
alias ....='cd ../../..'
alias ...='cd ../..'
alias addon="zip -r -FS extension.zip * --exclude '*.git*'"
alias airplay="uxplay -p -fps 60 -s 2560x1600@60"
alias bak='~/bak.sh'
alias bat='bat --color=always'
alias c='clear'
alias cl='clear;eza --icons'
alias cll='clear;eza  --icons -l'
alias clla='clear;eza --icons -la'
alias cllt='clear;eza --icons -T'
alias cllt='clear;eza --icons -lT'
alias cp='cp -v'
alias diff='batdiff'
alias du='duf'
alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
alias gclr="git clean -xfd"
alias kf='konsole --fullscreen'
alias l='eza --icons'
alias la='eza --icons -a'
alias lg='lazygit'
alias ll='eza --icons -l'
alias lla='eza --icons -la'
alias llt='eza --icons -lT'
alias ls='eza --icons'
alias lt='eza -T'
alias man='batman'
alias n='cd ~/.config/nvim/lua'
alias open='xdg-open'
alias p='nvim ~/.config/nvim/lua/core/plugins.lua'
alias refresh="sudo reflector -c Taiwan -f 12 -n 12 -l 12 --download-timeout 60 -p rsync --save /etc/pacman.d/mirrorlist"
alias t='topgrade -y --no-retry -c'
alias th='sh ~/theme.sh'
alias v='nvim'
alias vim='nvim'
alias vm='nvim'
alias vmi='nvim'
owofetch
HISTFILE=~/.zsh_history
HISTSIZE=100000
setopt appendhistory
setopt autocd
setopt interactive_comments

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

export PATH="$PATH:/home/olivertzeng/.local/bin:/usr/lib/qt6/bin/"
export EDITOR=nvim
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
