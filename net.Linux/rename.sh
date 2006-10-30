# Copyright (c) 2005-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void rename_depend(void)
#
# Sets up the dependancies for the module
rename_depend() {
	after macchanger
	before wireless interface
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
	local iface="$1" newname= mac= ifvar=$(bash_variable "$1")
	interface_exists "${iface}" || return 0

	newname="rename_${ifvar}"
	[[ -z ${!newname} || ${iface} == "${!newname}" ]] && return 0

	# We don't work on bonded, bridges, tun/tap or vlan
	for f in bonding bridge tuntap vlan ; do
		if is_function "${f}_exists" ; then
			if ${f}_exists "${iface}" ; then
				veinfo $"Cannot rename a" "${f}" $"interface"
				return 0
			fi
		fi
	done

	ebegin $"Renaming" "\"${iface}\"" $"to" "\"${!newname}\""

	# Ensure that we have an init script
	[[ ! -e "/etc/init.d/net.${!newname}" ]] \
		&& ( cd /etc/init.d ; ln -s net.lo "net.${!newname}" )

	# Ensure that the interface is down and without any addresses or we
	# will not work
	interface_del_addresses "${iface}"
	interface_down "${iface}"
	interface_set_name "${iface}" "${!newname}"
	eend $? $"Failed to rename interface" || return 1

	# Mark us as stopped, start the new interface and bail cleanly
	mark_service_stopped "net.${iface}"
	einfo $"Stopped configuration of" "${iface}" $"due to renaming"
	service_stopped "net.${!newname}" && start_service "net.${!newname}"

	exit 1 
}

# vim: set ts=4 :
