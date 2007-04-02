# Copyright 2006-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

ccwgroup_depend() {
	before interface 
}
ccwgroup_expose() {
	variables ccwgroup
}

ccwgroup_pre_start() {
	local iface="$1" ifvar=$(bash_variable "$1")
	local ccw="ccwgroup_${ifvar}[@]"
	local -a ccwgroup=( "${!ccw}" )

	local qeth_layer2="qeth_layer2_${ifvar}[@]"
	local layer2=${!qeth_layer2:-0}

	[[ -z ${!ccw} ]] && return 0
	if [[ ! -d /sys/bus/ccwgroup ]] ; then
		modprobe qeth >& /dev/null
		if [[ ! -d /sys/bus/ccwgroup ]] ; then
			eerror $"ccwgroup support missing in kernel"
			return 1
		fi
	fi

	einfo $"Enabling ccwgroup on" "${iface}"
	if [[ -e /sys/devices/qeth/"${ccwgroup[0]}" ]] ; then
		echo "0" > /sys/devices/qeth/"${ccwgroup[0]}"/online
	else
		echo "${!ccw// /,}" > /sys/bus/ccwgroup/drivers/qeth/group
	fi
	echo "${layer2}" > /sys/devices/qeth/"${ccwgroup[0]}"/layer2
	echo "1" > /sys/devices/qeth/"${ccwgroup[0]}"/online
	eend $?
}

ccwgroup_pre_stop() {
	local iface="$1"

	# Erase any existing ccwgroup to be safe
	save_options ccwgroup_device ""
	
	[[ ! -L /sys/class/net/"${iface}"/driver ]] && return 0
	local driver=$(readlink /sys/class/net/"${iface}"/driver)
	[[ ${driver} != *"/bus/ccwgroup/"* ]] && return 0

	local device=$(readlink /sys/class/net/"${iface}"/device)
	device="${device##*/}"
	save_options ccwgroup_device "${device}"
}

ccwgroup_post_stop() {
	local iface="$1" device=$(get_options ccwgroup_device)
	
	[[ -z ${device} ]] && return 0
	
	einfo $"Disabling ccwgroup on" "${iface}"
	echo "0"  > /sys/devices/qeth/"${device}"/online
	echo "1"  > /sys/devices/qeth/"${device}"/ungroup
	eend $?
}

# vim: set ts=4 :
