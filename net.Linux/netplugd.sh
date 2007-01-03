# Copyright 2005-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void netplugd_depend(void)
#
# Sets up the dependancies for the module
netplugd_depend() {
	after macnet rename
	before interface
	provide plug
}

# void netplugd_expose(void)
#
# Expose variables that can be configured
netplugd_expose() {
	variables plug_timeout
}

# bool netplugd_check_installed(void)
#
# Returns 0 if netplug is installed, otherwise 1
netplugd_check_installed() {
	if [[ ! -x /sbin/netplugd ]]; then
		${1:-false} && eerror $"For netplug support, emerge sys-apps/netplug"
		return 1
	fi
	return 0
}

# bool netplugd_pre_start(char *interface)
#
# Start netplug on an interface
netplugd_pre_start() {
	local iface="$1" timeout=
	local pidfile="/var/run/netplugd.${iface}.pid"
	local opts="netplugd_$(bash_variable "${iface}")"

	# We don't start netplug if we're being called from the background
	${IN_BACKGROUND} && return 0

	interface_exists "${iface}" || return 0

	# We need a valid MAC address
	# It's a basic test to ensure it's not a virtual interface
	local mac=$(interface_get_mac_address "${iface}")
	if [[ -z ${mac} ]] ; then
		vewarn $"netplug only works on interfaces with a valid MAC address"
		return 0
	fi

	# We don't work on bonded, bridges, tun/tap, vlan or wireless
	for f in bonding bridge tuntap vlan wireless ; do
		if is_function "${f}_exists" ; then
			if ${f}_exists "${iface}" ; then
				veinfo $"netplug does not work with" "${f}"
				return 0
			fi
		fi
	done

	ebegin $"Starting netplug on" "${iface}"

	# We need the interface up for netplug to listen to netlink events
	interface_up "${iface}"

	# Mark the us as inactive so netplug can restart us
	mark_service_inactive "net.${iface}"

	# Start netplug
	start-stop-daemon --start --exec /sbin/netplugd \
		--pidfile "${pidfile}" \
		-- ${!opts} -i "${iface}" -P -p "${pidfile}" -c /dev/null
	eend "$?" || return 1

	eindent

	timeout="plug_timeout_${ifvar}"
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

# bool netplugd_stop(char *iface)
#
# Stops netplug on an interface
# Returns 0 (true) when successful, non-zero otherwise
netplugd_stop() {
	${IN_BACKGROUND} && return 0
	local iface="$1"
	local pidfile="/var/run/netplugd.${iface}.pid"

	[[ ! -e ${pidfile} ]] && return 0
	
	ebegin $"Stopping netplug on" "${iface}"
	start-stop-daemon --stop --quiet --exec /sbin/netplugd \
		--pidfile "${pidfile}"
	eend $?
}

# vim: set ts=4 :
