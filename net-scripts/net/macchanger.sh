# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void macchanger_depend(void)
#
# Sets up the dependancies for the module
macchanger_depend() {
	before macnet
	functions interface_get_mac_address interface_set_mac_address
}

# void macchanger_expose(void)
#
# Expose variables that can be configured
macchanger_expose() {
	variables mac
}

# bool macchanger_pre_start(char *iface)
#
# Configures the MAC address for iface 
macchanger_pre_start() {
	# We don't change MAC addresses from background
	${IN_BACKGROUND} && return 0

	local iface="$1" mac opts ifvar="$(bash_variable "$1")"

	mac="mac_${ifvar}"
	[[ -z ${!mac} ]] && return 0

	interface_exists "${iface}" true || return 1

	ebegin "Changing MAC address of ${iface}"

	# The interface needs to be up for macchanger to work most of the time
	interface_down "${iface}"
	
	mac="$(echo "${!mac}" | tr '[:upper:]' '[:lower:]')"
	case "${mac}" in
		# specific mac-addr, i wish there were a shorter way to specify this 
		[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f])
			# We don't need macchanger to change to a specific mac address
			interface_set_mac_address "${iface}" "${mac}"
			eend "$?"
			if [[ $? == "0" ]] ; then
				mac="$(interface_get_mac_address "${iface}")"
				eindent
				einfo "changed to ${mac}"
				eoutdent
				return 0
			fi
			;;

		# increment MAC address, default macchanger behavior
		increment) opts="${opts}" ;;

		# randomize just the ending bytes
		random-ending) opts="${opts} -e" ;;

		# keep the same kind of physical layer (eg fibre, copper)
		random-samekind) opts="${opts} -a" ;;

		# randomize to any known vendor of any physical layer type
		random-anykind) opts="${opts} -A" ;;

		# fully random bytes
		random-full) opts="${opts} -r" ;;

		# default case is just to pass on all the options
		*) opts="${opts} ${mac}" ;;
	esac

	if [[ ! -x /sbin/macchanger ]] ; then
		eerror "For changing MAC addresses, emerge net-analyzer/macchanger"
		return 1
	fi

	mac="$( /sbin/macchanger ${opts} "${iface}" \
		| sed -n -e 's/^Faked MAC:.*\<\(..:..:..:..:..:..\)\>.*/\U\1/p' )"

	# Sometimes the interface needs to be up ....
	if [[ -z ${mac} ]] ; then
		interface_up "${iface}"
		mac="$( /sbin/macchanger ${opts} "${iface}" \
			| sed -n -e 's/^Faked MAC:.*\<\(..:..:..:..:..:..\)\>.*/\U\1/p' )"
	fi

	if [[ -z ${mac} ]] ; then
		eend 1 "Failed to set MAC address"
		return 1
	fi

	eend 0
	eindent
	einfo "changed to ${mac}"
	eoutdent

	return 0 #important
}

# vim: set ts=4 :
