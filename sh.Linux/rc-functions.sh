# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# void single_user()
#
#  Drop to a shell, remount / ro, and then reboot
#
single_user() {
	if is_vps_sys ; then
		einfo "Halting"
		halt -f
		return
	fi
	
	sulogin ${CONSOLE}
	einfo "Unmounting filesystems"
	if [[ -c /dev/null ]] ; then
		mount -a -o remount,ro &>/dev/null
	else
		mount -a -o remount,ro
	fi
	einfo "Rebooting"
	reboot -f
}

# vim: set ts=4 :
