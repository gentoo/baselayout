# Copyright (c) 2005-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Contributed by Alin Nastac (mrness@gentoo.org)

# void pppd_depend(void)
#
# Sets up the dependancies for the module
pppd_depend() {
	after interface
	before dhcp
	provide ppp
}

# bool pppd_check_installed(void)
#
# Returns 1 if pppd is installed, otherwise 0
pppd_check_installed() {
	if [[ ! -x /usr/sbin/pppd ]] ; then
		${1:-false} && eerror $"For PPP support, emerge net-dialup/ppp"
		return 1
	fi
	return 0
}

# bool pppd_exists(char *interface)
#
# Returns 0 if the interface is ppp controlled, otherwise 1
pppd_exists() {
	[[ -e /var/run/ppp-$1.pid ]]
}

# bool pppd_start(char *iface)
#
# Start PPP on an interface by calling pppd
#
# Returns 0 (true) when successful, otherwise 1
pppd_start() {
	${IN_BACKGROUND} && return 0

	local iface="$1" ifvar=$(bash_variable "$1") opts= link= i=
	if [[ ${iface%%[0-9]*} != "ppp" ]] ; then
		eerror $"PPP can only be invoked from net.ppp[0-9]"
		return 1
	fi

	local unit="${iface#ppp}"
	if [[ -z ${unit} ]] ; then
		eerror $"PPP requires a unit - use net.ppp[0-9] instead of net.ppp"
		return 1
	fi

	# PPP requires a link to communicate over - normally a serial port
	# PPPoE communicates over Ethernet
	# PPPoA communicates over ATM
	# In all cases, the link needs to be available before we start PPP
	link="link_${ifvar}"
	if [[ -z ${!link} ]] ; then
		eerror "${link}" $"has not been set in /etc/conf.d/net"
		return 1
	fi

	if [[ ${!link} == "/"* && ! -e ${!link} ]] ; then
		eerror "${link}" $"does not exist"
		eerror $"Please verify hardware or kernel module (driver)"
		return 1
	fi

	# Load any commandline options
	opts="pppd_${ifvar}[@]"
	opts="${!opts}"

	# We don't work with these options set by the user
	for i in unit nodetach linkname ; do
		if [[ " ${opts} " == *" ${i} "* ]] ; then
			eerror $"The option" "\"${i}\"" $"is not allowed in" "pppd_${ifvar}"
			return 1
		fi
	done

	# Might be set in conf.d/net
	local username= password=
	username="username_${ifvar}"
	password="password_${ifvar}"
	if [[ -n ${!username} ]] \
	&& [[ -n ${!password} || -z ${!password-x} ]] ; then
		local fd=3
		# fd 3 maybe in use, so find another one
		while [[ -e /proc/$$/fd/${fd} ]] ; do
			((fd++))
			# Don't use fd 5
			[[ ${fd} == 5 ]] && ((fd++))
		done

		password="${!password//\\/\\\\}"
		password="${password//\"/\\\"}"
		opts="${opts} plugin passwordfd.so passwordfd ${fd}"
		eval exec "${fd}< <(echo -e -n \"${password}\")"
	fi
	
	# Check for mtu/mru
	local mtu="mtu_${ifvar}"
	if [[ -n ${!mtu} ]] ; then
		[[ " ${opts} " != *" mtu "* ]] && opts="${opts} mtu ${!mtu}"
		[[ " ${opts} " != *" mru "* ]] && opts="${opts} mru ${!mtu}"
	fi

	# Set linkname because we need /var/run/ppp-${linkname}.pid
	# This pidfile has the advantage of being there, even if ${iface} interface was never started
	opts="linkname ${iface} ${opts}"

	# Setup auth info
	[[ -n ${!username} ]] && opts="user '"${!username}"' ${opts}"
	opts="remotename ${iface} ${opts}"

	# Load a custom interface configuration file if it exists
	[[ -f "/etc/ppp/options.${iface}" ]] \
		&& opts="${opts} file /etc/ppp/options.${iface}"

	# Set unit
	opts="unit ${unit} ${opts}"

	# Default maxfail to 0 unless specified
	[[ " ${opts} " != *" maxfail "* ]] && opts="${opts} maxfail 0"

	# Append persist
	[[ " ${opts} " != *" persist "* ]] && opts="${opts} persist"
	
	# Setup connect script
	local chat="chat_${ifvar}[@]"
	if [[ -n "${!chat}" ]] ; then
		local chatopts="/usr/sbin/chat -e -E -v"
		local -a phone_number="phone_number_${ifvar}[@]"
		phone_number=( "${!phone_number}" )
		if [[ ${#phone_number[@]} -ge 1 ]] ; then
			chatopts="${chatopts} -T '${phone_number[0]}'"
			if [[ ${#phone_number[@]} -ge 2 ]] ; then
				chatopts="${chatopts} -U '${phone_number[1]}'"
			fi
		fi
		opts="${opts} connect $(requote "${chatopts} $(requote "${!chat}")")" # "
	fi

	# Add plugins
	local plugins="plugins_${ifvar}[@]"
	for i in "${!plugins}" ; do
		local -a plugin=( ${i} )
		# Bound to be some users who do this
		[[ ${plugin[0]} == "passwordfd" ]] && continue	# Disable
		[[ ${plugin[0]} == "pppoe" ]] && plugin[0]="rp-pppoe"
		[[ ${plugin[0]} == "pppoa" ]] && plugin[0]="pppoatm"
		[[ ${plugin[0]} == "capi" ]] && plugin[0]="capiplugin"

		if [[ ${plugin[0]} == "rp-pppoe" || ( ${plugin[0]} == "pppoatm" && ${!link} != '/dev/null' ) ]] ; then
			opts="${opts} connect true plugin ${plugin[0]}.so ${plugin[@]:1} ${!link}"
		else
			opts="${opts} plugin ${plugin[0]}.so ${plugin[@]:1}"
		fi
	done

	#Specialized stuff. Insert here actions particular to connection type (pppoe,pppoa,capi)
	local insert_link_in_opts=1
	if [[ " ${opts} " == *" plugin rp-pppoe.so "* ]] ; then
		if [[ ! -e /proc/net/pppoe ]] ; then
			# Load the PPPoE kernel module
			if ! modprobe pppoe ; then
				eerror $"kernel does not support PPPoE"
				return 1
			fi
		fi

		# Ensure that the link exists and is up
		interface_exists "${!link}" true || return 1
		interface_up "${!link}"

		insert_link_in_opts=0
	fi

	if [[ " ${opts} " == *" plugin pppoatm.so "* ]] ; then
		if [[ ${!link} =~ '^[ \t]*([1-9]*[0-9]\.){1,2}[1-9]*[0-9][ \t]*$' ]] ; then
			insert_link_in_opts=0
		else
			ewarn $"WARNING: An [itf.]vpi.vci ATM address was expected in" "${link}"
		fi

		if [[ ! -d /proc/net/atm ]] ; then
			# Load the PPPoA kernel module
			if ! modprobe pppoatm ; then
				eerror $"kernel does not support PPPoATM"
				return 1
			fi
		fi
	fi
	[[ ${insert_link_in_opts} -eq 0 ]] || opts="${!link} ${opts}"

	ebegin $"Running pppd"
	mark_service_inactive "net.${iface}"
	eval start-stop-daemon --start --exec /usr/sbin/pppd \
		--pidfile "/var/run/ppp-${iface}.pid" -- "${opts}" >/dev/null 

	if [[ $? != "0" ]] ; then
		eend $? $"Failed to start PPP"
		mark_service_starting "net.${iface}"
		return $?
	fi

	if [[ " ${opts} " == *" updetach "* ]] ; then
		local addr=$(interface_get_address "${iface}")
		einfo "${iface}" $"received address" "${addr}"
	else
		einfo $"Backgrounding ..."
	fi

	# pppd will re-call us when we bring the interface up
	exit 0
}

# bool pppd_stop(char *iface)
#
# Stop PPP link by killing the associated pppd process
#
# Returns 0 (true) if no process to kill or it terminates successfully,
# otherwise non-zero (false)
pppd_stop() {
	${IN_BACKGROUND} && return 0
	local iface="$1" pidfile="/var/run/ppp-$1.pid"

	[[ ! -s ${pidfile} ]] && return 0

	# Give pppd at least 30 seconds do die, #147490
	einfo $"Stopping pppd on" "${iface}"
	start-stop-daemon --stop --exec /usr/sbin/pppd \
		--pidfile "${pidfile}" --retry 30
	eend $?
}

# vim: set ts=4 :
