# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# void single_user()
#
#  Drop to a shell, remount / ro, and then reboot
#
single_user() {
	/sbin/sulogin ${CONSOLE}
	einfo "Unmounting filesystems"
	if [[ -c /dev/null ]] ; then
		/bin/mount -a -o remount,ro &>/dev/null
	else
		/bin/mount -a -o remount,ro
	fi
	einfo "Rebooting"
	/sbin/reboot -f
}

source "${svclib}"/sh/init-functions.sh
source "${svclib}"/sh/init-common-pre.sh

echo
echo -e "${GOOD}Gentoo Linux${GENTOO_VERS}; ${BRACKET}http://www.gentoo.org/${NORMAL}"
echo -e " Copyright 1999-2006 Gentoo Foundation; Distributed under the GPLv2"
echo
if [[ ${RC_INTERACTIVE} == "yes" ]] ; then
	echo -e "Press ${GOOD}I${NORMAL} to enter interactive boot mode"
	echo
fi
check_statedir /proc

ebegin "Mounting proc at /proc"
if [[ ${RC_USE_FSTAB} = "yes" ]] ; then
	mntcmd=$(get_mount_fstab /proc)
else
	unset mntcmd
fi
try mount -n ${mntcmd:--t proc proc /proc}
eend $?

# Read off the kernel commandline to see if there's any special settings
# especially check to see if we need to set the  CDBOOT environment variable
# Note: /proc MUST be mounted
[[ -f /sbin/livecd-functions.sh ]] && livecd_read_commandline

if [[ $(get_KV) -ge "$(KV_to_int '2.6.0')" ]] ; then
	if [[ -d /sys ]] ; then
		ebegin "Mounting sysfs at /sys"
		if [[ ${RC_USE_FSTAB} == "yes" ]] ; then
			mntcmd=$(get_mount_fstab /sys)
		else
			unset mntcmd
		fi
		try mount -n ${mntcmd:--t sysfs sysfs /sys}
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
		if get_bootparam "noudev" || \
		   [[ ! -x /sbin/udev || ${devfs_automounted} == "yes" || \
		      $(get_KV) -lt "$(KV_to_int '2.6.0')" ]] ; then
			udev="no"
		fi
	fi

	# Check devfs prerequisites and kernel params
	if [[ ${devfs} == "yes" ]] ; then
		if get_bootparam "nodevfs" || [[ ${udev} == "yes" ]] || \
		   ! grep -qs '[[:space:]]devfs$' /proc/filesystems ; then
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
if [[ "$(get_KV)" -ge "$(KV_to_int '2.5.68')" ]] ; then
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
			try mount -n ${mntcmd:--t devpts -o gid=5,mode=0620 devpts /dev/pts}
			eend $?
		fi
	fi
fi

source "${svclib}"/sh/init-common-post.sh

# Have to run this after /var/run is mounted rw, bug #85304
if [[ -x /sbin/irqbalance && $(get_KV) -ge "$(KV_to_int '2.5.0')" ]] ; then
	ebegin "Starting irqbalance"
	/sbin/irqbalance
	eend $?
fi

# Setup login records ... this has to be done here because when 
# we exit this runlevel, init will write a boot record to utmp
# If /var/run is readonly, then print a warning, not errors
if touch /var/run/utmp 2>/dev/null ; then
	> /var/run/utmp
	touch /var/log/wtmp
	chgrp utmp /var/run/utmp /var/log/wtmp
	chmod 0664 /var/run/utmp /var/log/wtmp
	# Remove /var/run/utmpx (bug from the past)
	rm -f /var/run/utmpx
else
	ewarn "Skipping /var/run/utmp initialization (ro root?)"
fi


# vim:ts=4
