# Copyright (c) 2005-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void rename_depend(void)
#
# Sets up the dependancies for the module
rename_depend() {
	after macchanger
	before wireless interface
	functions interface_exists interface_down interface_del_addresses
}

# void rename_expose(void)
#
# Expose variables that can be configured
rename_expose() {
	variables rename
}

# bool rename_pre_start(char *iface)
#
# Checks to see if we have to rename the interface 
rename_pre_start() {
	local iface="$1" newname="" mac ifvar="$(bash_variable "$1")"

	interface_exists "${iface}" || return 0

	newname="rename_${ifvar}"
	[[ -z ${!newname} || ${iface} == "${!newname}" ]] && return 0

	# We cannot rename vlan interfaces as /proc/net/vlan/config always
	# returns the old interface name. We don't bail out though as it's
	# not critical that the interface gets renamed.
	if [[ -d /proc/net/vlan/config ]] ; then
		if grep -q "^${iface} " /proc/net/vlan/config ; then
			eerror "Cannot rename VLAN interfaces"
			return 0
		fi
	fi

	ebegin "Renaming \"${iface}\" to \"${!newname}\""

	# Ensure that we have an init script
	[[ ! -e "/etc/init.d/net.${!newname}" ]] \
		&& ( cd /etc/init.d ; ln -s net.lo "net.${!newname}" )

	# Ensure that the interface is down and without any addresses or we
	# will not work
	interface_del_addresses "${iface}"
	interface_down "${iface}"
	interface_set_name "${iface}" "${!newname}"
	eend $? "Failed to rename interface" || return 1

	# Mark us as stopped, start the new interface and bail cleanly
	mark_service_stopped "net.${iface}"
	einfo "Stopped configuration of ${iface} due to renaming"
	service_stopped "net.${!newname}" && start_service "net.${!newname}"

	exit 1 
}

# vim: set ft=sh ts=4 :
