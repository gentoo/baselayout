# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
ifconfig() {
	LC_ALL=C /sbin/ifconfig "$@"
}

ifconfig_tunnel() {
	LC_ALL=C /sbin/iptunnel "$@"
}

route() {
	LC_ALL=C /sbin/route "$@"
}

# void ifconfig_depend(void)
#
# Sets up the dependancies for the module
ifconfig_depend() {
	provide interface
}

# void ifconfig_expose(void)
#
# Expose variables that can be configured
ifconfig_expose() {
	variables config routes fallback metric
}

# bool ifconfig_check_installed(void)
#
# Returns 1 if ifconfig is installed, otherwise 0
ifconfig_check_installed() {
	[[ -x /sbin/ifconfig ]] && return 0
	${1:-false} && eerror $"For ifconfig support, emerge sys-freebds/freebsd-sbin"
	return 1
}

# bool ifconfig_exists(char *interface, bool report)
#
# Returns 1 if the interface exists, otherwise 0
ifconfig_exists() {
	[[ -e /dev/net/$1 ]] && return 0

	if ${2:-false} ; then
		eerror $"network interface" "$1" $"does not exist"
		eerror $"Please verify hardware or kernel module (driver)"
	fi

	return 1
}

# char* cidr2netmask(int cidr)
#
# Returns the netmask of a given CIDR
cidr2netmask() {
	local cidr="$1" netmask="" done=0 i sum=0 cur=128
	local octets= frac=

	(( octets=cidr/8 ))
	(( frac=cidr%8 ))
	while [[ octets -gt 0 ]] ; do
		netmask="${netmask}.255"
		(( octets-- ))
		(( done++ ))
	done

	if [[ ${done} -lt 4 ]] ; then
		for (( i=0; i<${frac}; i++ )); do
			(( sum+=cur ))
			(( cur/=2 ))
		done
		netmask="${netmask}.${sum}"
		(( done++ ))

		while [[ ${done} -lt 4 ]] ; do
			netmask="${netmask}.0"
			(( done++ ))
		done
	fi

	echo "${netmask:1}"
}

# void ifconfig_up(char *iface)
#
# provides a generic interface for bringing interfaces up
ifconfig_up() {
	ifconfig "$1" up
}

# void ifconfig_down(char *iface)
#
# provides a generic interface for bringing interfaces down
ifconfig_down() {
	ifconfig "$1" down
}

# bool ifconfig_is_up(char *iface, bool withaddress)
#
# Returns 0 if the interface is up, otherwise 1
# If withaddress is true then the interface has to have an IPv4 address
# assigned as well
ifconfig_is_up() {
	[[ $(ifconfig "$1") == *"<UP"* ]] || return 1
	[[ ${2:-false} != "true" ]] || return 0
	[[ -n $(ifconfig_get_address "$1") ]]
}

# void ifconfig_set_flag(char *iface, char *flag, bool enabled)
#
# Sets or disables the interface flag 
ifconfig_set_flag() {
	local iface="$1" flag="$2" enable="$3"
	${enable} || flag="-${flag}"
	ifconfig "${iface}" "${flag}"
}

# void ifconfig_get_address(char *interface)
#
# Fetch the address retrieved by DHCP.  If successful, echoes the
# address on stdout, otherwise echoes nothing.
ifconfig_get_address() {
	[[ $(ifconfig "$1") \
	=~ $'\n'[[:space:]]*inet\ ([^\ ]*)\ netmask\ ([^\ ]*) ]] \
		|| return 1
	echo "${BASH_REMATCH[1]}/$(netmask2cidr "${BASH_REMATCH[2]}")"
}

# bool ifconfig_is_ethernet(char *interface)
#
# Return 0 if the link is ethernet, otherwise 1.
ifconfig_is_ethernet() {
	[[ $(ifconfig "$1") == *$'\n'[[:space:]]+"media: Ethernet "* ]]
}

# bool ifconfig_has_carrier(char *iface)
#
# Return 0 if we have a carrier
ifconfig_has_carrier() {
	local s=$(ifconfig "$1" | sed -ne 's/^[[:space:]]status: \(.*\)$/\1/p')
	[[ -z ${s} || ${s} == "active" || ${s} == "associated" ]] 
}

# void ifconfig_get_mac_address(char *interface)
#
# Fetch the mac address assingned to the network card
ifconfig_get_mac_address() {
	[[ $(ifconfig "$1") =~ $'\n'[[:space:]]*ether\ (..:..:..:..:..:..) ]] \
		|| return 1
	
	local mac="${BASH_REMATCH[1]}"
	[[ ${mac} != '00:00:00:00:00:00' \
	&& ${mac} != '44:44:44:44:44:44' \
	&& ${mac} != 'FF:FF:FF:FF:FF:FF' ]] \
		&& echo "${mac}"
}

# void ifconfig_set_mac_address(char *interface, char *mac)
#
# Assigned the mac address to the network card
ifconfig_set_mac_address() {
	ifconfig "$1" ether "$2"
}

# int ifconfig_set_name(char *interface, char *new_name)
#
# Renames the interface
ifconfig_set_name() {
	[[ -z $2 ]] && return 1
	ifconfig "$1" name "$2"
}

# void ifconfig_get_aliases_rev(char *interface)
#
# BSD does not support this concept, so just return
ifconfig_get_aliases_rev() {
	return 0
}

# bool ifconfig_del_addresses(char *interface, bool onlyinet)
#
# Remove addresses from interface.  Returns 0 (true) if there
# were addresses to remove (whether successful or not).  Returns 1
# (false) if there were no addresses to remove.
# If onlyinet is true then we only delete IPv4 / inet addresses
ifconfig_del_addresses() {
	local iface="$1" i= onlyinet="${2:-false}"
	# We don't remove addresses from aliases
	[[ ${iface} == *:* ]] && return 0

	# If the interface doesn't exist, don't try and delete
	ifconfig_exists "${iface}" || return 0

	local addr=$(ifconfig_get_address "${iface}")
	while [[ -n ${addr} ]] ; do
		ifconfig "${iface}" delete "${addr%/*}"
		addr=$(ifconfig_get_address "${iface}")
	done

	# Remove IPv6 addresses
	if ! ${onlyinet} ; then
		for i in $(ifconfig "${iface}" | \
		sed -n -e 's/^[[:space:]]*inet6 \([^ ]*\).*/\1/p') ; do
			[[ ${i} == *"%${iface}" ]] && continue
			ifconfig "${iface}" inet6 delete "${i}"
		done
	fi
	return 0
}

# bool ifconfig_get_old_config(char *iface)
#
# Returns config and config_fallback for the given interface
ifconfig_get_old_config() {
	# Don't support old config on FreeBSD :)
	return 0
}

# bool ifconfig_iface_stop(char *interface)
ifconfig_iface_stop() {
	# No need for this on FreeBSD :)
	return 0
}

# bool ifconfig_pre_start(char *interface)
#
# Runs any pre_start stuff on our interface - just the MTU atm
# We set MTU twice as it may be needed for DHCP - a dhcp client could
# change it in error, so we set MTU in post start too
ifconfig_pre_start() {
	local iface="$1"

	interface_exists "${iface}" || return 0

	local ifvar=$(bash_variable "$1")

	# MTU support
	local mtu="mtu_${ifvar}"
	[[ -n ${!mtu} ]] && ifconfig "${iface}" mtu "${!mtu}"

	return 0
}

# bool ifconfig_add_address(char *iface, char *options ...)
#
# Adds the given address to the interface
ifconfig_add_address() {
	local iface="$1"

	# Extract the config
	local -a config=( "$@" )
	config=( ${config[@]:1} )

	if [[ ${config[0]} == *:* ]]; then
		# Support IPv6 - nice and simple
		config[0]="inet6 add ${config[0]}"
	else
		# Support iproute2 style config where possible
		local x="${config[@]}"
		config=( ${x//brd +/} )
		config=( "${config[@]//brd/broadcast}" )
		config=( "${config[@]//peer/pointopoint}" )
		config=( "${config[@]//pointtopoint}" )
		config[0]="inet add ${config[0]}"
	fi

	# Finally add the address
	ifconfig "${iface}" ${config[@]}
}

# bool ifconfig_post_start(char *iface)
#
# Bring up iface using ifconfig utilities, called from iface_start
#
# Returns 0 (true) when successful on the primary interface, non-zero
# (false) when the primary interface fails.  Aliases are allowed to
# fail, the routine should still return success to indicate that
# net.eth0 was successful
ifconfig_post_start() {
	local iface="$1" ifvar=$(bash_variable "$1") x= y= 
	local metric="metric_${ifvar}" mtu="mtu_${ifvar}"
	local -a routes=()

	ifconfig_exists "${iface}" || return 0
	
	# Apply metric and MTU if required
	[[ -n ${!metric} ]] && ifconfig "${iface}" metric "${!metric}"
	[[ -n ${!mtu} ]] && ifconfig "${iface}" mtu "${!mtu}"

	x="routes_${ifvar}[@]"
	routes=( "${!x}" )
	[[ -z ${routes} ]] && return 0

	# Add routes for this interface, might even include default gw
	einfo $"Adding routes"
	eindent
	for x in "${routes[@]}"; do
		ebegin "${x}"

		# Support iproute2 style routes
		x="${x//via/gw} "
		x="${x//scope * / }"
		x="${x//gw/}"

		# Work out if we're a host or a net if not told
		if [[ " ${x} " != *" -net "* && " ${x} " != *" -host "* ]] ; then
			y="${x%% *}"
			if [[ ${x} == *" netmask "* ]] ; then
				x="-net ${x}"
			elif [[ ${y} == *.*.*.*/32 ]] ; then
				x="-host ${x}"
			elif [[ ${y} == *.*.*.*/* || ${y} == "0.0.0.0" \
				|| ${y} == "default" ]] ; then
				x="-net ${x}"
			else
				# Given the lack of a netmask, we assume a host
				x="-host ${x}"
			fi
		fi

		# Support adding IPv6 addresses easily
		if [[ ${x} == *:* ]]; then
			[[ ${x} != *"-A inet6"* ]] && x="-A inet6 ${x}"
			x="${x// -net / }"
		fi

		route add ${x} >/dev/null
		eend $?
	done
	eoutdent

	return 0
}

# vim: set ts=4 :
