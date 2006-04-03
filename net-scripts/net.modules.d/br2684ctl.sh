# Copyright (c) 2004-2006 Gentoo Foundation
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
	local iface="$1" ifvar="$(bash_variable "$1")" opts= lnk=

	opts="br2684ctl_${ifvar}"
	[[ -z ${!opts} ]] && return 0

	einfo "Starting RFC 2684 Bridge control on ${iface}"
	
	lnk="link_${ifvar}"
	if [[ -z ${!lnk} ]] ; then
		eerror "No link specified!"
		return 1
	fi

	start-stop-daemon --start --exec /sbin/br2684ctl \
		--pidfile "/var/run/br2684ctl-${!lnk}.pid" --makepid \
		-- -c ${!lnk#nas} ${!opts}
	eend $? && save_options "link" "${!lnk}"
}

# bool br2684ctl_stop(char *iface)
br2684ctl_stop() {
	local lnk="$(get_options link)"
	
	[[ -e /var/run/br2864ctl-${lnk}.pid ]] || return 0
	
	einfo "Stopping RFC 2684 Bridge control on ${iface}"
	start-stop-daemon --stop --exec /sbin/br2864ctl \
		--pidfile "/var/run/br2684ctl-${lnk}.pid"
	eend $?
}

# vim: set ft=sh ts=4 :
