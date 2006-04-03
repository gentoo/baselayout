#!/bin/bash
# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Contributed by Roy Marples (uberlord@gentoo.org)

# void ip6to4_depend(void)
#
# Sets up the dependancies for the module
ip6to4_depend() {
	after interface
	functions interface_exists interface_get_address interface_tunnel
}

# void ip6to4_expose(void)
#
# Expose variables that can be configured
ip6to4_expose() {
	variables link
}

# bool ip6to4_start(char *interface)
#
# Configures IPv6 addresses to be added to the tunnel based on a IPv4
# addresses on a pre-configured interface.
# Returns 0 on success, otherwise 1.
ip6to4_start() {
	local iface="$1" addr=""
	local ifvar="$(bash_variable "${iface}")"

	# Ensure the interface is sit0 if we're using ifconfig
	if [[ " ${MODULES[@]} " == *" ifconfig "* && ${iface} != "sit0" ]] ; then
		eerror "ip6to4 can only on interface sit0 using ifconfig"
		eerror "emerge sys-apps/iproute2 to use other interfaces"
		return 1
	fi

	local host="link_${ifvar}"
	if [[ -z ${!host} ]] ; then
		eerror "link_${ifvar} is not set"
		return 1
	fi
	
	interface_exists "${!host}" true || return 1
	
	# An interface can have more than 1 ip address
	local -a addrs=( $(interface_get_address "${!host}") )
	if [[ -z ${addrs} ]] ; then
		eerror "${!host} is not configured with an IPv4 address"
		return 1
	fi

	local -a new=()
	local addr=""
	for addr in "${addrs[@]}" ; do
		# Strip the subnet
		local ip="${addr%/*}" subnet="${addr#*/}"
		# We don't work on private IPv4 addresses
		[[ ${ip} == "127."* ]] && continue
		[[ ${ip} == "10."* ]] && continue
		[[ ${ip} == "192.168."* ]] && continue
		local i
		for ((i=16; i<32; i++)); do
			[[ ${ip} == "172.${i}."* ]] && break 
		done
		[[ ${i} -lt 32 ]] && continue
	
		veinfo "IPv4 address on ${!host}: ${ip}"
		local ip6="$(printf "2002:%02x%02x:%02x%02x::1" ${ip//./ })"
		veinfo "Derived IPv6 address: ${ip6}"

		# Now apply our IPv6 address to our config
		new=( "${new[@]}" "${ip6}/16" )
	done	

	if [[ -z ${new} ]] ; then
		eerror "No global IPv4 addresses found on interface ${!host}"
		return 1
	fi

	if [[ ${iface} != "sit0" ]] ; then
		ebegin "Creating 6to4 tunnel on ${iface}"
		interface_tunnel add "${iface}" mode sit ttl 255 remote any local "${ip}"
		eend $? || return 1
	fi
	
	# Now apply our config
	config=( "${config[@]}" "${new[@]}" )

	# Add a route for us, ensuring we don't delete anything else
	local routes="routes_${ifvar}[@]"
	eval "routes_${ifvar}=( \"\${!routes}\" \
			\"2003::/3 via ::192.88.99.1 metric 2147483647\" )"
}
	
# vim:ts=4
# vim: set ts=4 :
