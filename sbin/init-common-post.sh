# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Set the console loglevel to 1 for a cleaner boot
# the logger should anyhow dump the ring-0 buffer at start to the
# logs, and that with dmesg can be used to check for problems
/bin/dmesg -n 1

# Start logging console output since we have all /dev stuff setup
bootlog start

# Start RAID/LVM/EVMS/DM volumes for /usr, /var, etc.
start_volumes

# We set the forced softlevel from the kernel command line
# It needs to be run right after proc is mounted for the
# boot runlevel
setup_defaultlevels

# $BOOT can be used by rc-scripts to test if it is the first time
# the 'boot' runlevel is executed.  Now also needed by some stuff in
# the 'sysinit' runlevel ...
export BOOT="yes"

# We first try to find a locally defined list of critical services
# for a particular runlevel.  If we cannot find it, we use the
# defaults.
get_critical_services

splash "rc_init" "${argv1}"

export START_CRITICAL="yes"

# We do not want to break compatibility, so we do not fully integrate
# these into /sbin/rc, but rather start them by hand ...
for x in ${CRITICAL_SERVICES} ; do
	splash "svc_start" "${x}"
	user_want_interactive && svcinteractive="yes"
	if ! start_critical_service "${x}" ; then
		splash "critical" &>/dev/null &
		
		echo
		eerror "One of more critical startup scripts failed to start!"
		eerror "Please correct this, and reboot ..."
		echo; echo
		/sbin/sulogin ${CONSOLE}
		einfo "Unmounting filesystems"
		/bin/mount -a -o remount,ro &>/dev/null
		einfo "Rebooting"
		/sbin/reboot -f
	fi

	splash "svc_started" "${x}" "0"
done

unset START_CRITICAL

# /var/log should be writable now, so starting saving the boot output
bootlog sync

# Check that $svcdir exists ...
check_statedir "${svcdir}"

# Should we use tmpfs/ramfs/ramdisk for caching dependency and 
# general initscript data?  Note that the 'gentoo=<fs>' kernel 
# option should override any other setting ...
for fs in tmpfs ramfs ramdisk ; do
	if get_bootparam "${fs}" ; then
		svcmount="yes"
		svcfstype="${fs}"
		break
	fi
done
if [[ ${svcmount} == "yes" ]] ; then
	ebegin "Mounting ${svcfstype} at ${svcdir}"
	case "${svcfstype}" in
	ramfs)
		try mount -t ramfs svcdir "${svcdir}" \
			-o rw,mode=0755,size="${svcsize}"k
		;;
	ramdisk)
		try dd if=/dev/zero of=/dev/ram0 bs=1k count="${svcsize}"
		try /sbin/mke2fs -i 1024 -vm0 /dev/ram0 "${svcsize}"
		try mount -t ext2 /dev/ram0 "${svcdir}" -o rw
		;;
	tmpfs|*)
		try mount -t tmpfs svcdir "${svcdir}" \
			-o rw,mode=0755,size="${svcsize}"k
		;;
	esac
	eend 0
fi

# If booting off CD, we want to update inittab before setting the runlevel
if [[ -f /sbin/livecd-functions.sh && -n ${CDBOOT} ]] ; then
	ebegin "Updating inittab"
	livecd_fix_inittab
	eend $?
	/sbin/telinit q &>/dev/null
fi

# Clear $svcdir from stale entries, but leave the caches around, as it
# should help speed things up a bit
rm -rf $(ls -d1 "${svcdir}/"* 2>/dev/null | \
	 grep -ve '\(depcache\|deptree\|envcache\)')

echo "sysinit" > "${svcdir}/softlevel"
echo "${svcinteractive}" > "${svcdir}/interactive"

# Update the dependency cache
/sbin/depscan.sh -u

# Now that the dependency cache are up to date, make sure these
# are marked as started ...
(
	# Needed for mark_service_started()
	source "${svclib}"/sh/rc-services.sh
	
	for x in ${CRITICAL_SERVICES} ; do
		mark_service_started "${x}"
	done
)

# If the user's /dev/null or /dev/console are missing, we 
# should help them out and explain how to rectify the situation
if [[ ${dev_null} -eq 0 || ${dev_console} -eq 0 ]] && \
   [[ -e /usr/share/baselayout/issue.devfix ]] ; then
	# Backup current /etc/issue
	if [[ -e /etc/issue && ! -e /etc/issue.devfix ]] ; then
		mv -f /etc/issue /etc/issue.devfix
	fi

	cp -f /usr/share/baselayout/issue.devfix /etc/issue
fi

# All done logging
bootlog quit


# vim:ts=4
