# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# void single_user()
#
#  Drop to a shell, remount / ro, and then reboot
#
single_user() {
	exit 1
}

mount_ro() {
	mount -u -o ro "$@"
}

mount_rw() {
	mount -u -o rw "$@"
}

fsck_progress() {
	# -p enables preen mode
	fsck -p "$@"
}

fsck_all() {
	# Needs to find a way to enable background fs checking..
	fsck_progress "$@"
}

source "${svclib}"/sh/init-functions.sh
source "${svclib}"/sh/init-common-pre.sh

echo
echo -e "${GOOD}Gentoo/FreeBSD $(get_base_ver); ${BRACKET}http://gentoo-alt.gentoo.org/${NORMAL}"
echo -e " Copyright 1999-2006 Gentoo Foundation; Distributed under the GPLv2"
echo

check_statedir /proc

ebegin "Mounting linprocfs at /proc"
try mount -t linprocfs none /proc
eend $?

# Swap needs to be activated *after* devfs has been mounted and *after*
# devfsd has been started, so that the fstab can be properly parsed
# and only if the server/Gentoo box is initialized ...
ebegin "Activating (possible) swap"
/sbin/swapon -a
eend 0

source "${svclib}"/sh/init-common-post.sh


# vim:ts=4
