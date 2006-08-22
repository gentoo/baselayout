# Copyright (c) 2005-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Giampaolo Tomassoni <g.tomassoni@libero.it>

# int atmclip_svc_start(char *name, char *desc)
#
# This starts a service. Albeit atmsigd, ilmid and atmarpd do allow for back-
# grounding through the -b option, its usage causes them to be sensible to
# SIGHUP, which is sent to all daemons when console detaches right after
# startup. This is probably due to the fact that these programs don't detach
# themself from the controlling terminal when backgrounding... The only way I
# see to overcame this is to use the --background option in start-stop-daemon,
# which is reported as a "last resort" method, but it acts correctly about this.
atmclip_svc_start() {
    ebegin "Starting $2 Daemon ($1)"
    start-stop-daemon --start \
		--background \
		--make-pidfile --pidfile "/var/run/$1.pid" \
		--exec "/usr/sbin/$1" -- -l syslog
    eend $?
}

# int atmclip_svcs_start()
#
# This starts the whole set of atm services needed by clip
atmclip_svcs_start() {
    einfo "First CLIP instance: starting ATM CLIP daemons"
    eindent

    if [[ ${clip_full:-yes} == "yes" ]]; then
		atmclip_svc_start atmsigd "Signaling" && \
		atmclip_svc_start ilmid	  "Integrated Local Management Interface" && \
		atmclip_svc_start atmarpd "Address Resolution Protocol"
    else
		atmclip_svc_start atmarpd "Address Resolution Protocol"
    fi

    local r=$?

    eoutdent
    return ${r}
}

# void atmclip_svc_stop(char *name, char* desc)
#
atmclip_svc_stop() {
    ebegin "Stopping $2 Daemon ($1)"
    start-stop-daemon --stop \
		--retry \
		--pidfile "/var/run/$1.pid" \
		--exec "/usr/sbin/$1"
    eend $?
}

# void atmclip_svcs_stop()
#
atmclip_svcs_stop() {
    einfo "Last CLIP instance: stopping ATM CLIP daemons"
    eindent

    # Heartake operation!
    sync

    atmclip_svc_stop atmarpd "Address Resolution Protocol"
    if [[ ${clip_full:-yes} == "yes" ]]; then
		atmclip_svc_stop ilmid "Integrated Local Management Interface"
		atmclip_svc_stop atmsigd "Signaling"
    fi

    eoutdent
}


# bool are_atmclip_svcs_running()
#
are_atmclip_svcs_running() {
    is_daemon_running atmarpd || return 1
    if [[ ${clip_full:-yes} == "yes" ]]; then
		is_daemon_running ilmid	  || return 1
		is_daemon_running atmsigd || return 1
    fi

    return 0
}

atmarp() {
    /usr/sbin/atmarp "$@"
}


# void clip_depend(void)
#
# Sets up the dependancies for this module
clip_depend() {
    before interface
    provide clip
    functions interface_down interface_up interface_exists is_daemon_running
    variables clip
}


# bool clip_check_installed(void)
#
# Returns true if the kernel clip module and linux-atm tools are installed,
# otherwise false. Please note that I'm checking for the presence of some
# daemons which are not needed in case you set "clip_full=no". They are part of
# the linux-atm package anyway, so it shouldn't hurt to check them too out.
clip_check_installed() {
    local x
    for x in atmsigd ilmid atmarpd atmarp ; do
		if [[ ! -x "/usr/sbin/${x}" ]] ; then
		    ${1:-false} && eerror "You need first to emerge net-dialup/linux-atm"
	    	return 1
		fi
    done

    return 0
}

# bool clip_pre_start(char *iface)
#
# Start the CLIP daemons
# Create the interface by calling atmarp -c
#
# Returns 0 (true) when successful, non-zero otherwise
clip_pre_start() {
    local iface="$1" ifvar=$(bash_variable "$1")
    local x="clip_$ifvar[@]"
    local -a opts=( "${!x}" )

    [[ -z ${opts} ]] && return 0
    clip_check_installed || return 1

    if [[ ! -r /proc/net/atm/arp ]] ; then
		modprobe clip && sleep 2
		if [[ ! -r /proc/net/atm/arp ]] ; then
	    	eerror "You need first to enable kernel support for ATM CLIP"
	    	return 1
		fi
    fi
	
    local started_here
    if ! are_atmclip_svcs_running ; then
		atmclip_svcs_start || return 1
		started_here=1
    fi

    if ! interface_exists "${iface}" ; then
		ebegin "Creating CLIP interface ${iface}"
		atmarp -c "${iface}"
		eend $?

		if [[ $? != "0" && ! -z ${started_here} ]]; then
	    	atmclip_svcs_stop
	    	return 1
		fi
    fi

    return 0
}

# bool clip_post_start(char *iface)
#
# Basically we create PVCs here.
clip_post_start() {
    local iface="$1" ifvar=$(bash_variable "$1") i
    local x="clip_$ifvar[@]"
    local -a opts=( "${!x}" )

    [[ -z ${opts} ]] && return 0
    clip_check_installed || return 1
    are_atmclip_svcs_running || return 1

    # The atm tools (atmarpd?) are silly enough that they would not work with
    # iproute2 interface setup as opposed to the ifconfig one.
    # The workaround is to temporarily toggle the interface state from up
    # to down and then up again, without touching its address. This (should)
    # work with both iproute2 and ifconfig.
    interface_down "${iface}"
    interface_up "${iface}"

    # Now the real thing: create a PVC with our peer(s).
    # There are cases in which the ATM interface is not yet
    # ready to establish new VCCs. In that cases, atmarp would
    # fail. Here we allow 10 retries to happen every 2 seconds before
    # reporting problems. Also, when no defined VC can be established,
    # we stop the ATM daemons.
    local has_failures i
    for (( i=0; i<${#opts[@]}; i++ )); do
		set -- ${opts[${i}]}
		local peerip="$1"; shift
		local ifvpivci="$1"; shift

		ebegin "Creating PVC ${ifvpivci} for peer ${peerip}"

		local nleftretries emsg ecode
		for ((nleftretries=10; nleftretries > 0; nleftretries--)); do
	    	emsg=$(atmarp -s "${peerip}" "${ifvpivci}" "$@" 2>&1)
	    	ecode=$?
	    	[[ ${ecode} == "0" ]] && break
	    	sleep 2
		done

	eend ${ecode}

	if [[ ${ecode} != "0" ]]; then
	    eerror "Creation failed for PVC ${ifvpivci}: ${emsg}"
	    has_failures=1
	fi
    done

    if [[ -n ${has_failures} ]]; then
		clip_pre_stop "${iface}"
		clip_post_stop "${iface}"
		return 1
    else
		return 0
    fi
}

# bool clip_pre_stop(char *iface)
#
# Here we basicly undo the PVC creation previously created through the
# clip_post_start function. When we establish a new PVC, a corresponding line
# is added to the /proc/net/atm/arp file, so we inspect it to extract all the
# outstanding PVCs of this interface.
clip_pre_stop() {
    local iface="$1" ifvar=$(bash_variable "$1") i
    local x="clip_$ifvar[@]"
    local -a opts=( "${!x}" )

    [[ -z ${opts} ]] && return 0

    are_atmclip_svcs_running || return 0

	# We remove all the PVCs which may have been created by
	# clip_post_start for this interface. This shouldn't be
	# needed by the ATM stack, but sometimes I got a panic
	# killing CLIP daemons without previously vacuuming
	# every active CLIP PVCs.
	# The linux 2.6's ATM stack is really a mess...
	local itf t encp idle ipaddr left
	einfo "Removing PVCs on this interface"
	eindent
	{
		read left && \
		while read itf t encp idle ipaddr left ; do
			if [[ ${itf} == "${iface}" ]]; then
				ebegin "Removing PVC to ${ipaddr}"
				atmarp -d "${ipaddr}"
				eend $?
			fi
		done
	} < /proc/net/atm/arp
	eoutdent
}

# bool clip_post_stop(char *iface)
#
# Here we should teorically delete the interface previously created in the
# clip_pre_start function, but there is no way to "undo" an interface creation.
# We can just leave the interface down. "ifconfig -a" will still list it...
# Also, here we can stop the ATM CLIP daemons if there is no other CLIP PVC
# outstanding. We check this condition by inspecting the /proc/net/atm/arp file.
clip_post_stop() {
    local iface="$1" ifvar=$( bash_variable "$1" ) i
    local x="clip_$ifvar[@]"
    local -a opts=( "${!x}" )

    [[ -z ${opts} ]] && return 0

    are_atmclip_svcs_running || return 0

    local itf left hasothers
    {
		read left && \
		while read itf left ; do
	    	if [[ ${itf} != "${iface}" ]] ; then
				hasothers=1
				break
	    	fi
		done
    } < /proc/net/atm/arp

    if [[ -z ${hasothers} ]] ; then
		atmclip_svcs_stop || return 1
    fi
}

# vim: set ts=4 :
