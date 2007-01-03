# Copyright 2005-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)
# Many thanks to all the people in the Gentoo forums for their ideas and
# motivation for me to make this and keep on improving it

# void macnet_depend(void)
#
# Sets up the dependancies for the module
macnet_depend() {
	before rename interface wireless
	after macchanger
	installed macchanger
}

# bool macnet_start(char *iface)
#
# All interfaces and module scripts can depend on the variables function 
# which returns a space seperated list of user configuration variables
# We can override each variable here from a given MAC address of the interface
# Always returns 0
macnet_pre_start() {
	local iface="$1"

	interface_exists "${iface}" || return 0

	local mac=$(interface_get_mac_address "${iface}")
	[[ -z ${mac} ]] && return 0

	vebegin $"Configuring" "${iface}" $"for MAC address" "${mac}" 2>/dev/null
	mac="${mac//:/}"
	configure_variables "${iface}" "${mac}"
	veend 0 2>/dev/null

	return 0
}

# vim: set ts=4 :
