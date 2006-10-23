# Copyright 1999-2006 Gentoo Foundation
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

# This basically mounts $svcdir as a ramdisk, but preserving its content
# which allows us to run depscan.sh
# The tricky part is finding something our kernel supports
# tmpfs and ramfs are easy, so force one or the other
mount_svcdir() {
	local filesystems=$(</proc/filesystems)$'\n'
	local fs= devdir="none" devtmp="none" x=
	
	if [[ ${filesystems} =~ "[[:space:]]tmpfs"$'\n' ]] ; then
		fs="tmpfs"
	elif [[ ${filesystems} =~ "[[:space:]]ramfs"$'\n' ]] ; then
		fs="ramfs"
	elif [[ -e /dev/ram0 && -e /dev/ram1 \
		&& ${filesystems} =~ "[[:space:]]ext2"$'\n' ]] ; then
		devdir="/dev/ram0"
		devtmp="/dev/ram1"
		fs="ext2"
		for x in ${devdir} ${devtmp} ; do
			try dd if=/dev/zero of="${x}" bs=1k count="${svcsize}"
			try mkfs -t "${fs}" -i 1024 -vm0 "${x}" "${svcsize}"
		done
	else
		echo
		eerror "Gentoo Linux requires tmpfs, ramfs or 2 ramdisks + ext2"
		eerror "compiled into the kernel"
		echo
		single_user
	fi

	local dotmp=false
	if [[ -e "${svcdir}"/deptree ]] ; then
		dotmp=true
		try mount -t "${fs}" "${devtmp}" "${svclib}"/tmp -o rw
		try cp -p "${svcdir}"/{depcache,deptree} "${svclib}"/tmp
	fi
	try mount -t "${fs}" "${devdir}" "${svcdir}" -o rw
	if ${dotmp} ; then
		try cp -p "${svclib}"/tmp/* "${svcdir}"
		try umount "${svclib}"/tmp
	fi
}

source "${svclib}"/sh/init-functions.sh
source "${svclib}"/sh/init-common-pre.sh

# Set the console loglevel to 1 for a cleaner boot
# the logger should anyhow dump the ring-0 buffer at start to the
# logs, and that with dmesg can be used to check for problems
${RC_DMESG_LEVEL+/bin/dmesg -n ${RC_DMESG_LEVEL}}

check_statedir /proc

procfs="proc"
[[ $(uname) == "GNU/kFreeBSD" ]] && proc="linprocfs"
ebegin "Mounting ${procfs} at /proc"
if [[ ${RC_USE_FSTAB} = "yes" ]] ; then
	mntcmd=$(get_mount_fstab /proc)
else
	mntcmd="-t ${procfs} proc /proc -o noexec,nosuid,nodev"
fi
try mount -n ${mntcmd}
eend $?

# Start profiling init now we have /proc
profiling start

# Read off the kernel commandline to see if there's any special settings
# especially check to see if we need to set the  CDBOOT environment variable
# Note: /proc MUST be mounted
[[ -f /sbin/livecd-functions.sh ]] && livecd_read_commandline

if [[ $(uname) != "GNU/kFreeBSD" && $(get_KV) -ge "$(KV_to_int '2.6.0')" ]] ; then
	if [[ -d /sys ]] ; then
		ebegin "Mounting sysfs at /sys"
		if [[ ${RC_USE_FSTAB} == "yes" ]] ; then
			mntcmd=$(get_mount_fstab /sys)
		else
			unset mntcmd
		fi
		try mount -n ${mntcmd:--t sysfs sysfs /sys -o noexec,nosuid,nodev}
		eend $?
	else
		ewarn "No /sys to mount sysfs needed in 2.6 and later kernels!"
	fi
fi

check_statedir /dev

devfs_automounted="no"
if [[ -e "/dev/.devfsd" ]] ; then
	# make sure devfs is actually mounted and it isnt a bogus file
	devfs_automounted=$(awk '($3 == "devfs") { print "yes"; exit 0 }' /proc/mounts)
fi

# Try to figure out how the user wants /dev handled
#  - check $RC_DEVICES from /etc/conf.d/rc
#  - check boot parameters
#  - make sure the required binaries exist
#  - make sure the kernel has support
if [[ ${RC_DEVICES} == "static" ]] ; then
	ebegin "Using existing device nodes in /dev"
	eend 0
elif [[ $(uname) == "GNU/kFreeBSD" ]] ; then
	ebegin "Using kFreeBSD devfs in /dev"
	eend 0
else
	fellback_to_devfs="no"
	case ${RC_DEVICES} in
		devfs)	devfs="yes"
				udev="no"
				;;
		udev)	devfs="yes"
				udev="yes"
				fellback_to_devfs="yes"
				;;
		auto|*)	devfs="yes"
				udev="yes"
				;;
	esac

	# Check udev prerequisites and kernel params
	if [[ ${udev} == "yes" ]] ; then
		if get_bootparam "noudev" || ! has_addon udev-start.sh || \
		   [[ ${devfs_automounted} == "yes" || \
		      $(get_KV) -lt "$(KV_to_int '2.6.0')" ]] ; then
			udev="no"
		fi
	fi

	# Check devfs prerequisites and kernel params
	if [[ ${devfs} == "yes" ]] ; then
		if get_bootparam "nodevfs" || ! has_addon devfs-start.sh ||
		   [[ ${udev} == "yes" || ! -r /proc/filesystems ]] ; then
			devfs="no"
		elif [[ ! $(</proc/filesystems)$'\n' =~ '[[:space:]]devfs'$'\n' ]]; then
			devfs="no"
		fi
	fi

	# Actually start setting up /dev now
	if [[ ${udev} == "yes" ]] ; then
		start_addon udev

	# With devfs, /dev can be mounted by the kernel ...
	elif [[ ${devfs} == "yes" ]] ; then
		start_addon devfs

		# Did the user want udev in the config file but for 
		# some reason, udev support didnt work out ?
		if [[ ${fellback_to_devfs} == "yes" ]] ; then
			ewarn "You wanted udev but support for it was not available!"
			ewarn "Please review your system after it's booted!"
		fi
	fi

	# OK, if we got here, things are probably not right :)
	if [[ ${devfs} == "no" && ${udev} == "no" ]] ; then
		:
	fi
fi

# From linux-2.5.68 we need to mount /dev/pts again ...
if [[ $(uname) != "GNU/kFreeBSD" && "$(get_KV)" -ge "$(KV_to_int '2.5.68')" ]] ; then
	have_devpts=$(awk '($2 == "devpts") { print "yes"; exit 0 }' /proc/filesystems)

	if [[ ${have_devpts} = "yes" ]] ; then
		# Only try to create /dev/pts if we have /dev mounted dynamically,
		# else it might fail as / might be still mounted readonly.
		if [[ ! -d /dev/pts ]] && \
		   [[ ${devfs} == "yes" || ${udev} == "yes" ]] ; then
			# Make sure we have /dev/pts
			mkdir -p /dev/pts &>/dev/null || \
				ewarn "Could not create /dev/pts!"
		fi

		if [[ -d /dev/pts ]] ; then
			ebegin "Mounting devpts at /dev/pts"
			if [[ ${RC_USE_FSTAB} == "yes" ]] ; then
				mntcmd=$(get_mount_fstab /dev/pts)
			else
				unset mntcmd
			fi
			try mount -n ${mntcmd:--t devpts devpts /dev/pts -o gid=5,mode=0620,noexec,nosuid}
			eend $?
		fi
	fi
fi

source "${svclib}"/sh/init-common-post.sh

# vim: set ts=4 :
