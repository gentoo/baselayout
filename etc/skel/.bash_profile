#This file is sourced by bash when you log in interactively.
[ -f ~/.bashrc ] && . ~/.bashrc

eval `dircolors -b /etc/DIR_COLORS`
alias d="ls --color"
alias ls="ls --color=auto"
alias ll="ls --color -l"
