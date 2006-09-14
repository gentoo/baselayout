# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void apipa_depend(void)
#
# Sets up the dependancies for the module
apipa_depend() {
	installed arping
	functions interface_exists
}

# bool apipa_start(char *iface)
#
# Tries to detect a config based on arpinging things
apipa_start() {
	local iface="$1" i1= i2= addr= i=0

	interface_exists "$1" true || return 1
	
	einfo $"Searching for free addresses in" "169.254.0.0/16"
	eindent

	while [[ ${i} -lt 64516 ]]; do
		(( i1=${RANDOM}%255 ))
		(( i2=${RANDOM}%255 ))

		addr="169.254.${i1}.${i2}"
		vebegin "${addr}/16"
		if ! arping_address_exists "${iface}" "${addr}" ; then
			config[config_counter]="${addr}/16 broadcast 169.254.255.255"
			(( config_counter-- ))
			veend 0
			eoutdent
			return 0
		fi

		(( i++ ))
	done

	eerror $"No free address found!"
	eoutdent
	return 1
}

# vim: set ts=4 :
