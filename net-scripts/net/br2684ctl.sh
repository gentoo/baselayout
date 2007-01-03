# Copyright 2004-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)

# void br2684ctl_depend(void)
br2684ctl_depend() {
	before ppp
}
br2684ctl_expose() {
	variables br2684ctl
}

# bool br2684ctl_check_installed(void)
br2684ctl_check_installed() {
	[[ -x /sbin/br2684ctl ]] && return 0
	${1:-false} && eerror "For RFC 2684 Bridge control support, emerge net-misc/br2684ctl"
	return 1
}

# bool br2684ctl_start(char *iface)
br2684ctl_pre_start() {
	local iface="$1" ifvar=$(bash_variable "$1") opts=
	local number="${iface#${iface%%[0-9]}}"
	
	opts="br2684ctl_${ifvar}"
	[[ -z ${!opts} ]] && return 0

	if [[ $(interface_type "${iface}") != "nas" || -z ${number} ]] ; then
		eerror "interface must be called nas[0-9] for RFC 2684 Bridging"
		return 1
	fi
	
	if [[ " ${!opts} " != *" -a "* ]] ; then
		eerror "-a option (VPI and VCI) is required in br2684_ctl"
		return 1
	fi

	if [[ " ${!opts} " == *" -b "* || " {!opts} " == *" -c "* ]] ; then
		eerror "The -b and -c options are not allowed for br2684ctl_${ifvar}"
		return 1
	fi
	
	einfo "Starting RFC 2684 Bridge control on ${iface}"
	start-stop-daemon --start --exec /sbin/br2684ctl --background \
		--make-pidfile --pidfile "/var/run/br2684ctl-${iface}.pid" \
		-- -c "${number}" ${!opts}
	eend $?
}

# bool br2684ctl_post_stop(char *iface)
br2684ctl_post_stop() {
	local iface="$1"
	local number="${iface#${iface%%[0-9]}}"
	local pidfile="/var/run/br2684ctl-${iface}.pid"
	
	[[ $(interface_type "${iface}") != "nas" ]] && return 0
	
	[[ -e ${pidfile} ]] || return 0
	
	einfo "Stopping RFC 2684 Bridge control on ${iface}"
	start-stop-daemon --stop --exec /sbin/br2684ctl --pidfile "${pidfile}"
	eend $?
}

# vim: set ts=4 :
