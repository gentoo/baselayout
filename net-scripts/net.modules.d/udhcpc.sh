# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
udhcpc() {
	LC_ALL=C /sbin/udhcpc "$@"
}

# void udhcpc_depend(void)
#
# Sets up the dependancies for the module
udhcpc_depend() {
	after interface
	provide dhcp
	functions interface_exists interface_get_address
}

# void udhcpc_expose(void)
#
# Expose variables that can be configured
udhcpc_expose() {
	variables udhcpc dhcp
}

# bool udhcpc_check_installed(void)
#
# Returns 1 if udhcpc is installed, otherwise 0
udhcpc_check_installed() {
	[[ -x /sbin/udhcpc ]] && return 0
	${1:-false} && eerror "For DHCP (udhcpc) support, emerge net-misc/udhcp"
	return 1
}

# bool udhcpc_stop(char *iface)
#
# Stops udhcpc running on an interface
# Return 1 if we fail to stop udhcpc (if it's running) otherwise 0
udhcpc_stop() {
	local iface="$1" pidfile="/var/run/udhcpc-$1.pid" d

	[[ ! -f ${pidfile} ]] && return 0

	ebegin "Stopping udhcpc on ${iface}"
	local pid="$(<"${pidfile}")" e=true

	local ifvar="$(bash_variable "${iface}")"
	d="dhcp_${ifvar}"
	[[ -z ${!d} ]] && d="dhcp" 

	if [[ " ${!d} " == *" release "* ]]; then
		kill -s USR2 "${pid}" &>/dev/null
		[[ -f "/var/cache/udhcpc-${iface}.lease" ]] \
			&& rm "/var/cache/udhcpc-${iface}.lease"
	fi

	start-stop-daemon --stop --exec /sbin/udhcpc --pidfile "${pidfile}"
	eend $? || return 1

	[[ -e /var/run/udhcpc-"${iface}".conf ]] \
		&& rm -f /var/run/udhcpc-"${iface}".conf
	return 0
}

# bool udhcpc_start(char *iface)
#
# Start DHCP on an interface by calling udhcpc $iface $options
#
# Returns 0 (true) when a DHCP address is obtained, otherwise 1
udhcpc_start() {
	local iface="$1" opts pidfile="/var/run/udhcpc-$1.pid"
	local cachefile="/var/cache/udhcpc-$1.lease" d

	interface_exists "${iface}" true || return 1

	local ifvar="$(bash_variable "${iface}" )" opts 
	opts="udhcpc_${ifvar}"
	opts="${!opts}"

	d="dhcp_${ifvar}"
	[[ -z ${!d} ]] && d="dhcp"

	if [[ " ${!d} " != *" nosendhost "* ]]; then
		if [[ ! " ${opts}" =~ " -([hH] |-hostname=)" ]]; then
			local hname="$(hostname)"
			[[ -n ${hname} && ${hname} != "(none)" && ${hname} != "localhost" ]] \
				&& opts="${opts} --hostname=${hname}"
		fi
	fi

	# Setup options for the udhcpc script
	# We pass these via a seperate config file so we're nice and fast
	# maybe oneday, udhcp will accept custom env vars.
	local conf="/var/run/udhcpc-${iface}.conf"
	echo "# udhcpc runtime configuration for interface ${iface}" > "${conf}"
	if [[ " ${!d} " == *" nodns "* ]] ; then
		#opts="${opts} --env PEER_DNS=no"
		echo "PEER_DNS=no" >> "${conf}"
	else
		#opts="${opts} --env PEER_DNS=yes"
		echo "PEER_DNS=yes" >> "${conf}"
	fi
	if [[ " ${!d} " == *" nontp "* ]] ; then
		#opts="${opts} --env PEER_NTP=no"
		echo "PEER_NTP=no" >> "${conf}"
	else
		#opts="${opts} --env PEER_NTP=yes"
		echo "PEER_NTP=yes" >> "${conf}"
	fi
	local metric="metric_${ifvar}"
	if [[ -n ${!metric} ]] ; then
		#opts="${opts} --env IF_METRIC=${!metric}"
		echo "IF_METRIC=${!metric}" >> "${conf}"
	fi

	# Bring up DHCP for this interface (or alias)
	ebegin "Running udhcpc"

	# Try and load the cache if it exists
	if [[ -f ${cachefile} ]]; then
		if [[ " ${opts}" != *" --request="* && " ${opts} " != *" -r "* ]]; then
			local x="$(<"${cachefile}")"
			# Check for a valid ip
			[[ ${x} == *.*.*.* ]] && opts="${opts} --request=${x}"
		fi
	fi

	eval start-stop-daemon --start --exec /sbin/udhcpc \
		--pidfile "${pidfile}" \
		-- "${opts}" --interface="${iface}" --now \
		--script=/lib/rcscripts/sh/udhcpc.sh \
		--pidfile="${pidfile}" >/dev/null
	eend $? || return 1

	# DHCP succeeded, show address retrieved
	local addr="$(interface_get_address "${iface}")"
	einfo "${iface} received address ${addr}"

	return 0
}

# vim: set ts=4 :
