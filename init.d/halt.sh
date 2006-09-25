#!/bin/bash
# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

# livecd-functions.sh should _ONLY_ set this differently
RC_NO_UMOUNTS="${RC_NO_UMOUNTS:-^(/|/lib/rcscripts/init.d)$}"
RC_NO_UMOUNT_FS="${RC_NO_UMOUNT_FS:-^(devfs|devpts|linprocfs|proc|rootfs|swap|sysfs|tmpfs|unionfs|usb(dev)?fs)$}"

# Check to see if this is a livecd, if it is read the commandline
# this mainly makes sure $CDBOOT is defined if it's a livecd
[[ -f /sbin/livecd-functions.sh ]] && \
	source /sbin/livecd-functions.sh && \
	livecd_read_commandline

# Reset pam_console permissions if we are actually using it
if [[ -x /sbin/pam_console_apply && ! -c /dev/.devfsd && \
      -n $(grep -v -e '^[[:space:]]*#' /etc/pam.d/* | grep 'pam_console') ]]; then
	/sbin/pam_console_apply -r
fi

stop_addon devfs
stop_addon udev

# Try to unmount all tmpfs filesystems not in use, else a deadlock may
# occure, bug #13599.
umount -a -t tmpfs &>/dev/null

# Turn off swap and perhaps zero it out for fun
if [[ -x /sbin/swapctl ]] ; then
	swap_list=$(swapctl -l 2>/dev/null | sed -e '1d')
else
	swap_list=$(swapon -s 2>/dev/null | sed -e '1d')
fi
if [[ -n ${swap_list} ]] ; then
	ebegin $"Deactivating swap"
	swapoff -a >/dev/null
	eend $?
fi

# Write a reboot record to /var/log/wtmp before unmounting
[[ $(uname) == "Linux" ]] && halt -w &>/dev/null

# Handy function to handle all our unmounting needs
# get_mounts is our portable function to get mount information
do_unmount() {
	local cmd="$1" no_unmounts="$2" nodes="$3"
	local l= fs= node= point=

	get_mounts | sort -ur | while read l ; do
		fs=${l##* }
		l=${l% *}
		node=${l##* }
		point=${l% *}
		[[ ${fs} =~ "${RC_NO_UMOUNT_FS}" ]] && continue
		[[ -n ${no_unmounts} && ${point} =~ "${no_unmounts}" ]] && continue
		[[ -z ${nodes} && ${node} =~ "${nodes}" ]] || continue

		retry=2
		while ! ${cmd} "${point}" &>/dev/null ; do
			# Kill processes still using this mount
			fuser -k -m "${point}" &>/dev/null
			sleep 2
			((retry--))

			# OK, try forcing things
			if [[ ${retry} -le 0 ]] ; then
				${cmd} -f "${point}" || retval=1
				break
			fi
		done
	done
	return ${retval}
}

# Flush all pending disk writes now
sync ; sync

# Umount loopback devies
ebegin $"Unmounting loopback devices"
do_unmount "umount -d" "${RC_NO_UMOUNTS}" "^/dev/loop"
eend $?

# Now everything else
ebegin $"Unmounting filesystems"
do_unmount "umount" "${RC_NO_UMOUNTS}"
eend $?

# Try to remove any dm-crypt mappings
stop_addon dm-crypt

# Stop LVM, etc
for x in $(reverse_list ${RC_VOLUME_ORDER}) ; do
	stop_addon "${x}"
done

# Remount the rest read-only
ebegin $"Remounting remaining filesystems readonly"
if [[ $(uname) == "Linux" ]] ; then
	do_unmount "mount -n -o remount,ro"
else
	do_unmount "mount -u -o ro"
fi
unmounted=$?
eend ${unmounted}

# This UPS code should be moved to out of here and to an addon
if [[ -f /etc/killpower ]] ; then
	UPS_CTL=/sbin/upsdrvctl
	UPS_POWERDOWN="${UPS_CTL} shutdown"
elif [[ -f /etc/apcupsd/powerfail ]] ; then
	UPS_CTL=/etc/apcupsd/apccontrol
	UPS_POWERDOWN="${UPS_CTL} killpower"
fi
if [[ -x ${UPS_CTL} ]] ; then
	ewarn $"Signalling ups driver(s) to kill the load!"
	${UPS_POWERDOWN}
	ewarn $"Halt system and wait for the UPS to kill our power"
	halt -id
	while [ 1 ]; do sleep 60; done
fi

if [[ ${unmounted} != 0 ]] ; then
	[[ -x /sbin/sulogin ]] && /sbin/sulogin -t 10 /dev/console
	exit 1
fi

# Load the final script - not needed on BSD so they should not exist
[[ -e /etc/init.d/"$1".sh ]] && . /etc/init.d/"$1".sh

# Always exit 0 here
exit 0

# vim: set ts=4 :
