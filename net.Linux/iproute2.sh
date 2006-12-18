# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
ip() {
	LC_ALL=C /sbin/ip "$@"
}
iproute2_tunnel() {
	LC_ALL=C /sbin/ip tunnel "$@"
}

# void iproute2_depend(void)
#
# Sets up the dependancies for the module
iproute2_depend() {
	provide interface
}

# void iproute2_expose(void)
#
# Expose variables that can be configured
iproute2_expose() {
	variables config routes fallback metric ipaddr ipaddr_fallback iproute inet6
}

# bool iproute2_check_installed(void)
#
# Returns 1 if iproute2 is installed, otherwise 0
iproute2_check_installed() {
	[[ -x /sbin/ip ]] && return 0
	${1:-false} && eerror $"For iproute2 support, emerge sys-apps/iproute2"
	return 1
}

# bool iproute2_exists(char *interface, bool report)
#
# Returns 1 if the interface exists, otherwise 0
iproute2_exists() {
	local e=$(ip addr show label "$1") report="${2:-false}"
	[[ -n ${e} ]] && return 0

	if ${report} ; then
		eerror $"network interface" "$1" $"does not exist"
		eerror $"Please verify hardware or kernel module (driver)"
	fi
	return 1
}

# void iproute2_up(char *interface)
#
# provides a generic interface for bringing interfaces up
iproute2_up() {
	ip link set up dev "$1"
}

# void iproute2_down(char *interface)
#
# provides a generic interface for bringing interfaces up
iproute2_down() {
	ip link set down dev "$1"
}

# bool ifproute2_is_up(char *iface, bool withaddress)
#
# Returns 0 if the interface is up, otherwise 1
# If withaddress is true then the interface has to have an IPv4 address
# assigned as well
iproute2_is_up() {
	local check="\<UP\>" addr="${2:-false}"
	${addr} && check="${check}.*inet "
	[[ $(ip addr show "$1") =~ ${check} ]]
}

# bool ifconfig_has_carrier(char *iface)
#
# Return 0 if we have a carrier
# Don't trust Linux drivers yet, so always 0
iproute2_has_carrier() {
	return 0
}

# void iproute2_set_flag(char *iface, char *flag, bool enabled)
#
# Sets or disables the interface flag 
iproute2_set_flag() {
	local enable="$3" opt="on"
	${enable} || opt="off"
	ip link set "$1" "$2" "${opt}"
}

# void iproute2_get_address(char *interface)
#
# Fetch the address retrieved by DHCP.  If successful, echoes the
# address on stdout, otherwise echoes nothing.
iproute2_get_address() {
	ip -family inet addr show "$1" | sed -n -e 's/.*inet \([^ ]*\).*/\1/p'
}

# bool iproute2_is_ethernet(char *interface)
#
# Return 0 if the link is ethernet, otherwise 1.
iproute2_is_ethernet() {
	[[ $(ip link show "$1") == *" link/ether "* ]]
}

# void iproute2_get_mac_address(char *interface)
#
# Fetch the mac address assingned to the network card
iproute2_get_mac_address() {
	local mac=$( ip link show "$1" | sed -n -e \
		'/link\// s/^.*\<\(..:..:..:..:..:..\)\>.*/\U\1/p' )
	[[ ${mac} != '00:00:00:00:00:00' \
	&& ${mac} != '44:44:44:44:44:44' \
	&& ${mac} != 'FF:FF:FF:FF:FF:FF' ]] \
		&& echo "${mac}"
}

# void iproute2_set_mac_address(char *interface, char *mac)
#
# Assigned the mac address to the network card
iproute2_set_mac_address() {
	ip link set address "$2" dev "$1"
}

# int iproute2_set_name(char *interface, char *new_name)
#
# Renames the interface
# This will not work if the interface is setup!
iproute2_set_name() {
	ip link set name "$2" dev "$1"
}

# void iproute2_get_aliases_rev(char *interface)
#
# Fetch the list of aliases for an interface.  
# Outputs a space-separated list on stdout, in reverse order, for
# example "eth0:2 eth0:1"
iproute2_get_aliases_rev() {
	local iface=$( interface_device "$1" )
	ip addr show dev "${iface}" | grep -Eo "${iface}:[^ ]+" | sed '1!G;h;$!d'
}

# bool iproute2_del_addresses(char *interface, bool onlyinet)
#
# Remove addresses from interface.
# If onlyinet is true, then we only remove IPv4 / inet addresses.
iproute2_del_addresses() {
	local pre=
	${2:-false} && pre="-f inet"
	ip ${pre} addr flush label "$1" scope global &>/dev/null
	ip ${pre} addr flush label "$1" scope site &>/dev/null
	ip ${pre} addr flush label "$1" scope host &>/dev/null
	return 0
}

# bool iproute2_get_old_config(char *iface)
#
# Returns config and config_fallback for the given interface
iproute2_get_old_config() {
	local ifvar=$( bash_variable "$1" ) inet6= t=

	# iproute2-style config vars
	t="ipaddr_${ifvar}[@]"
	config=( "${!t}" )
	t="config_fallback_${ifvar}[@]"
	config_fallback=( "${!t}" )
	t="inet6_${ifvar}[@]"
	inet6=( "${!t}" )

	# BACKWARD COMPATIBILITY: check for space-separated inet6 addresses
	[[ ${#inet6[@]} == "1" && ${inet6} == *" "* ]] && inet6=( ${inet6} )

	# Add inet6 addresses to our config if required
	[[ -n ${inet6} ]] && config=( "${config[@]}" "${inet6[@]}" )

	# Support old style iface_xxx syntax
	if [[ -z ${config} ]] ; then
		if is_function ifconfig_get_old_config ; then
			ifconfig_get_old_config "${iface}"
		fi
	fi

	return 0
}

# bool iproute2_iface_stop(char *interface)
#
# Do final shutdown for an interface or alias.
#
# Returns 0 (true) when successful, non-zero (false) on failure
iproute2_iface_stop() {
	local label="$1" iface=$( interface_device "$1" )

	# Shut down the link if this isn't an alias or vlan
	if [[ ${label} == "${iface}" ]] ; then
		iproute2_down "${iface}"
		return $?
	fi
	return 0
}

# bool iproute2_add_address(char *interface, char *options ...)
#
# Adds an the specified address to the interface
# returns 0 on success and non-zero on failure
iproute2_add_address() {
	local iface="$1" x=

	iproute2_exists "${iface}" true || return 1

	# Extract the config
	local -a config=( "$@" )
	config=( ${config[@]:1} )

	# Convert an ifconfig line to iproute2
	local n="${#config[@]}"
	for (( x=0; x<n; x++ )); do
		case "${config[x]}" in
			netmask)
				config[0]="${config[0]}/$( netmask2cidr "${config[x+1]}" )"
				unset config[x] config[x+1]
				;;
			mtu)
				ip link set mtu "${config[x+1]}" dev "${iface}"
				unset config[x] config[x+1]
				;;
		esac
	done
	config=( "${config[@]//pointopoint/peer}" )

	# Always scope lo addresses as host unless specified otherwise
	if [[ " ${config[@]} " != *" scope "* ]] ; then
		is_loopback "${iface}" && config=( "${config[@]}" "scope host" )
	fi

	# IPv4 specifics
	if [[ ${config[@]} == *.*.*.* ]] ; then
		# Work out a broadcast if none supplied
		[[ ${config[@]} != *" brd "* && ${config[@]} != *" broadcast "* ]] \
			&& config=( "${config[@]}" "brd +" )
	fi

	# Some kernels like to apply lo with an address when they are brought up
	if [[ ${config[@]} == "127.0.0.1/8 brd 127.255.255.255 scope host" ]] ; then
		is_loopback "${iface}" && ip addr del dev "${iface}" 127.0.0.1/8 2>/dev/null
	fi

	ip addr add dev "${iface}" ${config[@]}
}

# bool iproute2_pre_start(char *interface)
#
# Runs any pre_start stuff on our interface - just the MTU atm
# We set MTU twice as it may be needed for DHCP - a dhcp client could
# change it in error, so we set MTU in post start too
iproute2_pre_start() {
	local iface="$1"

	interface_exists "${iface}" || return 0

	local ifvar=$( bash_variable "$1" )

	# MTU support
	local mtu="mtu_${ifvar}"
	[[ -n ${!mtu} ]] && ip link set mtu "${!mtu}" dev "${iface}"

	return 0
}

# bool iproute2_post_start(char *interface)
#
# Runs any post_start stuff on our interface and adds routes
# Always returns 0
iproute2_post_start() {
	local iface="$1" ifvar=$( bash_variable "$1" ) x=

	iproute2_exists "${iface}" || return 0
	
	# MTU support
	local mtu="mtu_${ifvar}"
	[[ -n ${!mtu} ]] && ip link set mtu "${!mtu}" dev "${iface}"

	local x="routes_${ifvar}[@]"
	local -a routes=( "${!x}" )
	local metric="metric_${ifvar}"

	# Test for old style ipaddr variable
	if [[ -z ${routes} ]] ; then
		t="iproute_${ifvar}[@]"
		routes=( "${!t}" )
	fi

	# Set routes with ip route -- this might also include default route
	if [[ -n ${routes} ]] ; then
		einfo $"Adding routes"
		eindent
		for x in "${routes[@]}"; do
			ebegin "${x}"

			# Support net-tools routing too
			x="${x//gw/via}"
			x="${x//-A inet6/}"
			x="${x//-net/}"
			[[ " ${x} " == *" -host "* ]] && x="${x//-host/} scope host"

			# Attempt to support net-tools route netmask option
			netmask="${x##* netmask }"
			if [[ -n ${netmask} && ${x} != "${netmask}" ]] ; then
				netmask="${netmask%% *}"
				x="${x// netmask ${netmask} / }"
				local -a a=( ${x} )
				a[0]="${a[0]}/$( netmask2cidr "${netmask}")"
				x="${a[@]}"
			fi

			# Add a metric if we don't have one
			[[ " ${x} " != *" metric "* ]] && x="${x} metric ${!metric}"

			ip route append ${x} dev "${iface}"
			eend $?
		done
		eoutdent
	fi

	# Flush the route cache
	ip route flush cache dev "${iface}"

	return 0
}

# void iproute2_post_stop(char* interface)
iproute2_post_stop() {
	local iface="$1" rule=

	iproute2_exists "${iface}" || return

	# Flush the route cache
	ip route flush cache dev "${iface}"
}

# vim: set ts=4 :
