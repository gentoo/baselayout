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

ebegin "Unmounting filesystems"
umount -a -r -t noproc,notmpfs > /dev/null 2>/dev/null
if [ "$?" -ne 0 ]
then
	umount -a -r -f > /dev/null 2>/dev/null
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
