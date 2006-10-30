#!/sbin/runscript
# Copyright (c) 2004-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Contributed by Roy Marples (uberlord@gentoo.org)
# Many thanks to Aron Griffis (agriffis@gentoo.org)
# for help, ideas and patches

#NB: Config is in /etc/conf.d/net

# For pcmcia users. note that pcmcia must be added to the same
# runlevel as the net.* script that needs it.
depend() {
	need localmount
	after bootmisc modules hostname
	use isapnp isdn pcmcia usb wlan

	# Load any custom depend functions for the given interface
	# For example, br0 may need eth0 and eth1
	local iface="${SVCNAME#*.}"
	[[ $(type -t "depend_${iface}") == "function" ]] && depend_${iface}

	if [[ ${iface} != "lo" && ${iface} != "lo0" ]] ; then
		provide net
		after net.lo net.lo0

		# Support new style RC_NEED and RC_USE in one net file
		local x="RC_NEED_${iface}"
		[[ -n ${!x} ]] && need ${!x}
		x="RC_USE_${iface}"
		[[ -n ${!x} ]] && use ${!x}
	else
		# Support legacy setting
		[[ ${RC_NET_STRICT_CHECKING} != "no" ]] && provide net
	fi

	return 0
}

# Define where our modules are
MODULES_DIR="${svclib}/net"

# Make some wrappers to fudge after/before/need/use depend flags.
# These are callbacks so MODULE will be set.
after() {
	eval "${MODULE}_after() { echo \"$*\"; }"
}
before() {
	eval "${MODULE}_before() { echo \"$*\"; }"
}
installed() {
	eval "${MODULE}_instlled() { echo \"$*\"; }"
}
provide() {
	eval "${MODULE}_provide() { echo \"$*\"; }"
}
variables() {
	eval "${MODULE}_variables() { echo \"$*\"; }"
}

is_loopback() {
	[[ $1 == "lo" || $1 == "lo0" ]]
}

# char* interface_device(char *iface)
#
# Gets the base device of the interface
# Can handle eth0:1 and eth0.1
# Which returns eth0 in this case
interface_device() {
	local dev="${1%%.*}"
	[[ ${dev} == "$1" ]] && dev="${1%%:*}"
	echo "${dev}"
}

# char* interface_type(char* iface)
#
# Returns the base type of the interface
# eth, ippp, etc
interface_type() {
	echo "${1%%[0-9]*}"
}

# int calculate_metric(char *interface, int base)
#
# Calculates the best metric for the interface
# We use this when we add routes so we can prefer interfaces over each other
calculate_metric() {
	local iface="$1" metric="$2"

	# Have we already got a metric?
	local m=
	if [[ -e /proc/net/route ]] ; then
		m=$(awk '$1=="'${iface}'" && $2=="00000000" { print $7 }' \
		/proc/net/route)
	else
		[[ $(ifconfig "${iface}" 2>/dev/null) =~ "metric ([^ ]*)" ]] \
			&& m="${BASH_REMATCH[1]}"
	fi
	if [[ -n ${m} ]] ; then
		echo "${m}"
		return 0
	fi

	if [[ ! -e /proc/net/route ]] ; then
		echo "${metric}"
		return 0
	fi

	local i= dest= gw= flags= ref= u= m= mtu= metrics=
	while read i dest gw flags ref u m mtu ; do
		# Ignore lo
		is_loopback "${i}" && continue
		# We work out metrics from default routes only
		[[ ${dest} != "00000000" || ${gw} == "00000000" ]] && continue
		metrics="${metrics}\n${m}"
	done < /proc/net/route

	# Now, sort our metrics
	metrics=$(echo -e "${metrics}" | sort -n)

	# Now, find the lowest we can use
	local gotbase=false
	for m in ${metrics} ; do
		[[ ${m} -lt ${metric} ]] && continue
		[[ ${m} == ${metric} ]] && ((metric++))
		[[ ${m} -gt ${metric} ]] && break
	done
	
	echo "${metric}"
}

# int netmask2cidr(char *netmask)
#
# Returns the CIDR of a given netmask
netmask2cidr() {
	local binary= i= bin=

	for i in ${1//./ }; do
		bin=""
		while [[ ${i} != "0" ]] ; do
			bin=$[${i}%2]${bin}
			(( i=i>>1 ))
		done
		binary="${binary}${bin}"
	done
	binary="${binary%%0*}"
	echo "${#binary}"
}


# bool is_function(char* name)
#
# Returns 0 if the given name is a shell function, otherwise 1
is_function() {
	[[ -z $1 ]] && return 1
	[[ $(type -t "$1") == "function" ]]
}

# void function_wrap(char* source, char* target)
#
# wraps function calls - for example function_wrap(this, that)
# maps function names this_* to that_*
function_wrap() {
	local i=

	is_function "${2}_depend" && return 1

	for i in $(typeset -f | grep -o '^'"${1}"'_[^ ]*'); do
		eval "${2}${i#${1}}() { ${i} \"\$@\"; }"
	done

	return 0
}

# char[] * expand_parameters(char *cmd)
#
# Returns an array after expanding parameters. For example
# "192.168.{1..3}.{1..3}/24 brd +"
# will return
# "192.168.1.1/24 brd +"
# "192.168.1.2/24 brd +"
# "192.168.1.3/24 brd +"
# "192.168.2.1/24 brd +"
# "192.168.2.2/24 brd +"
# "192.168.2.3/24 brd +"
# "192.168.3.1/24 brd +"
# "192.168.3.2/24 brd +"
# "192.168.3.3/24 brd +"
expand_parameters() {
	local x=$(eval echo ${@// /_})
	local -a a=( ${x} )

	a=( "${a[@]/#/\"}" )
	a=( "${a[@]/%/\"}" )
	echo "${a[*]//_/ }"
}

# void configure_variables(char *interface, char *option1, [char *option2])
#
# Maps configuration options from <variable>_<option> to <variable>_<iface>
# option2 takes precedence over option1
configure_variables() {
	local iface="$1" option1="$2" option2="$3"

	local mod= func= x= i=
	local -a ivars=() ovars1=() ovars2=()
	local ifvar=$(bash_variable "${iface}")

	for mod in ${MODULES[@]}; do
		is_function ${mod}_variables || continue
		for v in $(${mod}_variables) ; do
			x=
			[[ -n ${option2} ]] && x="${v}_${option2}[@]"
			[[ -z ${!x} ]] && x="${v}_${option1}[@]"
			[[ -n ${!x} ]] && eval "${v}_${ifvar}=( \"\${!x}\" )"
		done
	done

	return 0
}

# bool modules_load(char *iface, bool starting)
#
# Loads the defined handler and modules for the interface
# Returns 0 on success, otherwise 1
modules_load()  {
	local iface=$1 starting=${2:-true} MODULE= i= j= x=
	local ifvar=$(bash_variable "${iface}")
	local RC_INDENTATION="${RC_INDENTATION}"
	local -a provides=() wrapped=()
	# These are our preferred modules
	local -a umods=() pmods=( iproute2 dhcpcd wpa_supplicant netplugd )

	veinfo "Loading networking modules for" "${iface}"

	if ! is_loopback "${iface}" ; then
		x="modules_force_${iface}[@]"
		[[ -n ${!x} ]] && modules_force=( "${!x}" )
		if [[ -n ${modules_force} ]] ; then
			ewarn $"WARNING: You are forcing modules!"
			ewarn $"Do not complain or file bugs if things start breaking"
			report=true
		fi
	fi

	if ${starting} ; then
		x="modules_${ifvar}[@]"
		umods=( "${!x}" "${modules[@]}" )
	fi

	if [[ -z ${modules_force} ]] ; then
		MODULES=( $(dolisting "${MODULES_DIR}") )
		j="${#MODULES[@]}"
		for (( i=0; i<j; i++ )); do
			if [[ ${MODULES[i]} != *.sh ]] ; then
				unset MODULES[i]
				continue
			fi
			MODULES[i]="${MODULES[i]##*/}"
			MODULES[i]="${MODULES[i]%.sh*}"
		done

		MODULES=( $(rc-depend --deptree "${svcdir}/netdeptree" \
					--alwaysvalid -iafter ${MODULES[@]}) )
	else
		MODULES=( "${modules_force[@]}" )
	fi

	# Each of these sources load into the global namespace, so it's
	# important that module functions and variables are prefixed with
	# the module name, for example iproute2_
	j="${#MODULES[@]}"
	for ((i=0; i<j; i++)); do
		(
		u=0; report=false;
		f="${svclib}/net/${MODULES[i]}.sh"
		if [[ ! -f ${f} ]] ; then
			is_loopback "${iface}" || eerror "${f}" $"does not exist"
			exit 1
		fi
		if ! . "${f}" ; then
			eerror "${f}" $"failed a sanity check"
			exit 1
		fi

		if ! is_function "${MODULES[i]}_depend" ; then 
			eerror "${f}" $"does not support the required function" "depend"
			exit 1
		fi

		if [[ ${u} == 0 ]] ; then
			inst="${MODULES[i]}_check_installed";
			[[ " ${umods} " == *" ${MODULES[i]} "* ]] && report=true
			if is_function "${inst}" ; then
				${inst} ${report} || u=1;
			fi
			if [[ " ${umods} " == *" !${MODULES[i]} "* ]] ; then
				u=1
			else
				MODULE="${MODULES[i]}"
				${MODULES[i]}_depend
				if is_function "${MODULES[i]}_provide" && [[ -n ${umods} ]] ; then
					[[ " ${umods} " == *" !$(${MODULES[i]}_provide) "* ]] && u=1
				fi
			fi
		fi
		exit "${u}";
		)

		if [[ $? != 0 || " ${umods}" == *" !${MODULES[i]} "* ]] ; then
			unset MODULES[i]
			continue
		fi

		# We can use this module
		. "${svclib}/net/${MODULES[i]}.sh"

		# Now load our dependencies - we need to use the MODULE variable
		# here as the after/before/need functions use it
		MODULE="${MODULES[i]}"
		${MODULE}_depend

		# If no provide is given, assume module name
		if is_function "${MODULES[i]}_provide" ; then
			provides[i]=$(${MODULES[i]}_provide)
		else
			provides[i]="${MODULES[i]}"
		fi

		# expose does exactly the same thing as depend
		# However it is more "correct" as it exposes things to other modules
		# instead of depending on them ;)
		is_function "${MODULES[i]}_expose" && ${MODULES[i]}_expose
	done

	# Squash our arrays
	MODULES=( "${MODULES[@]}" )
	provides=( "${provides[@]}" )

	# Wrap our preferred modules
	umods=( "${umods[@]}" "${pmods[@]}" )
	for i in ${umods[@]} ; do
		if [[ " ${MODULES[@]} " == *" ${i} "* ]] ; then
			if is_function "${i}_provide" ; then
				j=$(${i}_provide)
				if function_wrap "${i}" "${j}" ; then
					wrapped=( "${wrapped[@]}" "${i}" )
				fi
			fi
		fi
	done
	
	# Now wrap everything else
	# If something is already provided, then remove it if we're starting
	j=${#MODULES[@]}
	for ((i=0; i<j; i++)) ; do
		if [[ ${MODULES[i]} != "${provides[i]}" \
			&& " ${wrapped[@]} " != *" ${MODULES[i]} "* ]] ; then
			if ! function_wrap "${MODULES[i]}" "${provides[i]}" ; then
				${starting} && unset MODULES[i] && unset provides[i]
			fi
		fi
	done
	MODULES=( "${MODULES[@]}" )
	provides=( "${provides[@]}" )

	# Now check we have everthing we need
	j=${#MODULES[@]}
	for (( i=0; i<j; i++ )); do
		[[ -n ${MODULES[i]} ]] || continue
		if is_function "${MODULES[i]}_instlled" ; then
			for x in $( ${MODULES[i]}_instlled ); do
				if [[ " ${MODULES[@]} " != *" ${x} "* ]] ; then
					if [[ " ${umods} " == *" ${MODULES[i]} "* ]] ; then
						eerror "${MODULES[i]}" $"needs" "${x}"
						return 1
					fi
					unset MODULES[i]
					unset provides[i]
					break
				fi
			done
		fi
	done
	MODULES=( "${MODULES[@]}" )
	provides=( "${provides[@]}" )

	veindent
	veinfo "modules: ${MODULES[@]}"
	veindent

	j=${#MODULES[@]}
	x=false
	for (( i=0; i<j; i++ )); do
		if [[ -n ${MODULES[i]} && ${MODULES[i]} != "${provides[i]}" ]] ; then
			[[ ${provides[i]} == "interface" ]] && x=true
			${starting} && veinfo "${MODULES[i]}" $"provides" "${provides[i]}"
		fi
	done
	if ! ${x} ; then
		eerror $"No loaded module provides interface"
		return 1
	fi

	veoutdent
	veoutdent
	return 0 
}

# bool iface_start(char *interface)
#
# iface_start is called from start.  It's expected to start the base
# interface (for example "eth0"), aliases (for example "eth0:1") and to start
# VLAN interfaces (for example eth0.0, eth0.1).  VLAN setup is accomplished by
# calling itself recursively.
iface_start() {
	local iface="$1" mod config_counter="-1" x config_worked=false
	local RC_INDENTATION="${RC_INDENTATION}"
	local -a config=() fallback=() fallback_route=() conf=() a=() b=()
	local ifvar=$(bash_variable "$1") i= j= metric=0

	# Bring the interface up if we exist
	interface_exists "${iface}" && interface_up "${iface}"

	# pre Start any modules with
	for mod in ${MODULES[@]}; do
		if is_function "${mod}_pre_start" ; then
			${mod}_pre_start "${iface}" || { eend 1; return 1; }
		fi
	done

	x="metric_${ifvar}"
	# If we don't have a metric then calculate one
	# Our modules will set the metric variable to a suitable base
	# in their pre starts.
	if [[ -z ${!x} ]] ; then
		eval "metric_${ifvar}=\"$(calculate_metric "${iface}" "${metric}")\""
	fi

	# We now expand the configuration parameters and pray that the
	# fallbacks expand to the same number as config or there will be
	# trouble!
	a="config_${ifvar}[@]"
	a=( "${!a}" )
	for (( i=0; i<${#a[@]}; i++ )); do 
		eval b=( $(expand_parameters "${a[i]}") )
		config=( "${config[@]}" "${b[@]}" )
	done

	a="fallback_${ifvar}[@]"
	a=( "${!a}" )
	for (( i=0; i<${#a[@]}; i++ )); do 
		eval b=( $(expand_parameters "${a[i]}") )
		fallback=( "${fallback[@]}" "${b[@]}" )
	done

	# We don't expand routes
	fallback_route="fallback_route_${ifvar}[@]"
	fallback_route=( "${!fallback_route}" )
	
	# We must support old configs
	if [[ -z ${config} ]] ; then
		interface_get_old_config "${iface}" || return 1
		if [[ -n ${config} ]] ; then
			ewarn $"You are using a deprecated configuration syntax for" "${iface}"
			ewarn $"You are advised to read /etc/conf.d/net.example and upgrade it accordingly"
		fi
	fi

	# Handle "noop" correctly
	if [[ ${config[0]} == "noop" ]] ; then
		if interface_is_up "${iface}" true ; then
			einfo $"Keeping current configuration for" "${iface}"
			eend 0
			return 0
		fi
		# Remove noop from the config var
		config=( "${config[@]:1}" )
	fi

	# Provide a default of DHCP if no configuration is set and we're auto
	# Otherwise a default of NULL
	if [[ -z ${config} ]] ; then
		ewarn $"Configuration not set for" "${iface}," $"assuming DHCP"
		if is_function "dhcp_start" ; then
			config=( "dhcp" )
		else
			eerror $"No DHCP client installed"
			return 1
		fi
	fi

	einfo $"Bringing up" "${iface}"
	eindent

	for (( config_counter=0; config_counter<${#config[@]}; config_counter++ )); do
		# Handle null and noop correctly
		if [[ ${config[config_counter]} == "null" \
			|| ${config[config_counter]} == "noop" ]] ; then
			eend 0
			config_worked=true
			continue
		fi

		if [[ ${config_counter} == 0 ]] \
		&& interface_exists "${iface}" \
		&& ! interface_has_carrier "${iface}" ; then
			ebegin "Waiting for carrier"
			local timeout=3
			while [[ ${timeout} -gt 0 ]] ; do
				((timeout--))
				sleep 1
				interface_has_carrier "${iface}" && break
			done
			if [[ ${timeout} -gt 0 ]] ; then
				eend 0 
			elif is_runlevel_start && [[ -e ${svcdir}/softscripts/devd ]] ; then
				ewend 1 "No carrier - but devd will restart us when we get one"
				mark_service_inactive "net.${iface}"
				exit 0
			else
				eend 1 "No carrier - giving up"
				return 1
			fi
		fi

		# We convert it to an array - this has the added
		# bonus of trimming spaces!
		conf=( ${config[config_counter]} )
		einfo "${conf[0]}"

		# Do we have a function for our config?
		if is_function "${conf[0]}_start" ; then
			eindent
			${conf[0]}_start "${iface}" ; x=$?
			eoutdent
			[[ ${x} == 0 ]] && config_worked=true && continue
			# We need to test to see if it's an IP address or a function
			# We do this by testing if the 1st character is a digit
		elif [[ ${conf[0]:0:1} == [[:digit:]] || ${conf[0]} == *:* ]] ; then
			x="0"
			if ! is_loopback "${iface}" ; then
				if [[ " ${MODULES[@]} " == *" arping "* ]] ; then
					if arping_address_exists "${iface}" "${conf[0]}" ; then
						eerror "${conf[0]%%/*}" $"already taken on" "${iface}"
						x="1"
					fi
				fi
			fi
			[[ ${x} == "0" ]] && interface_add_address "${iface}" ${conf[@]}; x="$?"
			eend "${x}" && config_worked=true && continue
		else
			if [[ ${conf[0]} == "dhcp" ]] ; then
				eerror $"No DHCP client installed"
			else
				eerror $"No loaded modules provide" "\"${conf[0]}\" (${conf[0]}_start)"
			fi
		fi

		if [[ -n ${fallback[config_counter]} ]] ; then
			einfo $"Trying fallback configuration"
			config[config_counter]="${fallback[config_counter]}"
			fallback[config_counter]=""

			# Do we have a fallback route?
			if [[ -n ${fallback_route[config_counter]} ]] ; then
				x="fallback_route[config_counter]"
				eval "routes_${ifvar}=( \"\${!x}\" )"
				fallback_route[config_counter]=""
			fi

			(( config_counter-- )) # since the loop will increment it
			continue
		fi
	done
	eoutdent

	# We return failure if no configuration parameters worked
	${config_worked} || return 1

	# Start any modules with _post_start
	for mod in ${MODULES[@]}; do
		if is_function "${mod}_post_start" ; then
			${mod}_post_start "${iface}" || return 1
		fi
	done

	return 0
}

# bool iface_stop(char *interface)
#
# iface_stop: bring down an interface.  Don't trust information in
# /etc/conf.d/net since the configuration might have changed since
# iface_start ran.  Instead query for current configuration and bring
# down the interface.
iface_stop() {
	local iface="$1" i= aliases= need_begin=false mod=
	local RC_INDENTATION="${RC_INDENTATION}"

	# pre Stop any modules
	for mod in ${MODULES[@]}; do
		if is_function "${mod}_pre_stop" ; then
			${mod}_pre_stop "${iface}" || return 1
		fi
	done

	einfo $"Bringing down" "${iface}"
	eindent

	# Collect list of aliases for this interface.
	# List will be in reverse order.
	if interface_exists "${iface}" ; then
		aliases=$(interface_get_aliases_rev "${iface}")
	fi

	# Stop aliases before primary interface.
	# Note this must be done in reverse order, since ifconfig eth0:1 
	# will remove eth0:2, etc.  It might be sufficient to simply remove 
	# the base interface but we're being safe here.
	for i in ${aliases} ${iface}; do
		# Stop all our modules
		for mod in ${MODULES[@]}; do
			if is_function "${mod}_stop" ; then
				${mod}_stop "${i}" || return 1
			fi
		done

		# A module may have removed the interface
		if ! interface_exists "${iface}" ; then
			eend 0
			continue
		fi

		# We don't delete ppp assigned addresses
		if ! is_function pppd_exists || ! pppd_exists "${i}" ; then
			# Delete all the addresses for this alias
			interface_del_addresses "${i}"
		fi

		# Do final shut down of this alias
		if [[ ${IN_BACKGROUND} != "true" \
			&& ${RC_DOWN_INTERFACE} == "yes" ]] ; then
			ebegin $"Shutting down" "${i}"
			interface_iface_stop "${i}"
			eend "$?"
		fi
	done

	# post Stop any modules
	for mod in ${MODULES[@]}; do
		# We have already taken down the interface, so no need to error
		is_function "${mod}_post_stop" && ${mod}_post_stop "${iface}"
	done

	return 0
}

# bool run_start(char *iface)
#
# Brings up ${IFACE}.  Calls preup, iface_start, then postup.
# Returns 0 (success) unless preup or iface_start returns 1 (failure).
# Ignores the return value from postup.
# We cannot check that the device exists ourselves as modules like
# tuntap make create it.
run_start() {
	local iface="$1" IFVAR=$(bash_variable "$1")

	# We do this so users can specify additional addresses for lo if they
	# need too - additional routes too
	# However, no extra modules are loaded as they are just not needed
	if [[ ${iface} == "lo" ]] ; then
		metric_lo="0"
		config_lo=( "127.0.0.1/8 brd 127.255.255.255" "${config_lo[@]}" )
		routes_lo=( "127.0.0.0/8 via 127.0.0.1" "${routes_lo[@]}" )
	elif [[ ${iface} == "lo0" ]] ; then
		metric_lo0="0"
		config_lo0=( "127.0.0.1/8 brd 127.255.255.255" "${config_lo[@]}" )
		routes_lo0=( "127.0.0.0/8 via 127.0.0.1" "${routes_lo[@]}" )
	fi

	# We may not have a loaded module for ${iface}
	# Some users may have "alias natsemi eth0" in /etc/modules.d/foo
	# so we can work with this
	# However, if they do the same with eth1 and try to start it
	# but eth0 has not been loaded then the module gets loaded as
	# eth0.
	# Not much we can do about this :(
	# Also, we cannot error here as some modules - such as bridge
	# create interfaces
	if ! interface_exists "${iface}" && [[ -x /sbin/modprobe ]] ; then
		/sbin/modprobe "${iface}" &>/dev/null
	fi

	# Call user-defined preup function if it exists
	if is_function preup ; then
		einfo $"Running preup function"
		eindent
		( preup "${iface}" )
		eend "$?" $"preup" "${iface}" $"failed" || return 1
		eoutdent
	fi

	# If config is set to noop and the interface is up with an address
	# then we don't start it
	local config=
	config="config_${IFVAR}[@]"
	config=( "${!config}" )
	if [[ ${config[0]} == "noop" ]] && interface_is_up "${iface}" true ; then
		einfo $"Keeping current configuration for" "${iface}"
		eend 0
	else
		# Remove noop from the config var
		[[ ${config[0]} == "noop" ]] \
			&& eval "config_${IFVAR}=( "\"\$\{config\[@\]:1\}\"" )"

		# There may be existing ip address info - so we strip it
		if [[ ${RC_INTERFACE_KEEP_CONFIG} != "yes" \
			&& ${IN_BACKGROUND} != "true" ]] ; then
			interface_del_addresses "${iface}"
		fi

		# Start the interface
		if ! iface_start "${iface}" ; then
			if [[ ${IN_BACKGROUND} != "true" ]] ; then
				interface_exists "${iface}" && interface_down "${iface}"
			fi
			eend 1
			return 1
		fi
	fi

	# Call user-defined postup function if it exists
	if is_function postup ; then
		# We need to mark the service as started incase a
		# postdown function wants to restart services that depend on us
		mark_service_started "net.${iface}"
		end_service "net.${iface}" 0
		einfo $"Running postup function"
		eindent
		( postup "${iface}" )
		eoutdent
	fi

	return 0
}

# bool run_stop(char *iface) {
#
# Brings down ${iface}.  If predown call returns non-zero, then
# stop returns non-zero to indicate failure bringing down device.
# In all other cases stop returns 0 to indicate success.
run_stop() {
	local iface="$1" IFVAR=$(bash_variable "$1") x

	# Load our ESSID variable so users can use it in predown() instead
	# of having to write code.
	local ESSID=$(get_options ESSID) ESSIDVAR=
	[[ -n ${ESSID} ]] && ESSIDVAR=$(bash_variable "${ESSID}")

	# Call user-defined predown function if it exists
	if is_function predown ; then
		einfo $"Running predown function"
		eindent
		( predown "${iface}" )
		eend $? $"predown" "${iface}" $"failed" || return 1
		eoutdent
	elif is_net_fs / ; then
		eerror $"root filesystem is network mounted -- can't stop" "${iface}"
		return 1
	elif is_union_fs / ; then
		for x in $(unionctl "${dir}" --list \
		| sed -e 's/^\(.*\) .*/\1/') ; do
			if is_net_fs "${x}" ; then
				eerror $"Part of the root filesystem is network mounted - cannot stop" "${iface}"
				return 1
			fi
		done
	fi

	iface_stop "${iface}" || return 1  # always succeeds, btw

	# Release resolv.conf information.
	[[ -x /sbin/resolvconf ]] && resolvconf -d "${iface}"
	
	# Mark us as inactive if called from the background
	[[ ${IN_BACKGROUND} == "true" ]] && mark_service_inactive "net.${iface}"

	# Call user-defined postdown function if it exists
	if is_function postdown ; then
		# We need to mark the service as stopped incase a
		# postdown function wants to restart services that depend on us
		[[ ${IN_BACKGROUND} != "true" ]] && mark_service_stopped "net.${iface}"
		end_service "net.${iface}" 0
		einfo $"Running postdown function"
		eindent
		( postdown "${iface}" )
		eoutdent
	fi


	return 0
}

# bool run(char *iface, char *cmd)
#
# Main start/stop entry point
# We load modules here and remove any functions that they
# added as we may be called inside the same shell scope for another interface
run() {
	local iface="$1" cmd="$2" r=1 RC_INDENTATION="${RC_INDENTATION}"
	local starting=true
	local -a MODULES=() mods=()
	local IN_BACKGROUND="${IN_BACKGROUND}"

	if [[ ${IN_BACKGROUND} == "true" || ${IN_BACKGROUND} == "1" ]] ; then
		IN_BACKGROUND=true
	else
		IN_BACKGROUND=false
	fi

	# We need to override the exit function as runscript.sh now checks
	# for it. We need it so we can mark the service as inactive ourselves.
	unset -f exit

	eindent
	[[ ${cmd} == "stop" ]] && starting=false

	# We force lo to only use these modules for a major speed boost
	if is_loopback "${iface}" ; then	
		modules_force=( "ifconfig" "system" )
	fi

	if modules_load "${iface}" "${starting}" ; then
		if [[ ${cmd} == "stop" ]] ; then
			# Reverse the module list for stopping
			mods=( "${MODULES[@]}" )
			for ((i = 0; i < ${#mods[@]}; i++)); do
				MODULES[i]=${mods[((${#mods[@]} - i - 1))]}
			done

			run_stop "${iface}" && r=0
		else
			# Only hotplug on ethernet interfaces
			if [[ ${IN_HOTPLUG} == 1 ]] ; then
				if ! interface_is_ethernet "${iface}" ; then
					eerror $"We only hotplug for ethernet interfaces"
					return 1
				fi
			fi

			run_start "${iface}" && r=0
		fi
	fi

	if [[ ${r} != "0" ]] ; then
		if [[ ${cmd} == "start" ]] ; then
			# Call user-defined failup if it exists
			if is_function failup ; then
				einfo $"Running failup function"
				eindent
				( failup "${iface}" )
				eoutdent
			fi
		else
			# Call user-defined faildown if it exists
			if is_function faildown ; then
				einfo $"Running faildown function"
				eindent
				( faildown "${iface}" )
				eoutdent
			fi
		fi
		[[ ${IN_BACKGROUND} == "true" ]] \
			&& mark_service_inactive "net.${iface}"
	fi

	return "${r}"
}

# bool start(void)
#
# Start entry point so that we only have one function
# which localises variables and unsets functions
start() {
	declare -r IFACE="${SVCNAME#*.}"
	einfo "Starting ${IFACE}"
	run "${IFACE}" start
}

# bool stop(void)
#
# Stop entry point so that we only have one function
# which localises variables and unsets functions
stop() {
	declare -r IFACE="${SVCNAME#*.}"
	einfo "Stopping ${IFACE}"
	run "${IFACE}" stop
}

# vim: set ts=4 :
