# arch-functions.sh
# arch-specific functions needed by /sbin/rc.
# $Header$

# Some variables needed on all systems
SYSINIT_CRITICAL_SERVICES="checkroot hostname modules checkfs localmount clock"

#
# Functions needed on all systems:
#

# Function to go single-user when boot fails
single_user() {
	/sbin/sulogin ${CONSOLE}
	einfo "Unmounting filesystems"
	if [ -c /dev/null ]; then
		/bin/mount -a -o remount,ro &>/dev/null
	else
		/bin/mount -a -o remount,ro
	fi
	einfo "Rebooting"
	/sbin/reboot -f
}

# Brings up the 'sysinit' runlevel.
arch_sysinit() {
	# Setup initial $PATH just in case
	PATH="/bin:/sbin:/usr/bin:/usr/sbin:${PATH}"

	# Help users recover their systems incase these go missing
	[ -c /dev/null ] && dev_null=1 || dev_null=0
	[ -c /dev/console ] && dev_console=1 || dev_console=0

	echo
	echo -e "${GOOD}Gentoo Linux${GENTOO_VERS}; ${BRACKET}http://www.gentoo.org/${NORMAL}"
	echo -e " Copyright 1999-2004 Gentoo Foundation; Distributed under the GPLv2"
	echo

	check_statedir /proc

	ebegin "Mounting proc at /proc"
	try mount -n -t proc none /proc
	eend $?

	# Read off the kernel commandline to see if there's any special settings
	# especially check to see if we need to set the  CDBOOT environment variable
	# Note: /proc MUST be mounted
	[ -f /sbin/livecd-functions.sh ] && livecd_read_commandline

	if [ "$(get_KV)" -ge "$(KV_to_int '2.6.0')" ]
	then
		if [ -d /sys ]
		then
			ebegin "Mounting sysfs at /sys"
			mount -n -t sysfs none /sys
			eend $?
		else
			ewarn "No /sys to mount sysfs needed in 2.6 and later kernels!"
		fi
	fi

	check_statedir /dev

	# Fix weird bug where there is a /dev/.devfsd in a unmounted /dev
	devfs_automounted="no"
	if [ -e "/dev/.devfsd" ]
	then
		mymounts="$(awk '($3 == "devfs") { print "yes"; exit 0 }' /proc/mounts)"
		if [ "${mymounts}" != "yes" ]
		then
			rm -f /dev/.devfsd
		else
			devfs_automounted="yes"
		fi
	fi

	# Try to figure out how the user wants /dev handled
	#  - check $RC_DEVICES from /etc/conf.d/rc
	#  - check boot parameters
	#  - make sure the required binaries exist
	#  - make sure the kernel has support
	if [ "${RC_DEVICES}" = "static" ]
	then
		ebegin "Using existing device nodes in /dev"
		eend 0
	else
		fellback_to_devfs="no"
		case "${RC_DEVICES}" in
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
		if [ "${udev}" = "yes" ]
		then
			if get_bootparam "noudev" || \
			   [ ! -x /sbin/udev -o -e "/dev/.devfsd" ] || \
			   [ "$(get_KV)" -lt "$(KV_to_int '2.6.0')" ]
			then
				udev="no"
			fi
		fi

		# Check devfs prerequisites and kernel params
		if [ "${devfs}" = "yes" ]
		then
			if get_bootparam "nodevfs" || [ "${udev}" = "yes" ]
			then
				devfs="no"
			fi
		fi

		# Actually start setting up /dev now
		if [ "${udev}" = "yes" ]
		then
			# Setup temporary storage for /dev
			if [ "${RC_DEVICE_FS}" != "tmpfs" -a "${RC_DEVICE_FS}" != "ramfs" ]
			then
				RC_DEVICE_FS="tmpfs"
			fi
			ebegin "Mounting ${RC_DEVICE_FS} at /dev"
			try mount -n -t ${RC_DEVICE_FS} none /dev
			eend $?

			# Actually get udev rolling
			ebegin "Configuring system to use udev"
			if [ "${RC_DEVICE_TARBALL}" = "yes" ]
			then
				einfo "  Populating /dev with device nodes ..."
				try tar -jxpf /lib/udev-state/devices.tar.bz2 -C /dev
			fi
			populate_udev

			# Setup hotplugging (if possible)
			if [ -e /proc/sys/kernel/hotplug ]
			then
				if [ -x /sbin/hotplug ]
				then
					einfo "  Using /sbin/hotplug for udev management ..."
				else
					einfo "  Setting /sbin/udev as hotplug agent ..."
					echo "/sbin/udev" > /proc/sys/kernel/hotplug
				fi
			fi
			eend 0

		# With devfs, /dev can be mounted by the kernel ...
		elif [ "${devfs}" = "yes" ]
		then
			mymounts="$(awk '($2 == "devfs") { print "yes"; exit 0 }' /proc/filesystems)"
			# Is devfs support compiled in?
			if [ "${mymounts}" = "yes" ]
			then
				if [ "${devfs_automounted}" = "no" ]
				then
					ebegin "Mounting devfs at /dev"
					try mount -n -t devfs none /dev
					eend $?
				else
					ebegin "Kernel automatically mounted devfs at /dev"
					eend 0
				fi
				ebegin "Starting devfsd"
				/sbin/devfsd /dev >/dev/null
				eend $? "Could not start /sbin/devfsd"
			else
				devfs="no"
			fi

			# Did the user want udev in the config file but for 
			# some reason, udev support didnt work out ?
			if [ "${fellback_to_devfs}" = "yes" ]
			then
				ewarn "You wanted udev but support for it was not available!"
				ewarn "Please review your system after it's booted!"
			fi
		fi

		# OK, if we got here, things are probably not right :)
		if [ "${devfs}" = "no" ] && [ "${udev}" = "no" ]
		then
			clear
			echo
			einfo "The Gentoo Linux system initialization scripts have detected that"
			einfo "your system does not support DEVFS or UDEV.  Since Gentoo Linux"
			einfo "has been designed with these dynamic /dev managers in mind, it is"
			einfo "highly suggested that you build support for it into your kernel."
			einfo "Please read the Gentoo Handbook for more information!"
			echo
			einfo "    http://www.gentoo.org/doc/en/handbook/"
			echo
			einfo "Thanks for using Gentoo! :)"
			echo
			read -t 15 -p "(hit Enter to continue or wait 15 seconds ...)"
		fi
	fi

	# From linux-2.5.68 we need to mount /dev/pts again ...
	if [ "$(get_KV)" -ge "$(KV_to_int '2.5.68')" ]
	then
		have_devpts="$(awk '($2 == "devpts") { print "yes"; exit 0 }' /proc/filesystems)"

		if [ "${have_devpts}" = "yes" ]
		then
			# Only try to create /dev/pts if we have /dev mounted dynamically,
			# else it might fail as / might be still mounted readonly.
			if [ ! -d /dev/pts ] && \
			   [ "${devfs}" = "yes" -o "${udev}" = "yes" ]
			then
				# Make sure we have /dev/pts
				mkdir -p /dev/pts &>/dev/null || \
					ewarn "Could not create /dev/pts!"
			fi

			if [ -d /dev/pts ]
			then
				ebegin "Mounting devpts at /dev/pts"
				try mount -n -t devpts -o gid=5,mode=0620 none /dev/pts
				eend $?
			fi
		fi
	fi

	if [ -x /sbin/irqbalance -a "$(get_KV)" -ge "$(KV_to_int '2.5.0')" ]
	then
		ebegin "Starting irqbalance"
		/sbin/irqbalance
		eend $?
	fi

	# Swap needs to be activated *after* devfs has been mounted and *after*
	# devfsd has been started, so that the fstab can be properly parsed
	# and only if the server/Gentoo box is initialized ...
	ebegin "Activating (possible) swap"
	/sbin/swapon -a &>/dev/null
	eend 0

	# Set the console loglevel to 1 for a cleaner boot
	# the logger should anyhow dump the ring-0 buffer at start to the
	# logs, and that with dmesg can be used to check for problems
	/bin/dmesg -n 1

	# We set the forced softlevel from the kernel command line
	# It needs to be run right after proc is mounted for the
	# boot runlevel
	setup_defaultlevels

	# $BOOT can be used by rc-scripts to test if it is the first time
	# the 'boot' runlevel is executed.  Now also needed by some stuff in
	# the 'sysinit' runlevel ...
	export BOOT="yes"

	start_critical_service() {
		(
		local retval=

		source "/etc/init.d/${x}" || eerror "Failed to source /etc/init.d/${x}"
		retval=$?
		[ "${retval}" -ne 0 ] && return "${retval}"
		[ -e "/etc/conf.d/${x}" ] && source "/etc/conf.d/${x}"

		start || eerror "Failed to start /etc/init.d/${x}"
		retval=$?

		return "${retval}"
		)
	}

	# We first try to find a locally defined list of critical services
	# for a particular runlevel.  If we cannot find it, we use the
	# defaults.
	get_critical_services

	splash "rc_init" "${argv1}"

	# We do not want to break compatibility, so we do not fully integrate
	# these into /sbin/rc, but rather start them by hand ...
	for x in ${CRITICAL_SERVICES}
	do
		splash "svc_start" "${x}"

		if ! start_critical_service "${x}"
		then
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

	# Check that $svcdir exists ...
	check_statedir "${svcdir}"

	# Should we use tmpfs/ramfs/ramdisk for caching dependency and 
	# general initscript data?  Note that the 'gentoo=<fs>' kernel 
	# option should override any other setting ...
	for fs in tmpfs ramfs ramdisk
	do
		if get_bootparam "${fs}"
		then
			svcmount="yes"
			svcfstype="${fs}"
			break
		fi
	done
	if [ "${svcmount}" = "yes" ]
	then
		ebegin "Mounting ${svcfstype} at ${svcdir}"
		case "${svcfstype}" in
		ramfs)
			try mount -n -t ramfs ramfs "${svcdir}" \
				-o rw,mode=0644,size="${svcsize}"k
			;;
		ramdisk)
			try dd if=/dev/zero of=/dev/ram0 bs=1k count="${svcsize}"
			try /sbin/mke2fs -i 1024 -vm0 /dev/ram0 "${svcsize}"
			try mount -n -t ext2 /dev/ram0 "${svcdir}" -o rw
			;;
		tmpfs|*)
			try mount -n -t tmpfs tmpfs "${svcdir}" \
				-o rw,mode=0644,size="${svcsize}"k
			;;
		esac
		eend 0
	fi

	# If booting off CD, we want to update inittab before setting the runlevel
	if [ -f "/sbin/livecd-functions.sh" -a -n "${CDBOOT}" ]
	then
		ebegin "Updating inittab"
		livecd_fix_inittab
		eend $?
		/sbin/telinit q &>/dev/null
	fi

	# Clear $svcdir from stale entries, but leave the caches around, as it
	# should help speed things up a bit
	rm -rf $(ls -d1 "${svcdir}/"* 2>/dev/null | \
	         grep -ve '\(depcache\|deptree\|envcache\)')

	# Update the dependency cache
	/sbin/depscan.sh -u

	# Now that the dependency cache are up to date, make sure these
	# are marked as started ...
	(
		# Needed for mark_service_started()
		source "${svclib}/sh/rc-services.sh"
		
		for x in ${CRITICAL_SERVICES}
		do
			mark_service_started "${x}"
		done
	)

	# If the user's /dev/null or /dev/console are missing, we 
	# should help them out and explain how to rectify the situation
	if [ ${dev_null} -eq 0 -o ${dev_console} -eq 0 ] \
	    && [ -e /usr/share/baselayout/issue.devfix ]
	then
		# Backup current /etc/issue
		if [ -e /etc/issue -a ! -e /etc/issue.devfix ]
		then
			mv /etc/issue /etc/issue.devfix
		fi

		cp /usr/share/baselayout/issue.devfix /etc/issue
	fi

	# Setup login records ... this has to be done here because when 
	# we exit this runlevel, init will write a boot record to utmp
	# If /var/run is readonly, then print a warning, not errors
	if touch /var/run/utmp 2>/dev/null
	then
		> /var/run/utmp
		touch /var/log/wtmp
		chgrp utmp /var/run/utmp /var/log/wtmp
		chmod 0664 /var/run/utmp /var/log/wtmp
		# Remove /var/run/utmpx (bug from the past)
		rm -f /var/run/utmpx
	else
		ewarn "Skipping /var/run/utmp initialization (ro root?)"
	fi

	exit 0
} # end of arch_sysinit

#
# Stuff that needs to be defined, but might not be useful
#

# Called after a runlevel switch
arch_rl_postswitch() {
	# We want devfsd running after a change of runlevel (this is mostly if we return
	# from runlevel 'single')
	if [ -z "`ps --no-heading -C 'devfsd'`" -a \
	     -n "`gawk '/\/dev devfs/ { print }' /proc/mounts 2>/dev/null`" ]
	then
		if [ "${RC_DEVFSD_STARTUP}" != "no" ]
		then
			/sbin/devfsd /dev &>/dev/null
		fi
	fi
}

# Now for helper functions only needed by this arch...

populate_udev() {
	/sbin/udevstart

	# Not provided by sysfs but needed
	ln -snf /proc/self/fd /dev/fd
	ln -snf fd/0 /dev/stdin
	ln -snf fd/1 /dev/stdout
	ln -snf fd/2 /dev/stderr
	ln -snf /proc/kcore /dev/core

	# Create nodes that udev can't
	[ -x /sbin/dmsetup ] && /sbin/dmsetup mknodes &>/dev/null
	[ -x /sbin/lvm ] && /sbin/lvm vgscan -P --mknodes --ignorelockingfailure &>/dev/null

	# Create problematic directories
	mkdir -p /dev/{pts,shm}

	# Same thing as /dev/.devfsd
	touch /dev/.udev

	return 0
}


