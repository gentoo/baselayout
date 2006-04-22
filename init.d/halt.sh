# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

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

# We need to properly terminate devfsd to save the permissions
if [[ -n $(ps --no-heading -C 'devfsd') ]]; then
	ebegin "Stopping devfsd"
	killall -15 devfsd &>/dev/null
	eend $?
elif [[ ! -e /dev/.devfsd && -e /dev/.udev && -z ${CDBOOT} && \
        ${RC_DEVICE_TARBALL} == "yes" ]] && \
		touch /lib/udev-state/devices.tar.bz2 2>/dev/null
then
	ebegin "Saving device nodes"
	# Handle our temp files
	devices_udev=$(mktemp /tmp/devices.udev.XXXXXX)
	devices_real=$(mktemp /tmp/devices.real.XXXXXX)
	devices_totar=$(mktemp /tmp/devices.totar.XXXXXX)
	device_tarball=$(mktemp /tmp/devices-XXXXXX)
	
	if [[ -z ${devices_udev} || -z ${devices_real} || \
	      -z ${device_tarball} ]]; then
		eend 1 "Could not create temporary files!"
	else
		cd /dev
		# Find all devices
		find . -xdev -type b -or -type c -or -type l | cut -d/ -f2- > \
			"${devices_real}"
		# Figure out what udev created
		eval $(grep '^[[:space:]]*udev_db=' /etc/udev/udev.conf)
		if [[ -d ${udev_db} ]]; then
			# New udev_db is clear text ...
			udevinfo=$(cat "${udev_db}"/*)
		else
			# Old one is not ...
			udevinfo=$(udevinfo -d)
		fi
		# This basically strips 'S:' and 'N:' from the db output, and then
		# print all the nodes/symlinks udev created ...
		echo "${udevinfo}" | gawk '
			/^(N|S):.+/ {
				sub(/^(N|S):/, "")
				split($0, nodes)
				for (x in nodes)
					print nodes[x]
			}' > "${devices_udev}"
		# These ones we also do not want in there
		for x in MAKEDEV core fd initctl pts shm stderr stdin stdout; do
			echo "${x}" >> "${devices_udev}"
		done
		fgrep -x -v -f "${devices_udev}" < "${devices_real}" > "${devices_totar}"
		# Now only tarball those not created by udev if we have any
		if [[ -s ${devices_totar} ]]; then
			try tar --one-file-system -jcpf "${device_tarball}" -T "${devices_totar}"
			try mv -f "${device_tarball}" /lib/udev-state/devices.tar.bz2
		else
			rm -f /lib/udev-state/devices.tar.bz2
		fi
		eend 0
	fi

	rm -f "${devices_udev}" "${devices_real}" "${devices_totar}" "${device_tarball}"
fi

# Try to unmount all tmpfs filesystems not in use, else a deadlock may
# occure, bug #13599.
umount -at tmpfs &>/dev/null

if [[ -n $(swapon -s 2>/dev/null) ]]; then
	ebegin "Deactivating swap"
	swapoff -a
	eend $?
fi

# Write a reboot record to /var/log/wtmp before unmounting

halt -w &>/dev/null

# Unmounting should use /proc/mounts and work with/without devfsd running

# Credits for next function to unmount loop devices, goes to:
#
#	Miquel van Smoorenburg, <miquels@drinkel.nl.mugnet.org>
#	Modified for RHS Linux by Damien Neil
#
#
# Unmount file systems, killing processes if we have to.
# Unmount loopback stuff first
# Use `umount -d` to detach the loopback device

# Remove loopback devices started by dm-crypt

remaining=$(awk '!/^#/ && $1 ~ /^\/dev\/loop/ && $2 != "/" {print $2}' /proc/mounts | \
            sort -r | grep -v '/newroot' | grep -v '/mnt/livecd')
[[ -n ${remaining} ]] && {
	sig=
	retry=3

	while [[ -n ${remaining} && ${retry} -gt 0 ]]; do
		if [[ ${retry} -lt 3 ]]; then
			ebegin "Unmounting loopback filesystems (retry)"
			umount -d ${remaining} &>/dev/null
			eend $? "Failed to unmount filesystems this retry"
		else
			ebegin "Unmounting loopback filesystems"
			umount -d ${remaining} &>/dev/null
			eend $? "Failed to unmount filesystems"
		fi

		remaining=$(awk '!/^#/ && $1 ~ /^\/dev\/loop/ && $2 != "/" {print $2}' /proc/mounts | \
		            sort -r | grep -v '/newroot' | grep -v '/mnt/livecd')
		[[ -z ${remaining} ]] && break
		
		/bin/fuser -s -k ${sig} -m ${remaining}
		sleep 5
		retry=$((${retry} - 1))
		sig=-9
	done
}

# Try to unmount all filesystems (no /proc,tmpfs,devfs,etc).
# This is needed to make sure we dont have a mounted filesystem 
# on a LVM volume when shutting LVM down ...
ebegin "Unmounting filesystems"
unmounts=$( \
	awk '{ \
	    if (($3 !~ /^(proc|devpts|sysfs|devfs|tmpfs|usb(dev)?fs)$/) && \
	        ($1 != "none") && \
	        ($1 !~ /^(rootfs|\/dev\/root)$/) && \
	        ($2 != "/")) \
	      print $2 }' /proc/mounts | sort -k2 -ur)
for x in ${unmounts}; do
	# Do not umount these if we are booting off a livecd
	if [[ -n ${CDBOOT} ]] && \
	   [[ ${x} == "/mnt/cdrom" || ${x} == "/mnt/livecd" ]] ; then
		continue
	fi

	x=${x//\\040/ }
	if ! umount "${x}" &>/dev/null; then
		# Kill processes still using this mount
		/bin/fuser -s -k -9 -m "${x}"
		sleep 2
		# Now try to unmount it again ...
		umount -f -r "${x}" &>/dev/null
	fi
done
eend 0

# Try to remove any dm-crypt mappings
stop_addon dm-crypt

# Stop LVM, etc
stop_volumes

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
		ewarn "Signalling ups driver(s) to kill the load!"
		${UPS_POWERDOWN}
		ewarn "Halt system and wait for the UPS to kill our power"
		/sbin/halt -id
		while [ 1 ]; do sleep 60; done
	fi
}

mount_readonly() {
	local x=
	local retval=0
	local cmd=$1

	# Get better results with a sync and sleep
	sync; sync
	sleep 1

	for x in $(awk '$1 != "none" { print $2 }' /proc/mounts | sort -k2 -ur) ; do
		x=${x//\\040/ }
		if [[ ${cmd} == "u" ]]; then
			umount -n -r "${x}"
		else
			mount -n -o remount,ro "${x}" &>/dev/null
		fi
		retval=$((${retval} + $?))
	done
	[[ ${retval} -ne 0 ]] && killall5 -9 &>/dev/null

	return ${retval}
}

# Since we use `mount` in mount_readonly(), but we parse /proc/mounts, we 
# have to make sure our /etc/mtab and /proc/mounts agree
cp /proc/mounts /etc/mtab &>/dev/null
ebegin "Remounting remaining filesystems readonly"
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
	/sbin/sulogin -t 10 /dev/console
fi

# Inform if there is a forced or skipped fsck
if [[ -f /fastboot ]]; then
	echo
	ewarn "Fsck will be skipped on next startup"
elif [[ -f /forcefsck ]]; then
	echo
	ewarn "A full fsck will be forced on next startup"
fi

ups_kill_power


# vim:ts=4
