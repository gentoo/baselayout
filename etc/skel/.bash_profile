# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$

#This file is sourced by bash when you log in interactively.
[ -f ~/.bashrc ] && . ~/.bashrc

eval `dircolors -b /etc/DIR_COLORS`
alias d="ls --color"
alias ls="ls --color=auto"
alias ll="ls --color -l"
