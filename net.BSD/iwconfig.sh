# Copyright (c) 2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# BSD doesn't have iwconfig - it uses ifconfig for wireless to

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
	variables essid mode associate_timeout preferred_aps blacklist_aps
}

# bool iwconfig_check_installed(void)
#
# Returns 1 if wireless-tools is installed, otherwise 0
iwconfig_check_installed() {
	# BSD's iwconfig is really via ifconfig, so we're always installed
	return 0
}

# bool iwconfig_exists(char *interface)
#
# Checks to see if wireless extensions are enabled on the interface
iwconfig_exists() {
	[[ $(ifconfig "$1") \
	=~ $'\n'"[[:space:]]*media: IEEE 802.11 Wireless" ]] \
	&& return 0
}

# char* iwconfig_get_wep_status(char *interface)
#
# Echos a string showing whether WEP is enabled or disabled
# for the given interface
iwconfig_get_wep_status() {
	local status=$"disabled"
	local mode=$(ifconfig "$1" \
	| sed -n -e 's/^[[:space:]]*authmode \([^ ]*\) privacy ON .*/\1/p')
	if [[ -n ${mode} ]] ; then
		status=$"enabled"" - ${mode}"
	fi

	echo "("$"WEP" "${status})"
}

# char* iwconfig_get_essid(char *iface)
#
# Gets the current ESSID of the iface
iwconfig_get_essid() {
	[[ $(ifconfig "$1") =~ \
	$'\n'"[[:space:]]ssid (.*) channel [0-9]* bssid *" ]] \
	|| return 1
	echo "${BASH_REMATCH[1]}"
}

# char* iwconfig_get_ap_mac_address(char *interface)
#
# Returns the MAC address of the Access Point
# the interface is connected to
iwconfig_get_ap_mac_address() {
	[[ $(ifconfig "$1") =~ \
	$'\n'"[[:space:]]ssid (.*) channel [0-9]* bssid ([^"$'\n'"]*)" ]] \
	|| return 1
	echo "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]'

}

# void iwconfig_report(char *interface)
#
# Output how our wireless interface has been configured
iwconfig_report() {
	local iface="$1" essid= mac= m=$"connected to"

	essid=$(iwconfig_get_essid "${iface}")

	local wep_status=$(iwconfig_get_wep_status "${iface}") channel=
	if [[ $(ifconfig "${iface}") =~ $'\n'"[[:space:]]ssid (.*) channel ([0-9])*" ]] ; then
		channel=$"on channel"" ${BASH_REMATCH[2]} "
	fi

	essid="${essid//\\\\/\\\\}"
	mac=$(iwconfig_get_ap_mac_address "${iface}")
	[[ -n ${mac} ]] && mac=" "$"at"" ${mac}"

	eindent
	einfo "${iface} ${m} \"${essid}\"${mac}"
	einfo "${channel}${wep_status}"
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
	echo "${!key:--}"
}

# void iwconfig_user_config(char *iface, char *ifvar)
#
# Applies the user configuration to the interface
iwconfig_user_config() {
	local iface="$1" conf= aconf= ifvar="$2"
	[[ -z ${ifvar} ]] && ifvar=$(bash_variable "$1")

	# Apply the user configuration
	conf="ifconfig_${ifvar}"
	if [[ -n ${!conf} ]]; then
		aconf=( "${!conf}" )
		for conf in "${aconf[@]}" ; do
			if ! ifconfig "${iface}" ${conf} ; then
				ewarn "${iface}" $"does not support the following configuration commands"
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
		eerror "${iface}" $"requires an ESSID to be set to operate in" "${mode}" $"mode"
		eerror $"adjust the" "essid_${iface}" $"setting in /etc/conf.d/wireless"
		return 1
	fi
	dessid="${ESSID//\\\\/\\\\}"
	ESSIDVAR=$(bash_variable "${ESSID}")
	key=$(iwconfig_get_wep_key)

	# Now set the key
	if ! ifconfig "${iface}" wepkey ${key} ; then
		if [[ ${key} != "-" ]]; then
			ewarn "${iface}" $"does not support setting keys"
			ewarn $"or the parameter" "\"mac_key_${ESSIDVAR}\"" $"or" "\"key_${ESSIDVAR}\"" $"is incorrect"
		fi
	fi

	# Then set the ESSID
	if ! ifconfig "${iface}" ssid "${ESSID}" ; then
		eerror "${iface}" $"does not support setting SSID to" "\"${dessid}\""
		return 1
	fi

	channel="channel_${ifvar}"
	# We default the channel to 3
	if ! ifconfig "${iface}" channel "${!channel:-3}" ; then
		ewarn "${iface}" $"does not support setting the channel to" "\"${!channel:-3}\""
		return 1
	fi
	
	# Finally apply the user Config
	iwconfig_user_config "${iface}" "${ESSIDVAR}"
	
	iwconfig_report "${iface}"

	return 0
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
		&& vewarn $"WARNING: infinite timeout set for association on" "${iface}"

	while true; do
		ifconfig_has_carrier "${iface}" && return 0
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
	local iface="$1" mac="$2" channel="$3" caps="$4"
	local dessid="${ESSID//\\\\/\\\\}" key= w=$"(WEP Disabled)"
	local mode=$"managed"
	
	ESSIDVAR=$(bash_variable "${ESSID}")
	key=$(iwconfig_get_wep_key "${mac}")
	if [[ ${caps} == [EI]P* && ${key} == "-" ]]; then
		ewarn $"WEP key is not set for" "\"${dessid}\"" $"- not connecting"
		return 1
	fi
	if [[ ${caps} != [EI]P* && ${key} != "-" ]]; then
		key="-"
		ewarn "\"${dessid}\"" $"is not WEP enabled - ignoring setting"
	fi

	if [[ ${key} == "-" ]] ; then
		ifconfig "${iface}" wepmode off
	else
		ifconfig "${iface}" wepmode on
		ifconfig "${iface}" deftxkey 1
		w=$(iwconfig_get_wep_status "${iface}")
	fi
	if ! ifconfig "${iface}" ${prefix} wepkey ${key} ; then
		if [[ ${key} != "-" ]]; then
			ewarn "${iface}" $"does not support setting keys"
			ewarn $"or the parameter" "\"mac_key_${ESSIDVAR}\"" $"or" "\"key_${ESSIDVAR}\"" $"is incorrect"
			return 1
		fi
	fi

	if ! ifconfig "${iface}" ssid "${ESSID}" ; then
		ewarn "${iface}" $"does not support setting ESSID to" "\"${dessid}\""
	fi

	# Finally apply the user Config
	iwconfig_user_config "${iface}" "${ESSIDVAR}"

	ebegin $"Connecting to" "\"${dessid}\""

	if is_function preassociate ; then
		veinfo $"Running preassociate function"
		veindent
		( preassociate "${iface}" )
		e="$?"
		veoutdent
		if [[ ${e} != 0 ]]; then
			veend 1 "preassociate \"${dessid}\" on ${iface} failed"
			return 1
		fi
	fi

	if ! iwconfig_wait_for_association "${iface}" ; then
		eend 1
		return 1
	fi
	eend 0

	iwconfig_report "${iface}"

	if is_function postassociate ; then
		veinfo $"Running postassociate function"
		veindent
		( postassociate "${iface}" )
		veoutdent
	fi

	return 0
}

# bool iwconfig_scan(char *iface)
#
# Fills 3 arrays with information from a wireless scan
iwconfig_scan() {
	local iface="$1" ifvar=$(bash_variable "$1")

	einfo $"Scanning for access points"

	local first=true i=0 j= k= x=
	local -a mac=() essid=() qual=() chan=() caps=()

	while read line ; do
		if ${first} ; then
			first=false
			continue
		fi

		set -- ${line}

		while [[ $1 != *:*:*:*:*:* ]] ; do
			essid[i]="$1"
			shift
		done
		mac[i]=$(echo "$1" | tr '[:lower:]' '[:upper:]')
		chan[i]="$2"
		qual[i]="${4%:*}"
		shift ; shift ; shift ; shift ; shift
		caps[i]="$*"
		((i++))
	done < <(ifconfig "${iface}" up scan)

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
				unset chan[y]
				unset caps[y]
			fi
		done
	done
	mac=( "${mac[@]}" )
	qual=( "${qual[@]}" )
	essid=( "${essid[@]}" )
	chan=( "${chan[@]}" )
	caps=( "${caps[@]}" )

	for (( i=0; i<${#mac[@]}; i++ )); do
		# Don't like ad-hoc nodes by default
		[[ ${caps[i]} == "I"* ]] && (( qual[i]-=10000 ))
		sortline="${sortline}${qual[i]} ${i}\n"
	done
	sortline=( $(echo -e "${sortline}" | sort -nr) )

	for (( i=0; i<${#mac[@]}; i++ )); do
		(( x=(i * 2) + 1 ))
		mac_APs[i]="${mac[${sortline[x]}]}"
		essid_APs[i]="${essid[${sortline[x]}]}"
		chan_APs[i]="${chan[${sortline[x]}]}"
		caps_APs[i]="${caps[${sortline[x]}]}"
	done

	return 0
}

# void iwconfig_scan_report(void)
#
# Report the results of the scan and re-map any ESSIDs if they
# have been configured for the MAC address found
iwconfig_scan_report() {
	local i= k= m= remove= d=
	local -a u=()

	[[ -z ${mac_APs} ]] && ewarn $"no access points found"

	# We need to do the for loop like this so we can
	# dynamically remove from the array
	eindent
	for ((i=0; i<${#mac_APs[@]}; i++)); do
		if [[ ${caps_APs[i]} == I* ]] ; then
			k="(ad-hoc"
		elif [[ ${caps_APs[i]} == E* ]] ; then
			k="(managed"
		fi
		[[ ${caps_APs[i]} == [EI]P* ]] && k="${k}, encrypted"
		k="${k})"

		if [[ -z ${essid_APs[i]} ]]; then
			einfo $"Found" "${mac_APs[i]} ${k}"
			d=
		else
			d=${essid_APs[i]//\\\\/\\\\}
			einfo $"Found" "\"${d}\"" $"at" "${mac_APs[i]} ${k}"
		fi

		eindent

		m="mac_essid_${mac_APs[i]//:/}"
		if [[ -n ${!m} ]]; then
			essid_APs[i]="${!m}"
			d=${essid_APs[i]//\\\\/\\\\}
			einfo $"mapping to" "\"${d}\""
		fi

		remove=false
		# If we don't know the essid then we cannot connect to them
		# so we remove them from our array
		if [[ -z ${essid_APs[i]} ]]; then
			remove=true
		elif [[ ${caps_APs[i]} == *" WPA" ]];then
			ewarn "\"${d}\"" $"requires WPA - not connecting" 
			remove=true
		else
			for k in "${blacklist_aps[@]}"; do
				if [[ ${k} == "${essid_APs[i]}" ]]; then
					ewarn "\"${k//\\\\/\\\\}\"" $"has been blacklisted - not connecting"
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
		unset mac_APs[i]
		unset caps_APs[i]
		unset chan_APs[i]
	done

	# We need to squash our arrays so indexes work again
	essid_APs=( "${essid_APs[@]}" )
	mac_APs=( "${mac_APs[@]}" )
	caps_APs=( "${caps_APs[@]}" )
	chan_APs=( "${chan_APs[@]}" )
}

# bool iwconfig_force_preferred(char *iface)
#
# Forces the preferred_aps list to associate in order
# but only if they were not picked up by our scan
iwconfig_force_preferred() {
	local iface=$1 essid= i=

	[[ -z ${preferred_aps} ]] && return 1

	ewarn $"Trying to force preferred in case they are hidden"
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

	ewarn $"Failed to associate with any preferred access points on" "${iface}"
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
				iwconfig_associate "${iface}" "${mac_APs[i]}" \
					"${chan_APs[i]}" "${caps_APs[i]}" && return 0
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
			iwconfig_associate "${iface}" "${mac_APs[i]}" \
				"${chan_APs[i]}" "${caps_APs[i]}" && return 0
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
	#ifconfig "${iface}" txpower 100 2>/dev/null
	ifconfig "${iface}" bssid -
	ifconfig "${iface}" ssid -
	ifconfig "${iface}" authmode open
}

# void iwconfig_strip_associated(char *iface)
#
# We check to see which ifaces have associated AP's except for the iface
# given and remove those AP's from the scan list
# We also remove from the preferred list
iwconfig_strip_associated() {
	local iface="$1" e= a= j=
	local essid=$(iwconfig_get_essid "${iface}")

	for i in /dev/net/*; do
		i=${i##*/}
		[[ ${i} == ${iface} ]] && continue
		interface_is_up "${i}" || continue
		iwconfig_test_associated "${i}" || continue
		e=$(iwconfig_get_essid "${i}")
		local -a u=()
		for ((j=0; j<${#mac_APs[@]}; j++)); do
			if [[ ${essid_APs[j]} == "${e}" ]]; then
				ewarn "${e}" $"has already been associated with" "${i}"
				unset essid_APs[j]
				unset mac_APs[j]
				unset chan_APs[j]
				unset caps_APs[j]
				# We need to squash our arrays so that indexes work
				essid_APs=( "${essid_APs[@]}" )
				mac_APs=( "${mac_APs[@]}" )
				chan_APs=( "${chan_APs[@]}" )
				caps_APs=(" ${caps_APs[@]}" )
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
	local -a essid_APs=() mac_APs=() chan_APs=() caps_APs=()

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
		eerror $"Only managed, ad-hoc, master and auto modes are supported"
		return 1
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
	e=$"Couldn't"" ${e} "$"any access points on"" ${iface}"

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

	if ! iwconfig_exists "${iface}" ; then
		veinfo "${iface}" $"is not wireless"
		return 0
	fi

	iwconfig_defaults "${iface}"
	iwconfig_user_config "${iface}"
	
	# Set the base metric to be 2000
	metric=2000

	einfo $"Configuring wireless network for" "${iface}"

	if iwconfig_configure "${iface}" ; then
		save_options "ESSID" "${ESSID}"
		return 0
	fi

	eerror $"Failed to configure wireless for" "${iface}"
	iwconfig_defaults "${iface}"
	#iwconfig "${iface}" txpower 0 2>/dev/null
	unset ESSID ESSIDVAR
	return 1
}

iwconfig_post_stop() {
	${IN_BACKGROUND} && return 0
	interface_exists "${iface}" || return 0
	iwconfig_exists "${iface}" || return 0
	iwconfig_defaults "${iface}"
	#iwconfig "${iface}" txpower 0 2>/dev/null
}

# vim: set ts=4 :
