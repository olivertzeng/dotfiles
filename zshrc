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
export BAT_THEME='gruvbox-dark'
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export GOPATH="$HOME/go"
export GPG_TTY=$(tty)
export LANG=zh_TW.UTF-8
export LC_CTYPE="zh_TW.UTF-8"
export MANPATH="/usr/local/man:$MANPATH"
export PATH="$PATH:$GOPATH/bin:$HOME/.cargo/bin"
export PIPENV_VERBOSITY=-1
export RUNEWIDTH_EASTASIAN=0

# some more ls aliases
alias a='activate-linux -t "啟用 Arch Linux" -m "移至 [設定] 以啟用 Arch Linux" -G -d'
alias bak='cp ~/.zsh_plugins.txt ~/dotfiles/zsh_plugins.txt;cp -r ~/.config/nvim ~/dotfiles/;cp ~/.zshrc ~/dotfiles/zshrc;cp ~/.zshenv ~/dotfiles/zshenv;cp ~/.config/topgrade.toml ~/dotfiles;cp ~/light.sh ~/dotfiles;cp ~/dark.sh ~/dotfiles;cp ~/.gitconfig ~/dotfiles/gitconfig;cp ~/.config/pip/pip.conf ~/dotfiles'
alias bat='bat --color=always'
alias cp='cp -v'
alias da='sh ~/dark.sh > /dev/null'
alias diff='batdiff'
alias du='duf'
alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
alias ghcl='GHPATH=$(gum input --placeholder "Please input the GitHub clone path");git clone git@github.com:$GHPATH'
alias gu="fd -u '^\.git$' --prune -x xargs -P10 git -C $(printf '%s\n' '{//}') pull"
alias l='eza --icons'
alias la='eza --icons -a'
alias lg='lazygit'
alias li='sh ~/light.sh > /dev/null'
alias ll='eza --icons -l'
alias lla='eza --icons -la'
alias llt='eza -lT'
alias ls='eza --icons'
alias lt='eza -T'
alias man='batman'
alias open='xdg-open'
alias sudo='s'
alias t='topgrade -y --no-retry -c;sudo -k'
alias vim='nvim'
owofetch
setopt autocd
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt appendhistory

# The following lines were added by compinstall
zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
zstyle ':completion:*' matcher-list '' '' '' ''
zstyle :compinstall filename '/home/olivertzeng/.zshrc'


# Created by `pipx` on 2023-12-12 15:00:21
export PATH="$PATH:/home/olivertzeng/.local/bin"
export THEOS=~/theos
export PATH="$PATH:$THEOS/bin"
export PATH="$PATH:$THEOS/vendor/bin"
source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# pnpm
export PNPM_HOME="/home/olivertzeng/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
