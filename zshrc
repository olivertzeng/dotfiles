# Keep at the top of this file.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

PATH=/bin:/usr/bin:/usr/local/bin:${PATH}
export PATH="/usr/local/bin:$PATH"
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export BAT_THEME='gruvbox-dark'

ZSH_THEME="powerlevel10k/powerlevel10k"
zstyle ':omz:update' mode auto      # update automatically without asking

# Uncomment the following line to enable command auto-correction.
ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
COMPLETION_WAITING_DOTS="%F{cyan}請稍候...%f"

# see 'man strftime' for details.
HIST_STAMPS="mm/dd/yyyy"

# Plugins
plugins=(
	#archlinux
	alias-finder
	colored-man-pages 
	colorize
	git
	git-prompt 
	history 
    history-substring-search	
	man
	sudo
    zsh-autosuggestions
	zsh-interactive-cd
	zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# User configuration
export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
export LANG=zh_TW.UTF-8
export LC_CTYPE="zh_TW.UTF-8"

# Compilation flags
export ARCHFLAGS="-arch x86_64"

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='exa --icons --color=auto'
    alias grep='grep --color=auto'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias bat='bat --color=always'
alias cp='cp -v'
alias la='exa --icons -a'
alias l='exa --icons'
alias fzf="fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}'"
alias sudo='nocorrect sudo'
alias du='duf'
alias rm='rip --graveyard ~/.local/share/Trash'
alias neofetch='macchina -t Boron'
alias topgrade='topgrade --disable vim -y --no-retry -c'
alias commit='git commit -m "$(gum input  --prompt.foreground="212" --header.bold --header.italic --header="Summary" --placeholder "Summary of changes")"\
           -m "$(gum write --header="Details" --placeholder "Details of changes (CTRL+D to finish)" --header.italic --header.bold --show-line-numbers --prompt="▌" --prompt.foreground=212)"'
alias en='export LC_CTYPE="en_US.UTF-8"'
alias tw='export LC_CTYPE="zh_TW.UTF-8"'
alias bgp='batgrep'
alias vim='vim -X'
# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# alias grep
if command -v rg >/dev/null 2>&1; then
  alias grep='rg --ignore-file ~/.ignore --no-heading'
elif command -v ag >/dev/null 2>&1; then
  alias grep='ag --path-to-ignore ~/.ignore --nogroup -s'
else
  alias grep='grep --color --exclude={cscope.*,tags} --exclude-dir={.svn,builds} --binary-files=without-match'
fi

# Alias definitions.
if [ -f ~/.zsh_aliases ]; then
    . ~/.zsh_aliases
fi
macchina -t Boron

# Functions
# --------------------------------------------------------------------

highlight () { grep --color auto "$1|$" $2 ; }

# Fuzzy Finder
# --------------------------------------------------------------------

if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND="fd --type file"
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  export FZF_ALT_C_COMMAND="fd --type directory"
fi
export FZF_DEFAULT_OPTS="--reverse"
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
source /usr/local/share/zsh-history-substring-search/zsh-history-substring-search.zsh
export GOPATH="$HOME/go"
export PATH="$PATH:$GOPATH/bin"
