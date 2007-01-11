# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Start logging console output since we have all /dev stuff setup
bootlog start

# mount $svcdir as something we can write to if it's not rw
# On vservers, / is always rw at this point, so we need to clean out
# the old service state data
if touch "${svcdir}/.test" 2>/dev/null ; then
	rm -rf "${svcdir}/.test" \
		$(ls -d1 "${svcdir}"/* 2>/dev/null | grep -Ev "(depcache|deptree)$")
else
	mount_svcdir
fi

# Update init dependencies if needed
RC_FIX_FUTURE="no" depscan.sh

# We set the forced softlevel from the kernel command line
# It needs to be run right after proc is mounted for the
# boot runlevel
setup_defaultlevels

splash "rc_init" "${argv1}"

# $BOOT can be used by rc-scripts to test if it is the first time
# the 'boot' runlevel is executed.  Now also needed by some stuff in
# the 'sysinit' runlevel ...
export BOOT="yes"

# Coldplug any net devices found in /dev/
if [[ ${RC_COLDPLUG:-yes} == "yes" ]] ; then
	for n in /dev/psm[0-9]* /dev/ums[0-9]* /dev/net/*; do
		[[ -e ${n} ]] || continue
		if [[ ${n} == "/dev/net/"* ]] ; then
			n="net.${n#/dev/net/*}"
		else
			n="moused.${n#/dev/*}"
		fi
		[[ -e /etc/init.d/"${n}" ]] || continue
		doit=0
		set -f
		for x in ${RC_PLUG_SERVICES} ; do
			[[ ${n} == ${x} ]] && break
			if [[ "!${n}" == ${x} ]] ; then
				doit=1
				break
			fi
		done
		set +f
		if [[ ${doit} == "0" ]] ; then
			ln -snf "/etc/init.d/${n}" \
				"${svcdir}"/coldplugged/"${n}"
		fi
	done
fi

# If booting off CD, we want to update inittab before setting the runlevel
if [[ -f /sbin/livecd-functions.sh && -n ${CDBOOT} ]] ; then
	ebegin "Updating inittab"
	livecd_fix_inittab
	eend $?
	/sbin/telinit q &>/dev/null
fi

echo "sysinit" > "${svcdir}/softlevel"

# sysinit is now done, so allow init scripts to run normally
[[ -e /dev/.rcsysinit ]] && rm -f /dev/.rcsysinit

# If the user's /dev/null or /dev/console are missing, we 
# should help them out and explain how to rectify the situation
if [[ ${dev_null} -eq 0 || ${dev_console} -eq 0 ]] && \
   [[ -e /usr/share/baselayout/issue.devfix ]] ; then
	# Backup current /etc/issue
	if [[ -e /etc/issue && ! -e /etc/issue.devfix ]] ; then
		mv -f /etc/issue /etc/issue.devfix
	fi

	cp -f /usr/share/baselayout/issue.devfix /etc/issue
fi

# Check and save if the user wants interactive
user_want_interactive && svcinteractive="yes"
echo "${svcinteractive:-no}" > "${svcdir}/interactive"

# vim: set ts=4 :
