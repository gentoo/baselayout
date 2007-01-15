# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void ifplugd_depend(void)
#
# Sets up the dependancies for the module
ifplugd_depend() {
	after macnet rename
	before interface
	provide plug
}

# void ifplugd_expose(void)
#
# Expose variables that can be configured
ifplugd_expose() {
	variables plug_timeout
}

# bool ifplugd_check_installed(void)
#
# Returns 0 if ifplugd is installed, otherwise 1
ifplugd_check_installed() {
	if [[ ! -x /usr/sbin/ifplugd ]]; then
		${1:-false} && eerror $"For ifplugd support, emerge sys-apps/ifplugd"
		return 1
	fi
	return 0
}

# bool ifplugd_pre_start(char *interface)
#
# Start ifplugd on an interface
ifplugd_pre_start() {
	local iface="$1" ifvar=$(bash_variable "$1") timeout= opts=
	local pidfile="/var/run/ifplugd.${iface}.pid"

	# We don't start ifplugd if we're being called from the background
	${IN_BACKGROUND} && return 0

	interface_exists "${iface}" || return 0

	# ifplugd could have been started by the old init script
	if [[ -e ${pidfile} ]] ; then
		vewarn $"ifplugd is already running on" "${iface}"
		return 0
	fi

	# We need a valid MAC address
	# It's a basic test to ensure it's not a virtual interface
	local mac=$(interface_get_mac_address "${iface}")
	if [[ -z ${mac} ]] ; then
		vewarn $"ifplugd only works on interfaces with a valid MAC address"
		return 0
	fi

	# We don't work on bonded, bridges, tun/tap, vlan or wireless
	for f in bonding bridge tuntap vlan ; do
		if is_function "${f}_exists" ; then
			if ${f}_exists "${iface}" ; then
				veinfo $"ifplugd does not work with" "${f}"
				return 0
			fi
		fi
	done
	
	# Do some options
	opts="ifplugd_${ifvar}"
	
	# We don't work on wirelesss interfaces
	# Although ifplugd can, we prefer wpa_supplicant, unless explicitly told
	# so via our options
	if [[ " ${!opts} " != *" -m wlan "* \
		&& " ${!opts} " != *" --api-mode=wlan "* ]] ; then
		if is_function wireless_exists ; then
			if wireless_exists "${iface}" ; then
				veinfo $"ifplugd does not work on wireless interfaces"
				return 0
			fi
		fi
	fi

	ebegin $"Starting ifplugd on" "${iface}"

	# We need the interface up for ifplugd to listen to netlink events
	interface_up "${iface}"

	# Mark the us as inactive so ifplugd can restart us
	mark_service_inactive "net.${iface}"

	# Start ifplugd
	eval start-stop-daemon --start --exec /usr/sbin/ifplugd \
		--pidfile "${pidfile}" \
		-- "${!opts}" --iface="${iface}"
	eend "$?" || return 1

	eindent

	timeout="timeout_${ifvar}"
	timeout="${!timeout:--1}"
	if [[ ${timeout} == "0" ]] ; then
		ewarn $"WARNING: infinite timeout set for" "${iface}" $"to come up"
	elif [[ ${timeout} -lt 0 ]] ; then
		einfo $"Backgrounding ..."
		exit 0
	fi

	veinfo $"Waiting for" "${iface}" $"to be marked as started"

	local i=0
	while true ; do
		if service_started "net.${iface}" ; then
			local addr=$(interface_get_address "${iface}")
			einfo "${iface}" $"configured with address" "${addr}"
			exit 0
		fi
		sleep 1
		[[ ${timeout} == "0" ]] && continue
		(( i++ ))
		[[ ${i} == "${timeout}" || ${i} -gt "${timeout}" ]] && break
	done

	eend 1 $"Failed to configure" "${iface}" $"in the background"
	exit 0
}

# bool ifplugd_stop(char *iface)
#
# Stops ifplugd on an interface
# Returns 0 (true) when successful, non-zero otherwise
ifplugd_stop() {
	${IN_BACKGROUND} && return 0
	local iface="$1"
	local pidfile="/var/run/ifplugd.${iface}.pid"

	[[ ! -e ${pidfile} ]] && return 0

	ebegin $"Stopping ifplugd on" "${iface}"
	start-stop-daemon --stop --quiet --exec /usr/sbin/ifplugd \
		--pidfile "${pidfile}" --signal QUIT

	eend $?
}

# vim: set ts=4 :
