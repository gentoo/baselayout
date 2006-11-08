#!/bin/bash
# Copyright (c) 2004-2005 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
openvpn() {
	LC_ALL=C /usr/sbin/openvpn "$@"
}
tunctl() {
	LC_ALL=C /usr/bin/tunctl "$@"
}

# void tuntap_depend(void)
#
# Sets up the dependancies for the module
tuntap_depend() {
	before bridge interface macchanger
	functions interface_exists interface_type
	variables tunctl
}

# bool tuntap_check_installed(void)
#
# Returns 1 if tuntap is installed, otherwise 0
tuntap_check_installed() {
	[[ -x /usr/sbin/openvpn ]] && return 0
	[[ -x /usr/bin/tunctl ]] && return 0
	${1:-false} && eerror "For TunTap support, emerge net-misc/openvpn or sys-apps/usermode-utilities"
	return 1
}

# bool tuntap_check_kernel(void)
#
# Checks to see if the tun is present - if not try and load it
# Returns 1 if there is a problem
tuntap_check_kernel() {
	[[ -a /dev/net/tun ]] && return 0
	/sbin/modprobe tun && sleep 1
	[[ -a /dev/net/tun ]] && return 0
	eerror "TUN/TAP support is not present in this kernel"
	return 1
}

# bool tuntap_exists(char *interface)
#
# Returns 0 if the tun/tap interface exists, otherwise 1
tuntap_exists() {
	[[ -n $(get_options tuntap "net.$1") ]]
}

# bool tuntap_pre_start(char *iface)
#
# Create the device, give it the right perms
tuntap_pre_start() {
	local iface="$1" ifvar=$(bash_variable "$1")
	local tuntap="tuntap_${ifvar}"

	[[ -z ${!tuntap} ]] && return 0
	tuntap_check_kernel || return 1

	ebegin "Creating Tun/Tap interface ${iface}"

	# Set the base metric to 1000
	metric=1000
	
	if [[ -x /usr/sbin/openvpn ]] ; then
		openvpn --mktun --dev-type "${!tuntap}" --dev "${iface}" \
			> /dev/null
	else
		local opts="tunctl_${ifvar}"
		tunctl ${!opts} -t "${iface}" >/dev/null
	fi
	eend $? && save_options tuntap "${!tuntap}"
}

# bool tuntap_stop(char *iface)
#
# Removes the device
tuntap_stop() {
	local iface="$1"

	tuntap_check_installed || return 0
	tuntap_exists "${iface}" || return 0

	ebegin "Destroying Tun/Tap interface ${iface}"
	if [[ -x /usr/sbin/openvpn ]] ; then
		openvpn --rmtun \
			--dev-type "$(get_options tuntap)" \
			--dev "${iface}" > /dev/null
	else
		tunctl -d "${iface}" >/dev/null
	fi
	eend $?
}

# vim:ts=4
