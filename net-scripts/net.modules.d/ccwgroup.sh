# Copyright (c) 2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

ccwgroup_depend() {
	before interface 
}
ccwgroup_expose() {
	variables ccwgroup
}

ccwgroup_pre_start() {
	local iface="$1" ifvar="$(bash_variable "$1")"
	local ccwgroup="ccwgroup_${ifvar}[@]"

	[[ -z ${!ccwgroup} ]] && return 0
	if [[ ! -d /sys/bus/ccwgroup ]] ; then
		eerror "ccwgroup support missing in kernel"
		return 1
	fi

	einfo "Enabling ccwgroup on ${iface}"
	echo "${!ccwgroup// /,}" > /sys/bus/ccwgroup/drivers/qeth/group
	echo "1" > /sys/devices/qeth/"${!ccwgroup[0]}"/online
	eend $?
}

ccwgroup_post_stop() {
	local iface="$1"
	
	[[ ! -L /sys/class/net/"${iface}"/driver ]] && return 0
	local driver="$(readlink /sys/class/net/"${iface}"/driver)"
	[[ ${driver} != *"/bus/ccwgroup/"* ]] && return 0
	
	einfo "Disabling ccwgroup on ${iface}"
	echo "0"  > /sys/class/net/"${iface}"/device/online
	echo "1"  > /sys/class/net/"${iface}"/device/ungroup
	eend $?
}

# vim: set ft=sh ts=4 :
