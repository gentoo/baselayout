# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
dhclient() {
	LC_ALL=C /sbin/dhclient "$@"
}

# void dhclient_depend(void)
#
# Sets up the dependancies for the module
dhclient_depend() {
	after interface
	provide dhcp
	functions interface_exists interface_get_address
}

# void dhclient_expose(void)
#
# Expose variables that can be configured
dhclient_expose() {
	variables dhclient dhcp
}

# bool dhclient_check_installed(void)
#
# Returns 1 if dhclient is installed, otherwise 0
dhclient_check_installed() {
	[[ -x /sbin/dhclient ]] && return 0
	${1:-false} && eerror "For DHCP (dhclient) support, emerge net-misc/dhcp"
	return 1
}

# bool dhclient_stop(char *iface)
#
# Stop dhclient on an interface
# Always returns 0
dhclient_stop() {
	local iface="$1" pidfile="/var/run/dhclient-$1.pid"

	[[ ! -f ${pidfile} ]] && return 0

	ebegin "Stopping dhclient on ${iface}"
	local ifvar=$(bash_variable "${iface}")
	local d="dhcp_${ifvar}"
	[[ -z ${!d} ]] && d="dhcp"
	if [[ " ${!d} " == *" release "* ]] ; then
		dhclient -q -r -pf "${pidfile}" "${iface}"
	else
		start-stop-daemon --stop --exec /sbin/dhclient --pidfile "${pidfile}"
	fi
	eend $?
}

# bool dhclient_start(char *iface)
#
# Start DHCP on an interface by calling dhclient $iface $options
#
# Returns 0 (true) when a DHCP address is obtained, otherwise 1
dhclient_start() {
	local iface="$1" ifvar=$(bash_variable "$1") dhconf=
	local pidfile="/var/run/dhclient-${iface}.pid"

	interface_exists "${iface}" true || return 1

	# Load our default options
	opts="dhclient_${ifvar}"
	opts="${!opts}"

	local d="dhcp_${ifvar}"
	[[ -z ${!d} ]] && d="dhcp"
	
	# Add our peer and metric options
	if [[ " ${!d} " == *" nogateway "* ]] ; then
		opts="${opts} -e PEER_ROUTERS=no"
	elif [[ " ${opts} " != *" -e PEER_ROUTERS="* ]] ; then
		opts="${opts} -e PEER_ROUTERS=yes"
	fi
	if [[ " ${!d} " == *" nodns "* ]] ; then
		opts="${opts} -e PEER_DNS=no"
	elif [[ " ${opts} " != *" -e PEER_DNS="* ]] ; then
		opts="${opts} -e PEER_DNS=yes"
	fi
	if [[ " ${!d} " == *" nontp "* ]] ; then
		opts="${opts} -e PEER_NTP=no"
	elif [[ " ${opts} " != *" -e PEER_NTP="* ]] ; then
		opts="${opts} -e PEER_NTP=yes"
	fi
	local metric="metric_${ifvar}"
	if [[ -n ${!metric} && ${!metric} != "0" ]] ; then
		opts="${opts} -e IF_METRIC=${!metric}"
	fi
	
	# Send our hostname by editing cffile
	if [[ " ${!d} " != *" nosendhost "* ]] ; then
		local hname=$(hostname)
		if [[ ${hname} != "(none)" && ${hname} != "localhost" ]]; then
			dhconf="${dhconf} interface \"${iface}\" {\n"
			dhconf="${dhconf} send host-name \"${hname}\"\n;"
			dhconf="${dhconf}}"
		fi
	fi

	# Bring up DHCP for this interface (or alias)
	ebegin "Running dhclient"
	echo -e "${dhconf}" | start-stop-daemon --start --exec /sbin/dhclient \
		--pidfile "${pidfile}" -- ${opts} -q -1 -pf "${pidfile}" "${iface}"
	eend $? || return 1 

	# DHCP succeeded, show address retrieved
	local addr=$(interface_get_address "${iface}")
	einfo "${iface} received address ${addr}"

	return 0
}

# vim: set ts=4 :
