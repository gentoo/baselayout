# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Setup initial $PATH just in case
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:${PATH}"

# Help users recover their systems incase these go missing
[[ -c /dev/null ]] && dev_null=1 || dev_null=0
[[ -c /dev/console ]] && dev_console=1 || dev_console=0


# vim:ts=4
