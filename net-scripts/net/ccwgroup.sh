# Copyright 2006-2008 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

ccwgroup_depend() {
	before interface
}
ccwgroup_expose() {
	variables ccwgroup
}

ccwgroup_load_modules() {
	# make sure we have ccwgroup support or this is a crap shoot
	if [[ ! -d /sys/bus/ccwgroup ]] ; then
		[[ -e /proc/modules ]] && modprobe -q ccwgroup
		if [[ ! -d /sys/bus/ccwgroup ]] ; then
			eerror "ccwgroup support missing in kernel"
			return 1
		fi
	fi

	# verify the specific interface is supported
	if [[ ! -d /sys/bus/ccwgroup/drivers/$1 ]] ; then
		modprobe $1 >& /dev/null
		if [[ ! -d /sys/bus/ccwgroup/drivers/$1 ]] ; then
			eerror "$1 support missing in kernel"
			return 1
		fi
	fi

	return 0
}

ccwgroup_pre_start() {
	local iface="$1" ifvar=$(bash_variable "$1")
	local ccw="ccwgroup_${ifvar}[@]"
	local -a ccwgroup=( "${!ccw}" )

	local var
	var="ccwgroup_type_${ifvar}"
	local ccw_type=${!var:-qeth}
	var="ccwgroup_opts_${ifvar}[@]"
	local -a ccw_opts=( "${!var}" "online=1" )

	[[ -z ${!ccw} ]] && return 0
	ccwgroup_load_modules ${ccw_type} || return 1

	einfo "Enabling ccwgroup/${ccw_type} on ${iface}"
	if [[ -e /sys/devices/${ccw_type}/${ccwgroup[0]} ]] ; then
		echo "0" > /sys/devices/${ccw_type}/${ccwgroup[0]}/online
	else
		echo "${!ccw// /,}" > /sys/bus/ccwgroup/drivers/${ccw_type}/group
	fi

	local val idx=0
	while [[ -n ${ccw_opts[${idx}]} ]] ; do
		var=${ccw_opts[${idx}]%%=*}
		val=${ccw_opts[${idx}]#*=}
		echo "${val}" > /sys/devices/${ccw_type}/${ccwgroup[0]}/${var}
		((idx++))
	done
	eend $?
}

ccwgroup_pre_stop() {
	local iface="$1"

	# Erase any existing ccwgroup to be safe
	save_options ccwgroup_device ""
	save_options ccwgroup_type ""

	[[ ! -L /sys/class/net/"${iface}"/driver ]] && return 0
	local driver=$(readlink /sys/class/net/"${iface}"/driver)
	[[ ${driver} != *"/bus/ccwgroup/"* ]] && return 0

	local device
	device=$(readlink /sys/class/net/"${iface}"/device)
	device=${device##*/}
	save_options ccwgroup_device "${device}"
	device=$(readlink /sys/class/net/"${iface}"/device/driver)
	device=${device##*/}
	save_options ccwgroup_type "${device}"
}

ccwgroup_post_stop() {
	local iface="$1"
	local device=$(get_options ccwgroup_device)
	local ccw_type=$(get_options ccwgroup_type)

	[[ -z ${device} || -z ${ccw_type} ]] && return 0

	einfo "Disabling ccwgroup/${ccw_type} on ${iface}"
	echo "0"  > /sys/devices/${ccw_type}/"${device}"/online
	echo "1"  > /sys/devices/${ccw_type}/"${device}"/ungroup
	eend $?
}

# vim: set ts=4 :
