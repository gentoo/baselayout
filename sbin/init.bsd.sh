# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# void single_user()
#
#  Drop to a shell, remount / ro, and then reboot
#
single_user() {
	exit 1
}

# This basically mounts $svcdir as a ramdisk, but preserving its content
# which allows us to run depscan.sh
# FreeBSD has a nice ramdisk - we don't set a size as we should always
# be fairly small and we unmount them after the boot level is done anyway
# NOTE we don't set a size for Linux either
mount_svcdir() {
	try mdconfig -a -t malloc -u 0
	try newfs -U /dev/md0
	try mount /dev/md0 "${svclib}"/tmp
	try cp -apR "${svcdir}/"{depcache,deptree} "${svclib}"/tmp
	try mdconfig -a -t malloc -u 1 
	try newfs -U /dev/md1
	try mount /dev/md1 "${svcdir}"
	try cp -apR "${svclib}"/tmp/* "${svcdir}"
	try umount "${svclib}"/tmp
}

source "${svclib}"/sh/init-functions.sh
source "${svclib}"/sh/init-common-pre.sh

echo
echo -e "${GOOD}Gentoo/FreeBSD $(get_base_ver); ${BRACKET}http://gentoo-alt.gentoo.org/${NORMAL}"
echo -e " Copyright 1999-2006 Gentoo Foundation; Distributed under the GPLv2"
echo
if [[ ${RC_INTERACTIVE} == "yes" ]] ; then
	echo -e "Press ${GOOD}I${NORMAL} to enter interactive boot mode"
	echo
fi

check_statedir /proc

ebegin "Mounting linprocfs at /proc"
try mount -t linprocfs proc /proc
eend $?

# Start profiling init now we have /proc
profiling start

source "${svclib}"/sh/init-common-post.sh

# vim:ts=4
