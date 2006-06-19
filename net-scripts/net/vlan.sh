# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
vconfig() {
	LC_ALL=C /sbin/vconfig "$@"
}

# void vlan_depend(void)
#
# Sets up the dependancies for the module
vlan_depend() {
	after interface
	before dhcp
	functions iface_start iface_stop
}

# void vlan_expose(void)
#
# Expose variables that can be configured
vlan_expose() {
	variables vlans 
}

# bool vlan_check_installed(void)
#
# Returns 0 if vconfig is installed, otherwise 1
vlan_check_installed() {
	[[ -x /sbin/vconfig ]] && return 0
	${1:-false} && eerror "For VLAN (802.1q) support, emerge net-misc/vconfig"
	return 1
}

# bool vlan_exists(char *interface)
#
# Returns 0 if the interface is a vlan, otherwise 1
vlan_exists() {
	[[ ! -d /proc/net/vlan ]] && return 1
	egrep -q "^$1[[:space:]]+" /proc/net/vlan/config
}

# char* vlan_get_vlans(char *interface)
#
# Fetch the configured vlans for an interface.  Outputs a space
# separated list on stdout.  For example "eth0.1 eth0.2 eth0.3"
vlan_get_vlans() {
	sed -n -e 's/^\(.*[0-9]\) \(.* \) .*'"$1"'$/\1/p' \
		/proc/net/vlan/config 2>/dev/null
}

# bool vlan_check_kernel(void)
#
# Checks to see if the 802.1q module is present - if not try and load it
# Returns 1 if there is a problem
vlan_check_kernel() {
	[[ -d /proc/net/vlan ]] && return 0
	/sbin/modprobe 8021q &>/dev/null
	[[ -d /proc/net/vlan ]] && return 0
	eerror "VLAN (802.1q) support is not present in this kernel"
	return 1
}

#bool vlan_pre_start(char *iface)
#
# Setup vconfig
vlan_pre_start() {
	local iface="$1" opts= i= x= e= ifvar=$(bash_variable "$1")
	
	opts="vconfig_${ifvar}[@]"
	[[ -z ${!opts} ]] && return 0
	opts=( "${!opts}" )

	vlan_check_kernel || return 1
	interface_exists "${iface}" || return 1

	for (( i=0; i<${#opts[@]}; i++ )) ; do
		if [[ ${opts[i]} == "set_name_type "* ]]; then
			x="${opts[i]}"
		else
			x="${opts[i]/ / ${iface} }"
			[[ ${x} == "${opts[i]}" ]] && x="${x} ${iface}"
		fi
		e=$(vconfig ${x} 2>&1 1>/dev/null)
		[[ -z ${e} ]] && continue
		eerror "vconfig ${x}"
		eerror "${e}"
		return 1
	done

	return 0
}

# bool vlan_post_start(char *iface)
#
# Starts VLANs for a given interface
#
# Always returns 0 (true) 
vlan_post_start() {
	local iface="$1" ifvar=$(bash_variable "$1")
	local vlan= vlans= vlans_old= ifname= vlans="vlans_${ifvar}[@]"
	local start="vlan_start_${ifvar}"

	# BACKWARD COMPATIBILITY: check for old vlan variable name
	vlans_old="iface_${ifvar}_vlans"
	[[ -n ${!vlans_old} && -z ${!vlans} ]] && vlans="vlans_old"

	[[ -z ${!vlans} ]] && return 0

	vlan_check_kernel || return 1
	interface_exists "${iface}" true || return 1

	# Start vlans for this interface
	for vlan in ${!vlans} ; do
		einfo "Adding VLAN ${vlan} to ${iface}"
		e=$(vconfig add "${iface}" "${vlan}" 2>&1 1>/dev/null)
		if [[ -n ${e} ]] ; then
			eend 1 "${e}"
			continue
		fi
		eend 0

		# We may not want to start the vlan ourselves, but
		# as a seperate init script. This allows the vlan to be
		# renamed if needed.
		[[ -n ${!start} && ${!start} != "yes" ]] && continue
		
		# We need to work out the interface name of our new vlan id
		ifname=$( \
			sed -n -e 's/^\([^ \t]*\) *| '"${vlan}"' *| .*'"${iface}"'$/\1/p' \
			/proc/net/vlan/config
		)
		mark_service_started "net.${ifname}"
		iface_start "${ifname}" || mark_service_stopped "net.${ifname}"
	done

	return 0
}

# bool vlan_stop(char *iface)
#
# Stops VLANs for a given interface
#
# Always returns 0 (true) 
vlan_stop() {
	local iface="$1" vlan=

	vlan_check_installed || return 0

	for vlan in $(vlan_get_vlans "${iface}"); do
		einfo "Removing VLAN ${vlan##*.} from ${iface}"
		if iface_stop "${vlan}" ; then
			mark_service_stopped "net.${vlan}"
			vconfig rem "${vlan}" >/dev/null
		fi
	done

	return 0
}

# vim: set ts=4 :
