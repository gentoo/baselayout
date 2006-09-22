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
	try mdconfig -a -t malloc -s 1m -u 1 
	try newfs -U /dev/md1
	try mount /dev/md1 "${svclib}"/tmp
	try cp -p "${svcdir}/"{depcache,deptree} "${svclib}"/tmp
	try mdconfig -a -t malloc -s 2m -u 0
	try newfs -U /dev/md0
	try mount /dev/md0 "${svcdir}"
	try cp -p "${svclib}"/tmp/* "${svcdir}"
	try umount "${svclib}"/tmp
	try mdconfig -d -u 1
}

echo
echo -e "${GOOD}Gentoo/FreeBSD $(get_base_ver); ${BRACKET}http://gentoo-alt.gentoo.org/${NORMAL}"
echo -e " Copyright 1999-2006 Gentoo Foundation; Distributed under the GPLv2"
echo
if [[ ${RC_INTERACTIVE} == "yes" ]] ; then
	echo -e "Press ${GOOD}I${NORMAL} to enter interactive boot mode"
	echo
fi

# Start profiling init
profiling start

# Disable devd until we need it
sysctl hw.bus.devctl_disable=1 >/dev/null

source "${svclib}"/sh/init-functions.sh
source "${svclib}"/sh/init-common-pre.sh
source "${svclib}"/sh/init-common-post.sh

# vim: set ts=4 :
