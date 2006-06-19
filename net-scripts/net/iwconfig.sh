# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)
# Many thanks to all the people in the Gentoo forums for their ideas and
# motivation for me to make this and keep on improving it

# Fix any potential localisation problems
# Note that LC_ALL trumps LC_anything_else according to locale(7)
iwconfig() {
	LC_ALL=C /sbin/iwconfig "$@"
}
iwgetid() {
	LC_ALL=C /sbin/iwgetid "$@"
}
iwlist() {
	LC_ALL=C /sbin/iwlist "$@"
}
iwpriv() {
	LC_ALL=C /sbin/iwpriv "$@"
}

# void iwconfig_depend(void)
#
# Sets up the dependancies for the module
iwconfig_depend() {
	after plug
	before interface
	provide wireless
	functions interface_up interface_down interface_exists
}

# void iwconfig_expose(void)
#
# Expose variables that can be configured
iwconfig_expose() {
	variables essid mode associate_timeout sleep_scan preferred_aps blacklist_aps
}

# bool iwconfig_check_installed(void)
#
# Returns 1 if wireless-tools is installed, otherwise 0
iwconfig_check_installed() {
	local report=${1:-false}
	[[ -x /sbin/iwconfig ]] && return 0
	${report} && eerror "For Wireless (802.11) support, emerge net-wireless/wireless-tools"
   
	if [[ ! -e /proc/net/wireless ]]; then
		installed="1"
		if ${report} ; then
			eerror "iwconfig requires wireless support"
			eerror "(CONFIG_NET_WIRELESS=y) enabled in the kernel"
		fi
	fi
	
	return 1
}

# bool iwconfig_exists(char *interface)
#
# Checks to see if wireless extensions are enabled on the interface
iwconfig_exists() {
	[[ ! -e /proc/net/wireless ]] && return 1
	grep -q "^[ \t]*$1:" /proc/net/wireless
}

# char* iwconfig_get_wep_status(char *interface)
#
# Echos a string showing whether WEP is enabled or disabled
# for the given interface
iwconfig_get_wep_status() {
	local key=$(iwconfig "$1" | grep -i -o "Encryption key:[0-9,A-F]")
	local mode= status="disabled"

	if [[ -n ${key} ]]; then
		status="enabled"
		mode=$(iwconfig "$1" | sed -n -e 's/^.*Security mode:\(.*[^ ]\).*/\1/p')
		[[ -n ${mode} ]] && mode=" - ${mode}"
	fi

	echo "(WEP ${status}${mode})"
}

# char* iwconfig_get_essid(char *iface)
#
# Gets the current ESSID of the iface
iwconfig_get_essid() {
	local i= essid=

	for (( i=0; i<5; i++ )); do
		essid=$( iwgetid --raw "$1" )
		if [[ -n ${essid} ]] ; then
			echo "${essid}"
			return 0
		fi
		sleep 1
	done

	return 1
}

# char* iwconfig_get_ap_mac_address(char *interface)
#
# Returns the MAC address of the Access Point
# the interface is connected to
iwconfig_get_ap_mac_address() {
	iwgetid --raw --ap "$1"
}

# char* iwconfig_get_mode(char *interface)
#
# Returns the wireless mode in lower case
iwconfig_get_mode() {
	iwgetid --mode "$1" | sed -n -e 's/^.*Mode:\(.*\)/\L\1/p'
}

# char* iwconfig_get_type(char *interface)
#
# Returns the type of interface - the IEEE part
iwconfig_get_type() {
	iwconfig "$1" | sed -n -e 's/^'"$1"' *\([^ ]* [^ ]*\).*/\1/p'
}

# void iwconfig_report(char *interface)
#
# Output how our wireless interface has been configured
iwconfig_report() {
	local iface="$1" essid= mac= m="connected to"

	essid=$(iwconfig_get_essid "${iface}")

	local wep_status=$(iwconfig_get_wep_status "${iface}")
	local channel=$(iwgetid --raw --channel "${iface}")
	[[ -n ${channel} ]] && channel="on channel ${channel} "

	essid="${essid//\\\\/\\\\}"
	local mode=$(iwconfig_get_mode "${iface}")
	if [[ ${mode} == "master" ]]; then
		m="configured as"
	else
		mac=$(iwconfig_get_ap_mac_address "${iface}")
		[[ -n ${mac} ]] && mac=" at ${mac}"
	fi

	eindent
	einfo "${iface} ${m} ESSID \"${essid}\"${mac}"
	einfo "in ${mode} mode ${channel}${wep_status}"
	eoutdent
}

# char* iwconfig_get_wep_key(char *mac_address)
#
# Returns the configured WEP key for the given mac address
# or the given ESSID. The mac address setting takes precendence
iwconfig_get_wep_key() {
	local mac="$1" key=
	key="mac_key_${mac//:/}"
	[[ -z ${!key} ]] && key="key_${ESSIDVAR}"
	echo "${!key:-off}"
}

# void iwconfig_user_config(char *iface, char *ifvar)
#
# Applies the user configuration to the interface
iwconfig_user_config() {
	local iface="$1" conf= aconf= ifvar="$2"
	[[ -z ${ifvar} ]] && ifvar=$(bash_variable "$1")

	# Apply the user configuration
	conf="iwconfig_${ifvar}"
	if [[ -n ${!conf} ]]; then
		aconf=( "${!conf}" )
		for conf in "${aconf[@]}" ; do
			if ! iwconfig "${iface}" ${conf} ; then
				ewarn "${iface} does not support the following configuration commands"
				ewarn "  ${conf}"
			fi
		done
	fi

	conf="iwpriv_${ifvar}[@]"
	if [[ -n ${!conf} ]]; then
		aconf=( "${!conf}" )
		for conf in "${aconf[@]}" ; do
			if ! iwpriv "${iface}" ${conf} ; then
				ewarn "${iface} does not support the following private ioctls"
				ewarn "  ${conf}"
			fi
		done
	fi
}

# bool iwconfig_setup_specific(char *iface)
#
# Sets up our wireless interface to operate in ad-hoc or master mode
iwconfig_setup_specific() {
	local iface="$1" mode="$2" channel= key= dessid=
	local ifvar=$(bash_variable "$1")

	if [[ -z ${ESSID} ]]; then
		eerror "${iface} requires an ESSID to be set to operate in ${mode} mode"
		eerror "adjust the essid_${iface} setting in /etc/conf.d/wireless"
		return 1
	fi
	dessid="${ESSID//\\\\/\\\\}"
	ESSIDVAR=$(bash_variable "${ESSID}")
	key=$(iwconfig_get_wep_key)

	# We only change the mode if it's not the same
	local cur_mode=$(iwconfig_get_mode "${iface}")
	if [[ ${cur_mode} != "${mode}" ]]; then
		if ! iwconfig "${iface}" mode "${mode}" ; then
			eerror "${iface} does not support setting the mode to \"${mode}\""
			return 1
		fi
	fi

	channel="channel_${ifvar}"
	# We default the channel to 3
	channel="${!channel:-3}"
	if ! iwconfig "${iface}" channel "${channel}" ; then
		ewarn "${iface} does not support setting the channel to \"${channel}\""
		return 1
	fi

	# Now set the key
	if ! iwconfig "${iface}" key ${key} ; then
		if [[ ${key} != "off" ]]; then
			ewarn "${iface} does not support setting keys"
			ewarn "or the parameter \"mac_key_${ESSIDVAR}\" or \"key_${ESSIDVAR}\" is incorrect"
		fi
	fi

	# Then set the ESSID
	if ! iwconfig "${iface}" essid "${ESSID}" ; then
		eerror "${iface} does not support setting ESSID to \"${dessid}\""
		return 1
	fi

	# Finally apply the user Config
	iwconfig_user_config "${iface}" "${ESSIDVAR}"
	
	iwconfig_report "${iface}"

	return 0
}

# bool iwconfig_associate_mac(char *iface)
#
# Returns true if the AP MAC address is valid or not
iwconfig_associate_mac() {
	# Checks if a MAC address has been assigned
	local mac=$(iwconfig_get_ap_mac_address "$1") i=
	local -a invalid_macs=(
		"00:00:00:00:00:00"
		"44:44:44:44:44:44"
		"FF:00:00:00:00:00" 
		"FF:FF:FF:FF:FF:FF"
	)

	[[ -z ${mac} ]] && return 1
	for i in "${invalid_macs[@]}"; do
		[[ ${mac} == "${i}" ]] && return 1
	done
	return 0
}

# bool iwconfig_associate_quality(char *iface)
#
# Returns true if the link quality is not 0 or 0.
iwconfig_associate_quality() {
	local quality=$( \
		sed -n -e 's/^.*'"$1"': *[0-9]* *\([0-9]*\).*/\1/p' \
		/proc/net/wireless
	)
	[[ ${quality} != "0" ]]
	return "$?"
}

# bool iwconfig_test_associated(char *iface)
#
# Returns true if the interface has associated with an Access Point
iwconfig_test_associated() {
	local iface="$1" ttype= ifvar=$(bash_variable "$1") x=
	# Some drivers don't set MAC to a bogus value when assocation is lost/fails
	# whereas they do set link quality to 0

	x="associate_test_${ifvar}"
	ttype=$(echo "${!x:-mac}" | tr '[:upper:]' '[:lower:]')
	if [[ ${ttype} != "mac" && ${ttype} != "quality" && ${ttype} != "all" ]]; then
		ewarn "  associate_test_${iface} is not set to mac, quality or all"
		ewarn "  defaulting to \"mac\""
		test="mac"
	fi

	case "${ttype}" in
		mac) iwconfig_associate_mac "${iface}" && return 0 ;;
		quality) iwconfig_associate_quality "${iface}" && return 0 ;;
		all) iwconfig_associate_mac "${iface}" \
			&& iwconfig_associate_quality "${iface}" && return 0 ;;
	esac

	return 1
}

# bool iwconfig_wait_for_association(char *iface)
#
# Waits for a configured ammount of time until
# we are assocaited with an Access Point
iwconfig_wait_for_association() {
	local iface="$1" i=0 timeout= ifvar=$(bash_variable "$1")
	timeout="associate_timeout_${ifvar}"
	[[ -z ${!timeout} ]] && timeout="sleep_associate_${ifvar}"
	timeout="${!timeout:-10}"

	[[ ${timeout} == "0" ]] \
		&& vewarn "WARNING: infinite timeout set for association on ${iface}"

	while true; do
		iwconfig_test_associated "${iface}" && return 0
		sleep 1
		[[ ${timeout} == "0" ]] && continue
		(( i++ ))
		[[ ${i} == "${timeout}" || ${i} -gt ${timeout} ]] && break
	done
	return 1
}

# bool iwconfig_associate(char *interface, char *mac_address, char *wep_required)
#
# Tries to associate the interface with an Access Point
# If we scanned the Access Point we know if we need WEP to associate or not
# and if we have a WEP key for the ESSID or not
# so we can fail gracefully without even trying to connect
iwconfig_associate() {
	local iface="$1" mode="${2:-managed}"
	local mac="$3" wep_required="$4" w="(WEP Disabled)"
	local dessid="${ESSID//\\\\/\\\\}" key=

	if ! iwconfig "${iface}" mode "${mode}" ; then
		eerror "Unable to change mode to ${mode}"
		return 1
	fi

	if [[ ${ESSID} == "any" ]]; then
		iwconfig "${iface}" ap any 2>/dev/null
		dessid="any"
		unset ESSIDVAR
	else
		ESSIDVAR=$(bash_variable "${ESSID}")
		key=$(iwconfig_get_wep_key "${mac}")
		if [[ ${wep_required} == "on" && ${key} == "off" ]]; then
			ewarn "WEP key is not set for \"${dessid}\" - not connecting"
			return 1
		fi
		if [[ ${wep_required} == "off" && ${key} != "off" ]]; then
			key="off"
			ewarn "\"${dessid}\" is not WEP enabled - ignoring setting"
		fi

		if ! iwconfig "${iface}" key ${key} ; then
			if [[ ${key} != "off" ]]; then
				ewarn "${iface} does not support setting keys"
				ewarn "or the parameter \"mac_key_${ESSIDVAR}\" or \"key_${ESSIDVAR}\" is incorrect"
				return 1
			fi
		fi
		[[ ${key} != "off" ]] && w=$(iwconfig_get_wep_status "${iface}")
	fi

	if ! iwconfig "${iface}" essid "${ESSID}" ; then
		if [[ ${ESSID} != "any" ]]; then
			ewarn "${iface} does not support setting ESSID to \"${dessid}\""
		fi
	fi

	# Finally apply the user Config
	iwconfig_user_config "${iface}" "${ESSIDVAR}"

	vebegin "Connecting to \"${dessid}\" in ${mode} mode ${w}"

	if [[ ${ESSID} != "any" ]] && is_function preassociate ; then
		veinfo "Running preassociate function"
		eindent
		( preassociate "${iface}" )
		e="$?"
		eoutdent
		if [[ ${e} != 0 ]]; then
			veend 1 "preassociate \"${dessid}\" on ${iface} failed"
			return 1
		fi
	fi

	if ! iwconfig_wait_for_association "${iface}" ; then
		veend 1
		return 1
	fi
	veend 0

	if [[ ${ESSID} == "any" ]]; then
		ESSID=$(iwconfig_get_essid "${iface}")
		iwconfig_associate "${iface}"
		return $?
	fi

	iwconfig_report "${iface}"

	if is_function postassociate ; then
		veinfo "Running postassociate function"
		eindent
		( postassociate "${iface}" )
		eoutdent
	fi

	return 0
}

# bool iwconfig_scan(char *iface)
#
# Fills 3 arrays with information from a wireless scan
iwconfig_scan() {
	local iface="$1" mode= x= ifvar=$(bash_variable "$1")

	# First, we may need to change mode to scan in
	x="scan_mode_${ifvar}"
	mode=$(echo "${!x}" | tr '[:upper:]' '[:lower:]')
	if [[ -n ${mode} ]]; then
		if ! iwconfig "${iface}" mode "${mode}" ; then
			ewarn "${iface} does not support setting the mode to \"${mode}\""
		fi
	fi

	# Next we set any private driver ioctls needed
	x="iwpriv_scan_pre_${ifvar}"
	if [[ -n ${!x} ]]; then
		if ! eval iwpriv "${iface}" "${!x}" ; then
			ewarn "${iface} does not support the following private ioctls" \
			ewarn "  ${!x}"
		fi
	fi

	# Set the essid to any. This is required for scanning
	iwconfig "${iface}" essid any
	
	veinfo "Scanning for access points"

	# Sleep if required
	x="sleep_scan_${ifvar}"
	[[ -z ${!x} || ${!x} -gt 0 ]] && sleep "${!x:-1}"

	local error=true i=-1 line=
	local -a mac=() essid=() enc=() qual=() mode=()

	while read line; do
		error=false
		case "${line}" in
			*Address:*)
				(( i++ ))
				mac[i]=$(echo "${line#*: }" | tr '[:lower:]' '[:upper:]')
				;;
			*ESSID:*)
				essid[i]="${line#*\"}"
				essid[i]="${essid[i]%*\"}"
				;;
			*Mode:*)
				mode[i]=$(echo "${line#*:}" | tr '[:upper:]' '[:lower:]')
				[[ ${mode[i]} == "master" ]] && mode[i]="managed"
				;;
			*'Encryption key:'*)
				enc[i]="${line#*:}"
				;;
			*Quality*)
				qual[i]="${line#*:}"
				qual[i]="${qual[i]%/*}"
				qual[i]="${qual[i]//[![:digit:]]/}"
				qual[i]="${qual[i]:-0}"
				;;
		esac
	done < <(iwlist "${iface}" scan 2>/dev/null)

	if ${error}; then
		ewarn "${iface} does not support scanning"
		x="adhoc_essid_${ifvar}"
		[[ -n ${!x} ]] && return 0
		if [[ -n ${preferred_aps} ]]; then
			[[ ${associate_order} == "forcepreferred" \
			|| ${associate_order} == "forcepreferredonly" ]] && return 0
		fi
		eerror "You either need to set a preferred_aps list in /etc/conf.d/wireless"
		eerror "   preferred_aps=( \"ESSID1\" \"ESSID2\" )"
		eerror "   and set associate_order_${iface}=\"forcepreferred\""
		eerror "   or set associate_order_${iface}=\"forcepreferredonly\""
		eerror "or hardcode the ESSID to \"any\" and let the driver find an Access Point"
		eerror "   essid_${iface}=\"any\""
		eerror "or configure defaulting to Ad-Hoc when Managed fails"
		eerror "   adhoc_essid_${iface}=\"WLAN\""
		eerror "or hardcode the ESSID against the interface (not recommended)"
		eerror "   essid_${iface}=\"ESSID\""
		return 1
	fi

	# We may need to unset the previous private driver ioctls
	x="iwpriv_scan_post_${ifvar}"
	if [[ -n ${!x} ]]; then
		if ! eval iwpriv "${iface}" "${!x}" ; then
			ewarn "${iface} does not support the following private ioctls" \
			ewarn "  ${!x}"
		fi
	fi

	# Change back mode if needed
	x="mode_${ifvar}"
	x=$(echo "${!x:-managed}" | tr '[:upper:]' '[:lower:]')
	[[ ${mode} != "${x}" ]] && iwconfig "${iface}" mode "${x}"

	# Strip any duplicates
	local i= j= x="${#mac[@]}" y=
	for (( i=0; i<x-1; i++ )) ; do
		[[ -z ${mac[i]} ]] && continue
		for (( j=i+1; j<x; j++)) ; do
			if [[ ${mac[i]} == "${mac[j]}" ]] ; then
				if [[ ${qual[i]} -gt ${qual[j]} ]] ; then
					y="${j}"
				else
					y="${j}"
				fi
				unset mac[y]
				unset qual[y]
				unset essid[y]
				unset mode[y]
				unset enc[y]
			fi
		done
	done
	mac=( "${mac[@]}" )
	qual=( "${qual[@]}" )
	essid=( "${essid[@]}" )
	mode=( "${mode[@]}" )
	enc=( "${enc[@]}" )

	for (( i=0; i<${#mac[@]}; i++ )); do
		# Don't like ad-hoc nodes by default
		[[ ${mode[i]} == "ad-hoc" ]] && (( qual[i]-=10000 ))
		sortline="${sortline}${qual[i]} ${i}\n"
	done

	sortline=( $( echo -e "${sortline}" | sort -nr ) )

	for (( i=0; i<${#mac[@]}; i++ )); do
		(( x=(i * 2) + 1 ))
		mac_APs[i]="${mac[${sortline[x]}]}"
		essid_APs[i]="${essid[${sortline[x]}]}"
		mode_APs[i]="${mode[${sortline[x]}]}"
		enc_APs[i]="${enc[${sortline[x]}]}"
	done

	return 0
}

# void iwconfig_scan_report(void)
#
# Report the results of the scan and re-map any ESSIDs if they
# have been configured for the MAC address found
iwconfig_scan_report() {
	local i= k= m= remove=
	local -a u=()

	[[ -z ${mac_APs} ]] && ewarn "  no access points found"

	# We need to do the for loop like this so we can
	# dynamically remove from the array
	eindent
	for ((i=0; i<${#mac_APs[@]}; i++)); do
		k="(${mode_APs[i]}"
		[[ ${enc_APs[i]} != "off" ]] && k="${k}, encrypted"
		k="${k})"

		if [[ -z ${essid_APs[i]} ]]; then
			veinfo "Found ${mac_APs[i]} ${k}"
		else
			veinfo "Found \"${essid_APs[i]//\\\\/\\\\}\" at ${mac_APs[i]} ${k}"
		fi

		eindent

		m="mac_essid_${mac_APs[i]//:/}"
		if [[ -n ${!m} ]]; then
			essid_APs[i]="${!m}"
			veinfo "mapping to \"${!m//\\\\/\\\\}\""
		fi

		remove=false
		# If we don't know the essid then we cannot connect to them
		# so we remove them from our array
		if [[ -z ${essid_APs[i]} ]]; then
			remove=true
		else
			for k in "${blacklist_aps[@]}"; do
				if [[ ${k} == "${essid_APs[i]}" ]]; then
					vewarn "\"${k//\\\\/\\\\}\" has been blacklisted - not connecting"
					remove=true
					break
				fi
			done
		fi

		eoutdent

		${remove} && u=( "${u[@]}" "${i}" )
	done

	eoutdent

	# Now we remove any duplicates
	for ((i=0; i < ${#essid_APs[@]} - 1; i++)); do
		for ((j=${i} + 1; j <${#essid_APs[@]}; j++)); do
			[[ ${essid_APs[i]} == "${essid_APs[j]}" ]] && u=( "${u[@]}" "${j}" )
		done
	done

	for i in ${u[@]}; do
		unset essid_APs[i]
		unset mode_APs[i]
		unset mac_APs[i]
		unset enc_APs[i]
	done

	# We need to squash our arrays so indexes work again
	essid_APs=( "${essid_APs[@]}" )
	mode_APs=( "${mode_APs[@]}" )
	mac_APs=( "${mac_APs[@]}" )
	enc_APs=( "${enc_APs[@]}" )
}

# bool iwconfig_force_preferred(char *iface)
#
# Forces the preferred_aps list to associate in order
# but only if they were not picked up by our scan
iwconfig_force_preferred() {
	local iface=$1 essid= i=

	[[ -z ${preferred_aps} ]] && return 1

	ewarn "Trying to force preferred in case they are hidden"
	for essid in "${preferred_aps[@]}"; do
		local found_AP=false
		for ((i = 0; i < ${#mac_APs[@]}; i++)); do
			if [[ ${essid} == "${essid_APs[i]}" ]]; then
				found_AP=true
				break
			fi
		done
		if ! ${found_AP} ; then
			ESSID="${essid}"
			iwconfig_associate "${iface}" && return 0
		fi
	done

	ewarn "Failed to associate with any preferred access points on ${iface}"
	return 1
}

# bool iwconfig_connect_preferred(char *iface)
#
# Connects to preferred_aps in order if they were picked up
# by our scan
iwconfig_connect_preferred() {
	local iface="$1" essid= i=

	for essid in "${preferred_aps[@]}"; do
		for ((i=0; i<${#essid_APs[@]}; i++)); do
			if [[ ${essid} == "${essid_APs[i]}" ]]; then
				ESSID="${essid}"
				iwconfig_associate "${iface}" "${mode_APs[i]}" "${mac_APs[i]}" \
					"${enc_APs[i]}" && return 0
				break
			fi
		done
	done

	return 1
}

# bool iwconfig_connect_not_preferred(char *iface)
#
# Connects to any AP's found that are not in
# our preferred list
iwconfig_connect_not_preferred() {
	local iface=$1 i= ap= has_preferred=

	for ((i=0; i<${#mac_APs[@]}; i++)); do
		has_preferred=false
		for ap in "${preferred_aps[@]}"; do
			if [[ ${ap} == "${essid_APs[i]}" ]]; then
				has_preferred=true
				break
			fi
		done
		if ! ${has_preferred} ; then
			ESSID="${essid_APs[i]}"
			iwconfig_associate "${iface}" "${mode_APs[i]}" "${mac_APs[i]}" \
				"${enc_APs[i]}" && return 0
		fi
	done

	return 1
}

# void iwconfig_defaults(char *iface)
#
# Apply some sane defaults to the wireless interface
# incase the user already applied some changes
iwconfig_defaults() {
	local iface="$1"

	# Set some defaults
	iwconfig "${iface}" txpower auto 2>/dev/null
	iwconfig "${iface}" rate auto 2>/dev/null
	iwconfig "${iface}" rts auto 2>/dev/null
	iwconfig "${iface}" frag auto 2>/dev/null
}

# void iwconfig_strip_associated(char *iface)
#
# We check to see which ifaces have associated AP's except for the iface
# given and remove those AP's from the scan list
# We also remove from the preferred list
iwconfig_strip_associated() {
	local iface="$1" e= a= j=
	local essid=$(iwconfig_get_essid "${iface}")
	local -a ifaces=( $( iwconfig 2>/dev/null | grep -o "^\w*" ) )

	for i in "${ifaces[@]}"; do
		[[ ${i} == ${iface} ]] && continue
		interface_is_up "${i}" || continue
		iwconfig_test_associated "${i}" || continue
		e=$(iwconfig_get_essid "${i}")
		local -a u=()
		for ((j=0; j<${#mac_APs[@]}; j++)); do
			if [[ ${essid_APs[j]} == "${e}" ]]; then
				ewarn "${e} has already been associated with ${i}"
				unset essid_APs[j]
				unset mode_Aps[j]
				unset mac_APs[j]
				unset enc_APs[j]
				# We need to squash our arrays so that indexes work
				essid_APs=( "${essid_APs[@]}" )
				mode_APs=( "${mode_APs[@]}" )
				mac_APs=( "${mac_APs[@]}" )
				enc_APs=( "${enc_APs[@]}" )
				break
			fi
		done
		for ((j=0; j<${#preferred_aps[@]}; j++)); do
			if [[ ${preferred_aps[j]} == "${e}" ]]; then
				unset preferred_aps[j]
				preferred_aps=( "${preferred_aps[@]}" )
				break
			fi
		done
	done
}

# bool iwconfig_configure(char *iface)
#
# The main startup code
# First we bring the interface up, apply defaults, apply user configuration
# Then we test to see if ad-hoc mode has been requested and branch if needed
# Then we scan for access points and try to connect to them in a predetermined order
# Once we're connected we show a report and then configure any interface
# variables for the ESSID
iwconfig_configure() {
	local iface="$1" e= x= ifvar=$(bash_variable "$1")
	local -a essid_APs=() mac_APs=() mode_APs=() enc_APs=()

	ESSID="essid_${ifvar}"
	ESSID="${!ESSID}"

	# Setup ad-hoc mode?
	x="mode_${ifvar}"
	x=$(echo "${!x:-managed}" | tr '[:upper:]' '[:lower:]')
	if [[ ${x} == "ad-hoc" || ${x} == "master" ]]; then
		iwconfig_setup_specific "${iface}" "${x}"
		return $?
	fi

	if [[ ${x} != "managed" && ${x} != "auto" ]]; then
		eerror "Only managed, ad-hoc, master and auto modes are supported"
		return 1
	fi

	# We only change the mode if it's not the same as some drivers
	# only do managed and throw an error changing to managed
	local cur_mode=$(iwconfig_get_mode "${iface}")
	if [[ ${cur_mode} != "${x}" ]]; then
		if ! iwconfig "${iface}" mode "${x}" ; then
			eerror "${iface} does not support setting the mode to \"${x}\""
			return 1
		fi
	fi

	# Has an ESSID been forced?
	if [[ -n ${ESSID} ]]; then
		iwconfig_associate "${iface}" && return 0
		[[ ${ESSID} == "any" ]] && iwconfig_force_preferred "${iface}" && return 0

		ESSID="adhoc_essid_${ifvar}"
		ESSID="${!ESSID}"
		if [[ -n ${ESSID} ]]; then
			iwconfig_setup_specific "${iface}" ad-hoc
			return $?
		fi
		return 1
	fi

	# Do we have a preferred Access Point list specific to the interface?
	x="preferred_aps_${ifvar}[@]"
	[[ -n ${!x} ]] && preferred_aps=( "${!x}" )

	# Do we have a blacklist Access Point list specific to the interface?
	x="blacklist_aps_${ifvar}[@]"
	[[ -n ${!x} ]] && blacklist_aps=( "${!x}" )

	# Are we forcing preferred only?
	x="associate_order_${ifvar}"
	[[ -n ${!x} ]] && associate_order="${!x}"
	associate_order=$(echo "${associate_order:-any}" \
		| tr '[:upper:]' '[:lower:]')

	if [[ ${associate_order} == "forcepreferredonly" ]]; then
		iwconfig_force_preferred "${iface}" && return 0
	else
		iwconfig_scan "${iface}" || return 1
		iwconfig_scan_report

		# Strip AP's from the list that have already been associated with
		# other wireless cards in the system if requested
		x="unique_ap_${ifvar}"
		[[ -n ${!x} ]] && unique_ap="${!x}"
		unique_ap=$(echo "${unique_ap:-no}" | tr '[:upper:]' '[:lower:]')
		[[ ${unique_ap} != "no" ]] && iwconfig_strip_associated "${iface}"

		iwconfig_connect_preferred "${iface}" && return 0
		[[ ${associate_order} == "forcepreferred" \
			|| ${associate_order} == "forceany" ]] \
			&& iwconfig_force_preferred "${iface}" && return 0
		[[ ${associate_order} == "any" || ${associate_order} == "forceany" ]] \
			&& iwconfig_connect_not_preferred "${iface}" && return 0
	fi

	e="associate with"
	[[ -z ${mac_APs} ]] && e="find"
	[[ ${preferred_only} == "force" || ${preferred_aps} == "forceonly" ]] \
		&& e="force"
	e="Couldn't ${e} any access points on ${iface}"

	ESSID="adhoc_essid_${ifvar}"
	ESSID="${!ESSID}"
	if [[ -n ${ESSID} ]]; then
		ewarn "${e}"
		iwconfig_setup_specific "${iface}" ad-hoc
		return $?
	fi

	eerror "${e}"
	return 1
}

# bool iwconfig_pre_start(char *iface)
#
# Start entry point
# First we check if wireless extensions exist on the interface
# If they are then we configue wireless
iwconfig_pre_start() {
	local iface="$1" r=0

	# We don't configure wireless if we're being called from
	# the background
	${IN_BACKGROUND} && return 0

	save_options "ESSID" ""
	interface_exists "${iface}" || return 0

	# We need to bring the interface up, as some cards do not register
	# in /proc/wireless until they are brought up.
	interface_up "${iface}"

	if ! iwconfig_exists "${iface}" ; then
		veinfo "Wireless extensions not found for ${iface}"
		return 0
	fi

	iwconfig_defaults "${iface}"
	iwconfig_user_config "${iface}"
	
	# Set the base metric to be 2000
	metric=2000

	# Check for rf_kill - only ipw supports this at present, but other
	# cards may in the future.
	if [[ -e "/sys/class/net/${iface}/device/rf_kill" ]]; then
		if [[ $( < "/sys/class/net/${iface}/device/rf_kill" ) != 0 ]]; then
			eerror "Wireless radio has been killed for interface ${iface}"
			return 1
		fi
	fi

	einfo "Configuring wireless network for ${iface}"

	# Are we a proper IEEE device?
	# Most devices reutrn IEEE 802.11b/g - but intel cards return IEEE
	# in lower case and RA cards return RAPCI or similar
	# which really sucks :(
	# For the time being, we will test prism54 not loading firmware
	# which reports NOT READY!
	x=$(iwconfig_get_type "${iface}")
	if [[ ${x} == "NOT READY!" ]]; then
		eerror "Looks like there was a probem loading the firmware for ${iface}"
		return 1
	fi

	# Setup IFS incase parent script has modified it
	local IFS=$' '$'\n'$'\t'

	if iwconfig_configure "${iface}" ; then
		save_options "ESSID" "${ESSID}"
		return 0
	fi

	eerror "Failed to configure wireless for ${iface}"
	iwconfig_defaults "${iface}"
	iwconfig "${iface}" txpower off 2>/dev/null
	unset ESSID ESSIDVAR
	interface_down "${iface}"
	return 1
}

iwconfig_post_stop() {
	${IN_BACKGROUND} && return 0
	interface_exists "${iface}" || return 0
	iwconfig_defaults "${iface}"
	iwconfig "${iface}" txpower off 2>/dev/null
}

# vim: set ts=4 :
