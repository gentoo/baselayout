#!/bin/bash
# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

stop_addon devfs
stop_addon udev

# Flush all pending disk writes now
sync ; sync

# If we are in a VPS, we don't need anything below here, because
#   1) we don't need (and by default can't) umount anything (VServer) or
#   2) the host utils take care of all umounting stuff (OpenVZ)
if is_vps_sys ; then
	if [[ -e /etc/init.d/"$1".sh ]] ; then
		. /etc/init.d/"$1".sh
	else
		exit 0
	fi
fi

# If $svcdir is still mounted, preserve it if we can
if [[ -w ${svclib} ]] ; then
	get_mounts | while read point node x ; do
		[[ ${point} == "${svcdir}" ]] || continue
		fuser_opts="-m -c"
		[[ $(uname) == "Linux" ]] && fuser_opts="-c"
		if [[ -n $(fuser ${fuser_opts} "${svcdir}" 2>/dev/null) ]] ; then
			fuser -k ${fuser_opts} "${svcdir}" &>/dev/null
			sleep 2
		fi
		tar cpf "${svclib}/init.d.$$.tar" -C "${svcdir}" \
			depcache deptree netdepcache netdeptree softlevel
		umount "${svcdir}"
		rm -rf "${svcdir}"/*
		# Pipe errors to /dev/null as we may have future timestamps
		tar xpf "${svclib}/init.d.$$.tar" -C "${svcdir}" 2>/dev/null
		rm -f "${svclib}/init.d.$$.tar"
		# Release the memory disk if we used it
		[[ ${node} == "/dev/md"[0-9]* ]] && mdconfig -d -u "${node#/dev/md*}"
	done
fi

# Remount the remaining filesystems read-only
# We ge the do_unmount function from the localmount init script
( . /etc/init.d/localmount
	ebegin $"Remounting remaining filesystems read-only"
	eindent
	if [[ $(uname) == "Linux" ]] ; then
		do_unmount "mount -n -o remount,ro" "^(/dev|/dev/pts|/proc|/proc/bus/usb|/sys)$"
	else
		do_unmount "mount -u -o ro" "^/dev$"
	fi
	eoutdent
	eend $?
)
unmounted=$?

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
