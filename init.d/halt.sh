#we try to deactivate swap first because it seems to need devfsd running
#to work.  The TERM and KILL stuff will zap devfsd, so...

ebegin "Deactivating swap"
swapoff -a 1>&2
eend $?
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

ebegin "Unmounting filesystems"
umount -v -a -r -t noproc,notmpfs
if [ "$?" = "1" ]
then
	eend 1 "hmmmm..."
	ebegin "Trying to unmount again"
	umount -a -r -f
	eend $?
else
	eend 0
fi

#this is "just in case"
sync; sync
