#!/bin/bash
# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Contributed by Roy Marples (uberlord@gentoo.org)

# void ipppd_depend(void)
#
# Sets up the dependancies for the module
ipppd_depend() {
	after macnet
	before interface
	provide isdn
	variables ipppd
}

# bool ipppd_check_installed(void)
#
# Returns 1 if isnd4k-utils is installed, otherwise 0
ipppd_check_installed() {
	[[ -x /usr/sbin/ipppd ]] && return 0
	${1:-false} && eerror $"For ISDN (ipppd) support, emerge net-dialup/isdn4k-utils"
	return 1
}

# bool ipppd_start(char *iface)
#
# Start isdn on an interface
#
# Returns 0 (true) when successful, non-zero otherwise
ipppd_pre_start() {
	local iface="$1" opts= itype=$(interface_type "$1")
	local pidfile="/var/run/ipppd-${iface}.pid"

	# Check that we are a valid isdn interface
	[[ ${itype} != "ippp" && ${itype} != "isdn" ]] && return 0

	# Check that the interface exists
	interface_exists "${iface}" true || return 1

	local ifvar=$(bash_variable "${iface}")
	# Might or might not be set in conf.d/net
	opts="ipppd_${ifvar}"

	einfo $"Starting ipppd for" "${iface}"
	start-stop-daemon --start --exec /usr/sbin/ipppd \
		--pidfile "${pidfile}" \
		-- ${!opts} pidfile "${pidfile}" \
		file "/etc/ppp/options.${iface}" >/dev/null
	eend $? || return $?

	return 0
}

# bool ipppd_stop(char *iface)
#
# Stop isdn on an interface
# Returns 0 (true) when successful, non-zero otherwise
ipppd_stop() {
	local iface="$1" pidfile="/var/run/ipppd-$1.pid"

	[[ ! -f ${pidfile} ]] && return 0

	einfo $"Stopping ipppd for" "${iface}"
	start-stop-daemon --stop --quiet --exec /usr/sbin/ippd \
		--pidfile "${pidfile}"
	eend $?
}

# vim: set ts=4 :
