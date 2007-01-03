# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void iptunnel_depend(void)
#
# Sets up the dependancies for the module
iptunnel_depend() {
	before interface
	functions interface_exists interface_tunnel
}

# void iptunnel_expose(void)
#
# Expose variables that can be configured
iptunnel_expose() {
	variables iptunnel
}

# bool iptunnel_pre_start(char *iface)
#
# Create the device, give it the right perms
iptunnel_pre_start() {
	local iface="$1" opts= ifvar=$(bash_variable "$1")
	
	# Get our options
	eval opts="iptunnel_${ifvar}"
	[[ -z ${!opts} ]] && return 0

	# Set our base metric to 1000
	metric=1000
	
	ebegin "Creating tunnel ${iface}"
	interface_tunnel add "${iface}" ${!opts}
	eend "$?"
}

# bool iptunnel_stop(char *iface)
#
# Removes the device
iptunnel_stop() {
	local iface="$1"

	# Don't delete sit0 as it's a special tunnel
	[[ ${iface} == "sit0" ]] && return 0
	
	interface_exists "${iface}" || return 0
	[[ -z $(interface_tunnel show "${iface}" 2>/dev/null) ]] && return 0

	ebegin "Destroying tunnel ${iface}"
	interface_tunnel del "${iface}"
	eend $?
}

# vim: set ts=4 :
