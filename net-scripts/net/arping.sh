# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void arping_depend(void)
#
# Sets up the dependancies for the module
arping_depend() {
	functions interface_exists interface_up
}

# bool arping_check_installed(void)
#
# Returns 0 if arping or arping2 is installed, otherwise 1
arping_check_installed() {
	[[ -x /sbin/arping || -x /usr/sbin/arping2 ]] && return 0
	if ${1:-false}; then
		eerror "For arping support emerge net-misc/iputils or net-analyzer/arping"
	fi
	return 1
}

# void arping_sleep(char *interface)
#
# Allows the interface to settle on the LAN - normally takes around 3 seconds
# This requires the use of a global variable, ARPING_SLEPT
arping_sleep() {
	local iface="$1"
	[[ ${ARPING_SLEPT} == "1" ]] && return

	local ifvar="$(bash_variable "${iface}")"
	local s="arping_sleep_${ifvar}"
	s="${!s}"
	if [[ -z ${s} ]] ; then
		s="${arping_sleep}"
		s="${s:-1}"
	fi
	sleep "${s}"
	ARPING_SLEPT="1"
}

# bool arping_address_exists(char *interface, char *address)
#
# Returns 0 if the address on the interface responds to an arping
# 1 if not - packets defaults to 1
# If neither arping (net-misc/iputils) or arping2 (net-analyzer/arping)
# is installed then we return 1
arping_address_exists() {
	local iface="$1" ip="${2%%/*}" mac="$3" foundmac= i= w=

	# We only handle IPv4 addresses
	[[ ${ip} != *.*.*.* ]] && return 1

	# 0.0.0.0 isn't a valid address - and some lusers have configured this
	[[ ${ip} == "0.0.0.0" || ${ip} == "0" ]] && return 1

	# We need to bring the interface up to test
	interface_exists "${iface}" || return 1 
	interface_up "${iface}"

	arping_sleep

	local ifvar="$(bash_variable "${iface}")"
	w="arping_wait_${ifvar}"
	w="${!w}"
	[[ -z ${w} ]] && w="${arping_wait:-3}"

	if [[ -x /sbin/arping ]] ; then
		foundmac="$(arping -c 2 -w "${w}" -D -f -I "${iface}" \
			"${ip}" 2>/dev/null \
			| sed -n 's/.*\[\([^]]*\)\].*/\U\1/p')"
	elif [[ -x /usr/sbin/arping2 ]] ; then
		for (( i=0; i<w; i++ )) ; do
			foundmac="$(arping2 -r -0 -c 1 -i "${iface}" \
				"${ip}" 2>/dev/null)"
			if [[ $? == "0" ]] ; then
				foundmac="$(echo "${foundmac}" \
					| tr '[:lower:]' '[:upper:]')"
				break
			fi
			foundmac=
		done
	fi
	
	[[ -z ${foundmac} ]] && return 1
	
	if [[ -n ${mac} ]] ; then
		if [[ ${mac} != "${foundmac}" ]] ; then
			vewarn "Found ${ip} but MAC ${foundmac} does not match"
			return 1
		fi
	fi

	return 0
}

# bool arping_start(char *iface)
#
# arpings a list of gateways
# If one is foung then apply it's configuration
arping_start() {
	local iface="$1" gateways x conf i
	local ifvar="$(bash_variable "${iface}")"

	einfo "Pinging gateways on ${iface} for configuration"

	gateways="gateways_${ifvar}[@]"
	if [[ -z "${!gateways}" ]] ; then
		eerror "No gateways have been defined (gateways_${ifvar}=( \"...\"))"
		return 1
	fi

	eindent
	
	for x in ${!gateways}; do
		local -a a=( ${x//,/ } )
		local ip="${a[0]}" mac="${a[1]}" extra=
		if [[ -n ${mac} ]] ; then
			mac="$(echo "${mac}" | tr '[:lower:]' '[:upper:]')"
			extra="(MAC ${mac})"
		fi

		vebegin "${ip} ${extra}"
		if arping_address_exists "${iface}" "${ip}" "${mac}" ; then
			for i in ${ip//./ } ; do
				if [[ ${#i} == "2" ]] ; then
					conf="${conf}0${i}"
				elif [[ ${#i} == "1" ]] ; then
					conf="${conf}00${i}"
				else
					conf="${conf}${i}"
				fi
			done
			[[ -n ${mac} ]] && conf="${conf}_${mac//:/}"
			
			veend 0
			eoutdent
			veinfo "Configuring ${iface} for ${ip} ${extra}"
			configure_variables "${iface}" "${conf}"

			# Call the system module as we've aleady passed it by ....
			# And it *has* to be pre_start for other things to work correctly
			system_pre_start "${iface}"
			
			t="config_${ifvar}[@]"

			# Only return if we HAVE a config that doesn't include
			# arping to avoid infinite recursion.
			if [[ " ${!t} " != *" arping "* ]] ; then
				config=( "${!t}" )
				t="fallback_config_${ifvar}[@]"
				fallback_config=( "${!t}" )
				t="fallback_route_${ifvar}[@]"
				fallback_route=( "${!t}" )
				config_counter=-1
				return 0
			fi
		fi
		veend 1
	done

	eoutdent
	return 1
}

# vim: set ts=4 :
