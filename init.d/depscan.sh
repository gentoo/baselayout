#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


#needed for $SYSLOGGER (/etc/rc.conf overrides /etc/conf.d/basic).
[ -e /etc/conf.d/basic ] && source /etc/conf.d/basic
[ -e /etc/rc.conf ]      && source /etc/rc.conf

#set default if it is not set
[ "$SYSLOGGER" = "" ] && SYSLOGGER="sysklogd metalog syslog-ng"

source /etc/init.d/functions.sh

if [ ! -d $svcdir ]
then
	install -d -m0755 $svcdir
fi
for x in softscripts snapshot broken started ${deptypes}
do
	if [ ! -d ${svcdir}/${x} ]
	then
		install -d -m0755 ${svcdir}/${x}
	fi
done

#reset the broken services
rm -rf ${svcdir}/broken/*

#call: depend_dbadd dep_type service deps....
depend_dbadd() {
	local mytype
	local myservice
	local x
	mytype=$1
	myservice=$2
	shift 2
	for x in $*
	do
		if [ ! -e /etc/init.d/${x} ]
		then
			#nice thing about use's, is that they do not have to exist
			if [ "$x" != "net" ] && [ "$mytype" != "use" ]
			then
			#bogus dependency
				einfo "need: can't find service \"${x}\" needed by \"${myservice}\"; continuing..."
				#$myservice is broken due to missing 'need' dependancies
				if [ "$mytype" = "need" ]
				then
					if [ ! -d ${svcdir}/broken/${myservice} ]
					then
						install -d -m0755 ${svcdir}/broken/${myservice}
					fi
					if [ ! -e ${svcdir}/broken/${myservice}/${x} ]
					then
						touch ${svcdir}/broken/${myservice}/${x}
					fi
				fi
				continue
			fi
		fi

		#ugly bug ... if a service depends on itself, it creates
		#a 'mini fork bomb' effect, and breaks things...
		if [ "$x" = "$myservice" ]
		then
			einfo "depend: service \"${x}\" can't depend on itself; continuing..."
			continue
		fi
		if [ ! -d ${svcdir}/${mytype}/${x} ]
		then
			install -d -m0755 ${svcdir}/${mytype}/${x}
		fi
		if [ ! -L ${svcdir}/${mytype}/${x}/${myservice} ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/${mytype}/${x}/${myservice}
		fi
	done
}

need() {
	NEED="$*"
}

use() {
	USE="$*"
}

ebegin "Caching service dependencies"
rm -rf ${svcdir}/need/*
rm -rf ${svcdir}/use/*
for x in /etc/init.d/*
do
	[ "${x##*.}" = "sh" ] && continue
	[ "${x##*.}" = "c" ] && continue
	#set to "" else we get problems
	NEED=""
	USE=""

	myservice=${x##*/}
	depend() {
		NEED=""
		USE=""
		return
	}
	source ${x}
	depend
	if [ "$NEED" = "" ] && [ "$USE" = "" ]
	then
		continue
	fi
	if [ "$NEED" != "" ]
	then
		depend_dbadd need $myservice $NEED
	fi
	if [ "$USE" != "" ]
	then
		USE=${USE/logger/${SYSLOGGER}}
		depend_dbadd use $myservice $USE
	fi
done
eend
