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
	local dotmp=false
	if [[ -e "${svcdir}"/deptree ]] ; then
		dotmp=true
		try mdconfig -a -t malloc -s 1m -u 1
		try newfs /dev/md1
		try mount /dev/md1 "${svclib}"/tmp
		try cp -p "${svcdir}/"*{depcache,deptree} "${svclib}"/tmp
	fi
	try mdconfig -a -t malloc -s "${svcsize}"k -u 0
	try newfs -b 4096 -i 30 -n /dev/md0
	try mount -o rw,noexec,nosuid /dev/md0 "${svcdir}"
	if ${dotmp} ; then
		try cp -p "${svclib}"/tmp/*{depcache,deptree} "${svcdir}"
		try umount "${svclib}"/tmp
		try mdconfig -d -u 1
	fi
}

source "${svclib}"/sh/init-functions.sh
source "${svclib}"/sh/init-common-pre.sh

# Mount linprocfs if instructed
mntcmd=$(get_mount_fstab /proc)
if [[ -n ${mntcmd} ]] ; then
	ebegin "Mounting linprocfs at /proc"
	if [[ ! -d /proc ]] ; then
		eend 1 "/proc does not exist"
	else
		mount ${mntcmd}
		eend $?
	fi
fi

# Start profiling init
profiling start

# Disable devd until we need it
sysctl hw.bus.devctl_disable=1 >/dev/null

source "${svclib}"/sh/init-common-post.sh

# vim: set ts=4 :
