# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


#we try to deactivate swap first because it seems to need devfsd running
#to work.  The TERM and KILL stuff will zap devfsd, so...

ebegin "Deactivating swap"
swapoff -a 1>&2
eend $?

#we need to properly terminate devfsd to save the permissions
if [ "`ps -A |grep devfsd`" ]
then
	ebegin "Stopping devfsd"
	killall -15 devfsd >/dev/null 2>&1
	eend $?
fi

ebegin "Sending all processes the TERM signal"
killall5 -15
eend $?
sleep 5
ebegin "Sending all processes the KILL signal"
killall5 -9
eend $?

# Write a reboot record to /var/log/wtmp before unmounting

halt -w 1>&2

#unmounting should use /proc/mounts and work with/without devfsd running

# Credits for next function to unmount loop devices, goes to:
#
#	Miquel van Smoorenburg, <miquels@drinkel.nl.mugnet.org>
#	Modified for RHS Linux by Damien Neil
#
#
# Unmount file systems, killing processes if we have to.
# Unmount loopback stuff first
remaining=`awk '!/^#/ && $1 ~ /^\/dev\/loop/ && $2 != "/" {print $1}' /proc/mounts |sort -r`
[ -n "$remaining" ] && {
	sig=
	retry=3
	while [ -n "$remaining" -a "$retry" -gt 0 ]
	do
		if [ "$retry" -lt 3 ]; then
			ebegin "Unmounting loopback filesystems (retry)"
			umount $remaining > /dev/null 2>&1
			eend $?
		else
			ebegin "Unmounting loopback filesystems"
			umount $remaining > /dev/null 2>&1
			eend $?
		fi
		for dev in $remaining ; do
			losetup $dev > /dev/null 2>&1 && {
				ebegin "  Detaching loopback device $dev"
				losetup -d $dev > /dev/null 2>&1
				eend $?
			}
		done
		remaining=`awk '!/^#/ && $1 ~ /^\/dev\/loop/ && $2 != "/" {print $2}' /proc/mounts |sort -r`
		[ -z "$remaining" ] && break
		/sbin/fuser -k -m $sig $remaining >/dev/null
		sleep 5
		retry=$(($retry -1))
		sig=-9
	done
}

#try to unmount all filesystems (no /proc,tmpfs,devfs,etc)
#this is needed to make sure we dont have a mounted filesystem on a LVM volume
#when shutting LVM down ...
ebegin "Unmounting filesystems"
#awk should still be availible (allthough we should consider moving it to /bin if problems arise)
for x in `awk '!/(^#|proc|devfs|tmpfs|^none|^\/dev\/root| \/ )/ {print $2}' /proc/mounts |sort -r`
do
	umount -f ${x} > /dev/null 2>/dev/null
done
eend 0

#stop LVM
if [ -x /sbin/vgchange -a -f /etc/lvmtab ] && [ -d /proc/lvm ]
then
	ebegin "Shutting down the Logical Volume Manager"
	/sbin/vgchange -a n
	eend $?
fi

ebegin "Remounting remaining filesystems readonly"
#get better results with a sync and sleep
sync;sync
sleep 2
umount -a -r -t noproc,notmpfs > /dev/null 2>/dev/null
if [ "$?" -ne 0 ]
then
	umount -a -r -l -d -f > /dev/null 2>/dev/null
	if [ "$?" -ne 0 ]
	then
		eend 1
		sync; sync
		/sbin/sulogin -t 10 /dev/console
	else
		eend 0
	fi
else
	eend 0
fi
