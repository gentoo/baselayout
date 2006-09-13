#!/bin/bash
# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

# Check to see if this is a livecd, if it is read the commandline
# this mainly makes sure $CDBOOT is defined if it's a livecd
[[ -f /sbin/livecd-functions.sh ]] && \
	source /sbin/livecd-functions.sh && \
	livecd_read_commandline

# livecd-functions.sh should _ONLY_ set this differently if CDBOOT is
# set, else the default one should be used for normal boots.
# say:  RC_NO_UMOUNTS="/mnt/livecd|/newroot"
RC_NO_UMOUNTS=${RC_NO_UMOUNTS:-^(/|/mnt/livecd|/newroot)$}
RC_NO_UMOUNT_FS="^(proc|devpts|sysfs|devfs|tmpfs|usb(dev)?fs|unionfs|rootfs)$"

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

erase_swap() {
	while [[ -n $* ]] ; do
		local p=$1 t=$2 s=$3
		[[ -z ${s} ]] && return
		ebegin $"Erasing swap space" ${s}
		dd if=/dev/zero of="${p}" bs=1024 count="${s}" >/dev/null
		eend $?
		if [[ $(uname) == "Linux" ]] ; then
			ebegin $"Creating swap space" ${s}
			mkswap ${s} > /dev/null
			eend $?
		fi
		shift ; shift ; shift
	done
}

# Turn off swap and perhaps zero it out for fun
if [[ $(uname) == "Linux" ]] ; then
	swap_list=$(swapon -s 2>/dev/null)
else
	swap_list=$(swapctl -l 2>/dev/null \
		| sed -e '1 d; s,^\([^ ]*\) *\([^ ]*\).*,\1 partiton \2,')
fi

if [[ -n ${swap_list} ]] ; then
	ebegin $"Deactivating swap"
	swapoff -a >/dev/null
	eend $?

	[[ ${RC_SWAP_ERASE} == "yes" ]] && erase_swap ${swaplist}
fi

# Write a reboot record to /var/log/wtmp before unmounting
[[ $(uname) == "Linux" ]] && halt -w &>/dev/null

# Unmount file systems, killing processes if we have to.

# Unmount loopback stuff first
# Use `umount -d` to detach the loopback device
remaining=$(mount | awk '/^\/dev\/loop/ {print $3}' \
	| sort -ur | egrep -v "${RC_NO_UMOUNTS}")
if [[ -n ${remaining} ]] ; then
	retry=3
	while [[ -n ${remaining} && ${retry} -gt 0 ]]; do
		if [[ ${retry} -lt 3 ]]; then
			ebegin $"Unmounting loopback filesystems (retry)"
			umount -d ${remaining} &>/dev/null
			eend $? $"Failed to unmount filesystems this retry"
		else
			ebegin $"Unmounting loopback filesystems"
			umount -d ${remaining} &>/dev/null
			eend $? $"Failed to unmount filesystems"
		fi

		remaining=$(mount | awk '/^\/dev\/loop/ {print $2}' \
			| sort -ur | egrep -v "^(${RC_NO_UMOUNTS})$")
		[[ -z ${remaining} ]] && break
		
		fuser -s -k -m ${remaining}
		sleep 5
		retry=$((${retry} - 1))
	done
fi

# Try to unmount all filesystems (no /proc,tmpfs,devfs,etc).
# This is needed to make sure we dont have a mounted filesystem 
# on a LVM volume when shutting LVM down ...
# First sed call makes bsd mount look like linux :)

ebegin $"Unmounting filesystems"
for x in $(mount | sed -e 's/ (/ type /g' -e 's/, / /g' \
	| awk -v NO_UMOUNT_FS="${RC_NO_UMOUNT_FS}" \
	'{ \
	    if (($5 !~ NO_UMOUNT_FS) && \
	        ($1 !~ /^(none|rootfs|\/dev\/root)$/)) \
	      print $3 \
	}' | sort -ur) ; do
	[[ ${x} =~ "${RC_NO_UMOUNTS}" ]] && continue
	i=0
	while ! umount "${x}" &>/dev/null; do
		# Kill processes still using this mount
		fuser -s -k -m "${x}"
		sleep 2
		((i++))
		if [[ ${i} -gt 2 ]] ; then
			# OK, bad, try read only
			if [[ $(uname) == "Linux" ]] ; then
				mount -n -o remount,ro "${x}"
			else
				mount -u -o ro "${x}"
			fi
			break
		fi
	done
done
eend 0

# Try to remove any dm-crypt mappings
stop_addon dm-crypt

# Stop LVM, etc
for x in $(reverse_list ${RC_VOLUME_ORDER}) ; do
	stop_addon "${x}"
done

# This is a function because its used twice below
ups_kill_power() {
	local UPS_CTL UPS_POWERDOWN
	if [[ -f /etc/killpower ]] ; then
		UPS_CTL=/sbin/upsdrvctl
		UPS_POWERDOWN="${UPS_CTL} shutdown"
	elif [[ -f /etc/apcupsd/powerfail ]] ; then
		UPS_CTL=/etc/apcupsd/apccontrol
		UPS_POWERDOWN="${UPS_CTL} killpower"
	else
		return 0
	fi
	if [[ -x ${UPS_CTL} ]] ; then
		ewarn $"Signalling ups driver(s) to kill the load!"
		${UPS_POWERDOWN}
		ewarn $"Halt system and wait for the UPS to kill our power"
		/sbin/halt -id
		while [ 1 ]; do sleep 60; done
	fi
}

mount_readonly() {
	local x= retval=0 cmd="$1" unmounts=

	# Get better results with a sync and sleep
	sync; sync
	sleep 1

	for x in $(mount | sed -e 's/ (/ type /g' -e 's/, / /g' \
			| awk -v NO_UMOUNT_FS="${RC_NO_UMOUNT_FS}" \
	           	'{ \
	           		if (($1 != "none") && ($5 !~ NO_UMOUNT_FS)) \
	           			print $3 \
	           	}' | sort -ur) ; do
		if [[ ${cmd} == "u" ]]; then
			if [[ $(uname) == "Linux" ]] ; then
				umount -n -r "${x}"
			else
				umount -f "${x}"
			fi
		else
			if [[ $(uname) == "Linux" ]] ; then
				mount -n -o remount,ro "${x}"
			else
				mount -u -o ro "${x}"
			fi
		fi
		retval=$((${retval} + $?))
	done
	[[ ${retval} != 0 ]] && fuser -s -k -m "${x}"

	return ${retval}
}

if [[ $(uname) == "Linux" ]] ; then
	# Since we use `mount` in mount_readonly(), but we parse /proc/mounts,
	# we have to make sure our /etc/mtab and /proc/mounts agree
	cp /proc/mounts /etc/mtab &>/dev/null
fi

ebegin $"Remounting remaining filesystems readonly"
mount_worked=0
if ! mount_readonly ; then
	if ! mount_readonly ; then
		# If these things really don't want to remount ro, then 
		# let's try to force them to unmount
		if ! mount_readonly u ; then
			mount_worked=1
		fi
	fi
fi
eend ${mount_worked}
if [[ ${mount_worked} -eq 1 ]]; then
	ups_kill_power
	if [[ -x /sbin/sulogin ]] ; then
		/sbin/sulogin -t 10 /dev/console
	else
		exit 1
	fi
fi

ups_kill_power

# Load the final script depending on how we are called
[[ -e /etc/init.d/"$1".sh ]] && source /etc/init.d/"$1".sh

# vim: set ts=4 :
