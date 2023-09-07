function fzf
	fzf --preview 'bat --color=always --style=numbers --line-range=:5 $argv
end
