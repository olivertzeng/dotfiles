TERM=xterm-256color; export TERM
CLICOLOR=1; export CLICOLOR


#######################################
#PERSONAL CUSTOMIZATION BELOW THIS LINE
#######################################
if [ "$BASH" ]; then
  if [ "$PS1" ]; then
    PS1='\u@\h:\W$ '
  fi

  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
else
  if [ "`id -u`" -eq 0 ]; then
    PS1='# '
  else
    PS1='$ '
  fi
fi
. "$HOME/.cargo/env"
