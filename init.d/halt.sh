# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$


# We need to properly terminate devfsd to save the permissions
if [ -n "`ps --no-heading -C 'devfsd'`" ]
then
	ebegin "Stopping devfsd"
	killall -15 devfsd &> /dev/null
	eend $?
elif [ ! -e /dev/.devfsd -a -e /dev/.udev ]
then
	ebegin "Saving device nodes"
	cd /dev
	try tar -jclpf "/tmp/devices-$$.tar.bz2" *
	try mv -f "/tmp/devices-$$.tar.bz2" /lib/udev-state/devices.tar.bz2
	eend 0
fi

ebegin "Sending all processes the TERM signal"
killall5 -15 &> /dev/null
eend $?
sleep 5
ebegin "Sending all processes the KILL signal"
killall5 -9 &> /dev/null
eend $?

# Try to unmount all tmpfs filesystems not in use, else a deadlock may
# occure, bug #13599.
umount -at tmpfs &> /dev/null

if [ -n "`swapon -s 2> /dev/null`" ]
then
	ebegin "Deactivating swap"
	swapoff -a &> /dev/null
	eend $?
fi

# Write a reboot record to /var/log/wtmp before unmounting

halt -w &> /dev/null

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
remaining="`awk '!/^#/ && $1 ~ /^\/dev\/loop/ && $2 != "/" {print $2}' /proc/mounts | sort -r`"
[ -n "${remaining}" ] && {
	sig=
	retry=3
	
	while [ -n "${remaining}" -a "${retry}" -gt 0 ]
	do
		if [ "${retry}" -lt 3 ]
		then
			ebegin "Unmounting loopback filesystems (retry)"
			umount -d ${remaining} &> /dev/null
			eend $? "Failed to unmount filesystems this retry"
		else
			ebegin "Unmounting loopback filesystems"
			umount -d ${remaining} &> /dev/null
			eend $? "Failed to unmount filesystems"
		fi
		
		remaining="`awk '!/^#/ && $1 ~ /^\/dev\/loop/ && $2 != "/" {print $2}' /proc/mounts | sort -r`"
		[ -z "${remaining}" ] && break
		
		/bin/fuser -k -m ${sig} ${remaining} &> /dev/null
		sleep 5
		retry=$((${retry} - 1))
		sig=-9
	done
}

# Try to unmount all filesystems (no /proc,tmpfs,devfs,etc).
# This is needed to make sure we dont have a mounted filesystem
# on a LVM volume when shutting LVM down ...
ebegin "Unmounting filesystems"
no_unmount="`mount | awk '{ if (($5 ~ /^(proc|sysfs|devfs|tmpfs|usb(dev)?fs)$/) ||
                             ($1 ~ /^(rootfs|\/dev\/root)$/) ||
                             ($3 = "/"))
                           print $3
                       }' | sort | uniq`"
for x in `awk '{ print $2 }' /proc/mounts | sort -r | uniq`
do
	do_unmount="yes"
	
	for y in ${no_unmount}
	do
		[ "${x}" = "${y}" ] && do_unmount="no"
	done
	
	if [ "${do_unmount}" = "yes" ] && \
	   [ "${x}" != "/" -a "${x}" != "/dev" -a "${x}" != "/proc" -a \
	     "${x}" != "/sys" ]
	then
		umount -f -r ${x} &> /dev/null
	fi
done
eend 0

# Stop LVM
if [ -x /sbin/vgchange ] && [ -f /etc/lvmtab -o -d /etc/lvm ] && \
   [ -d /proc/lvm  -o "`grep device-mapper /proc/misc 2>/dev/null`" ]
then
	ebegin "Shutting down the Logical Volume Manager"
	/sbin/vgchange -a n > /dev/null
	eend $? "Failed to shut LVM down"
fi

# This is a function because its used twice below this line as:
#   [ -f /etc/killpower ] && ups_kill_power
ups_kill_power() {
	if [ -x /sbin/upsdrvctl ]
	then
		ewarn "Signalling ups driver(s) to kill the load!"
		/sbin/upsdrvctl shutdown
		ewarn "Halt system and wait for the UPS to kill our power"
		/sbin/halt -id
		while [ 1 ]; do sleep 60; done
	fi
}

ebegin "Remounting remaining filesystems readonly"
# Get better results with a sync and sleep
sync;sync
sleep 1
sync
sleep 1
if [ -n "${CDBOOT}" ]
then
	#LiveCD: don't unmount the read-only livecd loopback filesystem or all our commands will disappear
	mount | cut -f1 -d" " | grep -v livecd | xargs umount -r -n -t  nodevfs,noproc,nosysfs,notmpfs &>/dev/null
else
	umount -a -r -n -t nodevfs,noproc,nosysfs,notmpfs &>/dev/null
fi
if [ "$?" -ne 0 ]
then
	killall5 -9  &> /dev/null
	umount -a -r -n -l -d -f -t nodevfs,noproc,nosysfs &> /dev/null
	if [ "$?" -ne 0 ]
	then
		eend 1
		sync; sync
		[ -f /etc/killpower ] && ups_kill_power
		/sbin/sulogin -t 10 /dev/console
	else
		eend 0
	fi
else
	eend 0
fi

# Inform if there is a forced or skipped fsck
if [ -f /fastboot ]
then
	echo
	ewarn "Fsck will be skipped on next startup"
elif [ -f /forcefsck ]
then
	echo
	ewarn "A full fsck will be forced on next startup"
fi

[ -f /etc/killpower ] && ups_kill_power

# vim:ts=4
