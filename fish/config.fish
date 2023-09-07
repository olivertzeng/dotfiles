# This is a hack to prevent this file from being sourced twice
if not status is-interactive
    exit
end

set PATH '/bin:/usr/bin:/usr/local/bin:{PATH}'
set MANPAGER sh\ -c\ \'col\ -bx\ \|\ bat\ -l\ man\ -p\'
set BAT_THEME gruvbox-dark
set fish_greeting ''

# User configuration
set MANPATH '/usr/local/man:{MANPATH}'

# You may need to manually set your language environment
set LANG zh_TW.UTF-8
set LC_CTYPE zh_TW.UTF-8

# Compilation flags
set ARCHFLAGS '-arch x86_64'

# colored GCC warnings and errors
set GCC_COLORS 'error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

macchina
# Fuzzy Finder
# --------------------------------------------------------------------

if command -v fd >/dev/null 2>&1
	set FZF_DEFAULT_COMMAND 'fd --type file'
	set FZF_CTRL_T_COMMAND 'fd --type file'
	set FZF_ALT_C_COMMAND 'fd --type directory'
end
set FZF_DEFAULT_OPTS --reverse
