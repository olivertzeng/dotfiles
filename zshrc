# Keep at the top of this file.
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

# Source your static plugins file.
source $zsh_plugins

# source antidote
source ${ZDOTDIR:-~}/.antidote/antidote.zsh

# initialize plugins statically with ${ZDOTDIR:-~}/.zsh_plugins.txt
antidote load

PATH=/bin:/usr/bin:/usr/local/bin:${PATH}
export PATH="/usr/local/bin:$PATH"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export BAT_THEME='gruvbox-dark'

# User configuration
export MANPATH="/usr/local/man:$MANPATH"
export PATH="/usr/local/bin:$PATH"

# You may need to manually set your language environment
export LANG=zh_TW.UTF-8
export LC_CTYPE="zh_TW.UTF-8"

# Compilation flags
export ARCHFLAGS="-arch x86_64"

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias bat='bat --color=always'
alias bgp='batgrep'
alias cp='cp -v'
alias du='duf'
alias en='export LC_CTYPE="en_US.UTF-8"'
alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
alias l='eza --icons'
alias la='eza --icons -a'
alias ll='eza --icons -l'
alias lla='eza --icons -la'
alias ls='eza --icons'
alias rm='rip --graveyard ~/.local/share/Trash'
alias sudo='nocorrect sudo'
alias topgrade='topgrade -y --no-retry -c'
alias tw='export LC_CTYPE="zh_TW.UTF-8"'
alias vim='neovim'
pfetch
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
(echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> $HOME/.zprofile
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
eval $(thefuck --alias)
export GOPATH="$HOME/go"
export PATH="$PATH:$GOPATH/bin:$HOME/.cargo/bin"
source /home/linuxbrew/.linuxbrew/share/powerlevel10k/powerlevel10k.zsh-theme
setopt autocd
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory

# The following lines were added by compinstall
zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle ':completion:*' matcher-list '' '' '' ''
zstyle :compinstall filename '/home/olivertzeng/.zshrc'
