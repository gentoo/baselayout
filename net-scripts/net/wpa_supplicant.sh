# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
wpa_supplicant() {
	LC_ALL=C /sbin/wpa_supplicant "$@"
}

wpa_cli() {
	if [[ -n ${ctrl_dir} ]] ; then
		LC_ALL=C /bin/wpa_cli -p "${ctrl_dir}" "$@"
	else
		LC_ALL=C /bin/wpa_cli "$@"
	fi
}

# void wpa_supplicant_depend(void)
#
# Sets up the dependancies for the module
wpa_supplicant_depend() {
	after macnet plug
	before interface
	provide wireless
	functions interface_exists
}

# void wpa_supplicant_expose(void)
#
# Expose variables that can be configured
wpa_supplicant_expose() {
	variables associate_timeout wpa_supplicant
}

# bool wpa_supplicant_check_installed(void)
#
# Returns 0 if wpa_supplicant is installed, otherwise 1
wpa_supplicant_check_installed() {
	local report="${1:-false}" installed="0"
	if [[ ! -x /sbin/wpa_supplicant ]] ; then
		installed="1"
		${report} && eerror "For WPA support (wpa_supplicant) support, emerge net-wireless/wpa_supplicant"
	fi
	if [[ ! -e /proc/net/packet ]] ; then
		installed="1"
		if ${report} ; then
			eerror "wpa_supplicant requires Packet Socket"
			eerror "(CONFIG_PACKET=y) enabled in the kernel"
		fi
	fi
	return "${installed}"
}

# bool wpa_supplicant_exists(char *interface)
#
# Checks to see if wireless extensions are enabled on the interface
wpa_supplicant_exists() {
	[[ ! -e /proc/net/wireless ]] && return 1
	grep -q "^[ \t]*$1:" /proc/net/wireless
}

# char* wpa_supplicant_get_essid(char *interface)
#
# Gets the current ESSID of iface
wpa_supplicant_get_essid() {
	local i= essid=

	for (( i=0; i<5; i++ )); do
		essid=$( wpa_cli -i"$1" status | sed -n -e 's/^ssid=//p' )
		if [[ -n ${essid} ]] ; then
			echo "${essid}"
			return 0
		fi
		sleep 1
	done

	return 1
}

# char* wpa_supplicant_get_ap_mac_address(char *interface)
#
# Returns the MAC address of the Access Point
# the interface is connected to
wpa_supplicant_get_ap_mac_address() {
	wpa_cli -i"$1" status | sed -n -e 's/^bssid=\([^=]\+\).*/\U\1/p'
}

# bool wpa_supplicant_associated(char *interface)
#
# Returns 0 if we're associated correctly or 1 if not
# Note that just because we are associated does not mean we are using the
# correct encryption keys
wpa_supplicant_associated() {
	local -a status=()
	eval status=( $(wpa_cli -i"$1" status \
		| sed -n -e 's/^\(key_mgmt\|wpa_state\|EAP state\)=\([^=]\+\).*/\U\"\2\"/p')
	)

	case "${status[0]}" in
		"NONE")
			[[ ${status[1]} == "ASSOCIATED" || ${status[1]} == "COMPLETED" ]]
			;;
		"IEEE 802.1X (no WPA)")
			[[ ${status[2]} == "SUCCESS" ]]
			;;
		*)
			[[ ${status[1]} == "COMPLETED" ]]
			;;
	esac

	return $?
}

# void wpa_supplicant_kill(char *interface, bool report)
#
# Kills any existing wpa_supplicant process on the interface
wpa_supplicant_kill() {
	local iface="$1" report="${2:-false}" pidfile=

	# Shutdown wpa_cli first, if it's running
	# This is important as future versions of wpa_supplicant
	# may send a disconnect message to wpa_cli when it shutsdown
	pidfile="/var/run/wpa_cli-${iface}.pid"
	if [[ -f ${pidfile} ]] ; then
		${report} && ebegin "Stopping wpa_cli on ${iface}"
		start-stop-daemon --stop --exec /bin/wpa_cli --pidfile "${pidfile}"
		${report} && eend "$?"
	fi

	# Now shutdown wpa_supplicant
	pidfile="/var/run/wpa_supplicant-${iface}.pid"
	if [[ -f ${pidfile} ]] ; then
		${report} && ebegin "Stopping wpa_supplicant on ${iface}"
		start-stop-daemon --stop --exec /sbin/wpa_supplicant \
			--pidfile "${pidfile}"
		${report} && eend "$?"
	fi

	# If wpa_supplicant exits uncleanly, we need to remove the stale dir
	[[ -S "/var/run/wpa_supplicant/${iface}" ]] \
		&& rm -f "/var/run/wpa_supplicant/${iface}"
}

# bool wpa_supplicant_associate(char *interface)
#
# Returns 0 if wpa_supplicant associates and authenticates to an AP
# otherwise, 1
wpa_supplicant_associate() {
	local iface="$1" ifvar=$(bash_variable "$1") timeout=
	timeout="associate_timeout_${ifvar}"
	[[ -z ${!timeout} ]] && timeout="wpa_timeout_${ifvar}"
	timeout="${!timeout:--1}"

	[[ -z ${actfile} && ${timeout} -lt 0 ]] && timeout="60"

	if [[ ${timeout} == "0" ]] ; then
		ewarn "WARNING: infinite timeout set for association on ${iface}"
	elif [[ ${timeout} -lt 0 ]] ; then
		einfo "Backgrounding ..."
		exit 0
	fi

	local i=0
	while true ; do
		if [[ -n ${actfile} ]] ; then
			service_started "net.${iface}" && return 0
		else
			if ! wpa_cli -i"${iface}" status &>/dev/null ; then
				eend 1 "wpa_supplicant has exited unexpectedly"
				return 1
			fi
			wpa_supplicant_associated "${iface}" && return 0
		fi
		sleep 1
		[[ ${timeout} == "0" ]] && continue
		(( i++ ))
		[[ ${i} == "${timeout}" || ${i} -gt "${timeout}" ]] && break
	done

	# Spit out an appropriate error
	if [[ -n ${actfile} ]] ; then
		eend 1 "Failed to configure ${iface} in the background"
	else
		
		eend 1 "Timed out"
	fi

	# exit without error with wpa_supplicant-0.4.x as we may get kickstarted
	# when an AP comes in range
	[[ -n ${actfile} ]] && exit 0

	# Kill wpa_supplicant for 0.3.x
	wpa_supplicant_kill "${iface}"
	return 1
}

# bool wpa_supplicant_pre_start(char *interface)
#
# Start wpa_supplicant on an interface and wait for association
# Returns 0 (true) when successful, non-zero otherwise
wpa_supplicant_pre_start() {
	local iface="$1" opts= timeout= actfile= cfgfile=

	# We don't configure wireless if we're being called from
	# the background unless we're not currently running
	if ${IN_BACKGROUND} ; then
		if service_started_daemon "net.${iface}" /sbin/wpa_supplicant ; then
			if wpa_supplicant_exists "${iface}" ; then
				ESSID=$(wpa_supplicant_get_essid "${iface}")
				ESSIDVAR=$(bash_variable "${ESSID}")
				save_options "ESSID" "${ESSID}"
				metric=2000
			fi
			return 0
		fi
	fi

	save_options "ESSID" ""

	local ifvar=$(bash_variable "${iface}")
	opts="wpa_supplicant_${ifvar}"
	opts=" ${!opts} "
	[[ ${opts} != *" -D"* ]] \
		&& vewarn "wpa_supplicant_${ifvar} does not define a driver"
	
	# We only work on wirelesss interfaces unless a driver for wired
	# has been defined
	if [[ ${opts} != *" -Dwired "* && ${opts} != *" -D wired "* ]] ; then
		if ! wpa_supplicant_exists "${iface}" ; then
			veinfo "wpa_supplicant only works on wireless interfaces"
			veinfo "unless the -D wired option is specified"
			return 0
		fi
	fi

	# If wireless-tools is installed, try and apply our user config
	# This is needed for some drivers - such as hostap because they start
	# the card in Master mode which causes problems with wpa_supplicant.
	if is_function iwconfig_defaults ; then
		if wpa_supplicant_exists "${iface}" ; then
			iwconfig_defaults "${iface}"
			iwconfig_user_config "${iface}"
		fi
	fi	

	# Check for rf_kill - only ipw supports this at present, but other
	# cards may in the future
	if [[ -e "/sys/class/net/${iface}/device/rf_kill" ]] ; then
		if [[ $( < "/sys/class/net/${iface}/device/rf_kill" ) != 0 ]] ; then
			eerror "Wireless radio has been killed for interface ${iface}"
			return 1
		fi
	fi
	
	ebegin "Starting wpa_supplicant on ${iface}"

	cfgfile="${opts##* -c}"
	if [[ -n ${cfgfile} && ${cfgfile} != "${opts}" ]] ; then
		[[ ${cfgfile:0:1} == " " ]] && cfgfile="${cfgfile# *}"
		cfgfile="${cfgfile%% *}"
	else
		# Support new and old style locations
		cfgfile="/etc/wpa_supplicant/wpa_supplicant-${iface}.conf"
		[[ ! -e ${cfgfile} ]] \
			&& cfgfile="/etc/wpa_supplicant/wpa_supplicant.conf"
		[[ ! -e ${cfgfile} ]] \
			&& cfgfile="/etc/wpa_supplicant.conf"
		opts="${opts} -c${cfgfile}"
	fi

	if [[ ! -f ${cfgfile} ]] ; then
		eend 1 "configuration file ${cfgfile} not found!"
		return 1
	fi

	# Work out where the ctrl_interface dir is if it's not specified
	local ctrl_dir=$(sed -n -e 's/[ \t]*#.*//g;s/[ \t]*$//g;s/^ctrl_interface=//p' "${cfgfile}")
	if [[ -z ${ctrl_dir} ]] ; then
		ctrl_dir="${opts##* -C}"
		if [[ -n ${ctrl_dir} && ${ctrl_dir} != "${opts}" ]] ; then
			[[ ${ctrl_dir:0:1} == " " ]] && ctrl_dir="${ctrl_dir# *}"
			ctrl_dir="${ctrl_dir%% *}"
		else
			ctrl_dir="/var/run/wpa_supplicant"
			opts="${opts} -C${ctrl_dir}"
		fi
	fi
	save_options ctrl_dir "${ctrl_dir}"

	# Some drivers require the interface to be up
	interface_up "${iface}"

	# wpa_supplicant 0.4.0 and greater supports wpa_cli actions
	# This is very handy as if and when different association mechanisms are
	# introduced to wpa_supplicant we don't have to recode for them as
	# wpa_cli is now responsible for informing us of success/failure.
	# The downside of this is that we don't see the interface being configured
	# for DHCP/static.
	actfile="/etc/wpa_supplicant/wpa_cli.sh"
	# Support old file location
	[[ ! -x ${actfile} ]] && actfile="/sbin/wpa_cli.action"
	[[ ! -x ${actfile} ]] && unset actfile
	[[ -n ${actfile} ]] && opts="${opts} -W"

	eval start-stop-daemon --start --exec /sbin/wpa_supplicant \
		--pidfile "/var/run/wpa_supplicant-${iface}.pid" \
		-- "${opts}" -B -i"${iface}" \
		-P"/var/run/wpa_supplicant-${iface}.pid"
	eend "$?" || return 1

	# Starting wpa_supplication-0.4.0, we can get wpa_cli to
	# start/stop our scripts from wpa_supplicant messages
	if [[ -n ${actfile} ]] ; then
		mark_service_inactive "net.${iface}"
		ebegin "Starting wpa_cli on ${iface}"
		start-stop-daemon --start --exec /bin/wpa_cli \
			--pidfile "/var/run/wpa_cli-${iface}.pid" \
			-- -a"${actfile}" -p"${ctrl_dir}" -i"${iface}" \
			-P"/var/run/wpa_cli-${iface}.pid" -B
		eend "$?" || return 1
	fi

	eindent
	veinfo "Waiting for association"
	eend 0

	wpa_supplicant_associate "${iface}" || return 1

	# Only report wireless info for wireless interfaces
	if wpa_supplicant_exists "${iface}" ; then
		# Set ESSID for essidnet and report
		ESSID=$(wpa_supplicant_get_essid "${iface}" )
		ESSIDVAR=$(bash_variable "${ESSID}")
		save_options "ESSID" "${ESSID}"

		local -a status=()
		eval status=( $(wpa_cli -i"${iface}" status | sed -n -e 's/^\(bssid\|pairwise_cipher\|key_mgmt\)=\([^=]\+\).*/\"\U\2\"/p' | tr '[:lower:]' '[:upper:]') )
		einfo "${iface} connected to \"${ESSID//\\\\/\\\\}\" at ${status[0]}"

		if [[ ${status[2]} == "NONE" ]] ; then
			if [[ ${status[1]} == "NONE" ]] ; then
				ewarn "not using any encryption"
			else
				veinfo "using ${status[1]}"
			fi
		else
			veinfo "using ${status[2]}/${status[1]}"
		fi
		eoutdent
	else
		einfo "${iface} connected"
	fi

	if [[ -n ${actfile} ]] ; then
		local addr=$(interface_get_address "${iface}")
		einfo "${iface} configured with address ${addr}"
		exit 0 
	fi

	metric=2000
	return 0
}

# bool wpa_supplicant_post_stop(char *iface)
#
# Stops wpa_supplicant on an interface
# Returns 0 (true) when successful, non-zero otherwise
wpa_supplicant_post_stop() {
	if ${IN_BACKGROUND} ; then
		# Only stop wpa_supplicant if it's not the controlling daemon
		! service_started_daemon "net.$1" /sbin/wpa_supplicant 0
	fi
	[[ $? == 0 ]] && wpa_supplicant_kill "$1" true
	return 0
}

# vim: set ts=4 :
