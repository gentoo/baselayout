# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Setup initial $PATH just in case
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:${PATH}"

# Help users recover their systems incase these go missing
[[ -c /dev/null ]] && dev_null=1 || dev_null=0
[[ -c /dev/console ]] && dev_console=1 || dev_console=0

# Set the console loglevel to 1 for a cleaner boot
# the logger should anyhow dump the ring-0 buffer at start to the
# logs, and that with dmesg can be used to check for problems
/bin/dmesg -n 1


# vim:ts=4
