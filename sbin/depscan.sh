#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


source /sbin/functions.sh

if [ ! -d ${svcdir} ]
then
	install -d -m0755 ${svcdir}
fi
for x in softscripts cache snapshot options broken started provide ${deptypes} ${ordtypes}
do
	if [ ! -d ${svcdir}/${x} ]
	then
		install -d -m0755 ${svcdir}/${x}
		if [ "$?" -ne 0 ]
		then
			#there is a problem creating the directories, so quit with fail
			#status
			exit 1
		fi
	fi
done

# According to Spider, this should speed things up a bit, as
# all the stuff in /etc/init.d/ should be cached by the kernel
/bin/cat /etc/init.d/* >/dev/null

#call: depend_dbadd dep_type service deps....
depend_dbadd() {
	local mytype="${1}"
	local myservice="${2}"
	local x=""
	shift 2
	for x in $*
	do
		if [ ! -e ${svcdir}/cache/${myservice}.depend ]
		then
			continue
		fi
		if [ ! -e ${svcdir}/cache/${x}.depend ]
		then
			#handle 'need', as it is the only dependency type that
			#should handle invalid database entries currently.  The only
			#other type of interest is 'pretend' which *should* add
			#invalid database entries (no virtual depend should ever
			#actually have a matching rc-script).
			if [ "${mytype}" = "need" ] && \
			   [ ! -d ${svcdir}/provide/${x} ] && \
			   [ "${x}" != "net" ]
			then
				ewarn "NEED:  can't find service \"${x}\" needed by \"${myservice}\";"
				ewarn "       continuing..."
				
				#$myservice is broken due to missing 'need' dependancies
				if [ ! -d ${svcdir}/broken/${myservice} ]
				then
					install -d -m0755 ${svcdir}/broken/${myservice}
				fi
				if [ ! -e ${svcdir}/broken/${myservice}/${x} ]
				then
					touch ${svcdir}/broken/${myservice}/${x}
				fi
				continue
			elif [ "${mytype}" != "provide" ] && \
			     [ ! -d ${svcdir}/provide/${x} ] && \
			     [ "${x}" != "net" ]
			then
				continue
			fi
		fi

		#ugly bug ... if a service depends on itself, it creates
		#a 'mini fork bomb' effect, and breaks things...
		if [ "${x}" = "${myservice}" ]
		then
			#dont work too well with the '*' use and need
			if [ "${mytype}" != "before" ] && [ "${mytype}" != "after" ]
			then
				ewarn "DEPEND:  service \"${x}\" can't depend on itself;"
				ewarn "         continuing..."
			fi
			continue
		fi
	
		# NEED and USE override BEFORE and AFTER
		if (([ "${mytype}" = "before" ] && \
		    [ ! -L ${svcdir}/need/${x}/${myservice} ]) && \
		   ([ "${mytype}" = "before" ] && \
		    [ ! -L ${svcdir}/use/${x}/${myservice} ])) || \
		   (([ "${mytype}" = "after" ] && \
		    [ ! -L ${svcdir}/need/${myservice}/${x} ]) && \
		   ([ "${mytype}" = "after" ] && \
		    [ ! -L ${svcdir}/use/${myservice}/${x} ])) || \
		   ([ "${mytype}" = "need" ] || [ "${mytype}" = "use" ] || \
		    [ "${mytype}" = "provide" ])
		then
			if [ ! -d ${svcdir}/${mytype}/${x} ]
			then
				install -d -m0755 ${svcdir}/${mytype}/${x}
			fi
			if [ ! -L ${svcdir}/${mytype}/${x}/${myservice} ]
			then
				ln -sf /etc/init.d/${myservice} ${svcdir}/${mytype}/${x}/${myservice}
			fi
		fi
	done
}

check_rcscript() {
	[ ! -e ${1} ] && return 1
	
	[ "${1##*.}" = "sh" ] && return 1
	[ "${1##*.}" = "c" ] && return 1

	local IFS='!'
	local hash=""
	local shell=""
	(cat ${1}) | { read hash shell
		if [ "${hash}" = "#" ] && [ "${shell}" = "/sbin/runscript" ]
		then
			return 0
		else
			return 1
		fi
	}
}

cache_depend() {
	[ ! -e ${1} ] && return 1

	#the cached file should not be empty
	echo "echo foo >/dev/null 2>&1" > ${svcdir}/cache/${1##*/}.depend

	local myline=""
	local dowrite=1
	local mycount=0
	local count=0
	#we do not want comments in our cache
	(cat ${1} | awk '!/^#|^\t+#/ { print $0 }') | { while read myline
		do
			if [ "${myline/depend*()/}" != "${myline}" ]
			then
				dowrite=0
			fi
			if [ "${dowrite}" -eq 0 ]
			then
				#to grab the whole depend() function, starting and ending braces
				#should be equal
				local mycount="$(echo ${myline} | \
					awk '{ BNUM += gsub(/{/, "{") ; BNUM -= gsub(/}/, "}") } \
					END { print BNUM }')"
				count=$(( $count + $mycount ))
				
				echo "${myline}" >> ${svcdir}/cache/${1##*/}.depend
			fi
			if [ "${myline/\}/}" != "${myline}" ] && \
			   [ "${dowrite}" -eq 0 ] && [ "${count}" -eq 0 ]
			then
				dowrite=1
				break
			fi
		done
	}
	return 0
}

need() {
	NEED="${*}"
}

use() {
	USE="${*}"
}

before() {
	BEFORE="${*}"
}

after() {
	AFTER="${*}"
}

provide() {
	PROVIDE="${*}"
}

ebegin "Caching service dependencies"

#cleanup and fix a problem with 'for x in foo/*' if foo/ is empty
rm -rf ${svcdir}/need/*
rm -rf ${svcdir}/use/*
rm -rf ${svcdir}/before/*
rm -rf ${svcdir}/after/*
rm -rf ${svcdir}/broken/*
rm -rf ${svcdir}/provide/*
rm -rf ${svcdir}/cache/*

#for the '*' need and use types to work
pushd /etc/init.d &>/dev/null

#first cache the depend lines, and calculate all the provides
for x in $(dolisting /etc/init.d/)
do
	check_rcscript ${x} || continue

	#set to "" else we get problems
	PROVIDE=""

	myservice="${x##*/}"
	depend() {
		PROVIDE=""
		return 0
	}
	cache_depend ${x}
	wrap_rcscript ${svcdir}/cache/${myservice}.depend || {
		einfo "ERROR:  ${x} has syntax errors in it, please fix this before"
		einfo "        trying to execute this script..."
		einfo "NOTE:  the dependancies for this script has not been calculated!"
		rm -f {svcdir}/cache/${x##*/}.depend
		continue
	}
	depend
	if [ -n "${PROVIDE}" ]
	then
		depend_dbadd provide "${myservice}" ${PROVIDE}
	fi
done

#now do NEED and USE
for x in $(dolisting /etc/init.d/)
do
	[ ! -e ${svcdir}/cache/${x##*/}.depend ] && continue

	#set to "" else we get problems
	NEED=""
	USE=""

	myservice="${x##*/}"
	depend() {
		NEED=""
		USE=""
		return 0
	}
	#we already warn about the error in the provide loop
	source ${svcdir}/cache/${myservice}.depend
	depend
	if [ -n "${NEED}" ]
	then
		depend_dbadd need "${myservice}" ${NEED}
	fi
	if [ -n "${USE}" ]
	then
		depend_dbadd use "${myservice}" ${USE}
	fi
done

#now do BEFORE and AFTER (we do them in a seperate cycle to
#so that we can check for NEED or USE)
for x in $(dolisting /etc/init.d/)
do
	[ ! -e ${svcdir}/cache/${x##*/}.depend ] && continue

	#set to "" else we get problems
	BEFORE=""
	AFTER=""

	myservice="${x##*/}"
	depend() {
		BEFORE=""
		AFTER=""
		return 0
	}
	#we already warn about the error in the provide loop
	source ${svcdir}/cache/${myservice}.depend
	depend
	if [ -n "${BEFORE}" ]
	then
		depend_dbadd before "${myservice}" ${BEFORE}
		for y in ${BEFORE}
		do
			depend_dbadd after "${y}" "${myservice}"
		done
	fi
	if [ -n "${AFTER}" ]
	then
		depend_dbadd after "${myservice}" ${AFTER}
		for y in ${AFTER}
		do
			depend_dbadd before "${y}" "${myservice}"
		done
	fi
done

#resolve provides
dblprovide="no"
for x in $(dolisting ${svcdir}/provide/)
do
	for mytype in ${deptypes}
	do
		if [ -d ${svcdir}/${mytype}/${x##*/} ]
		then
			for y in $(dolisting ${svcdir}/${mytype}/${x##*/}/)
			do
				depend_dbadd "${mytype}" "${y##*/}" $(ls ${x})
			done
			rm -rf ${svcdir}/${mytype}/${x##*/}
		fi
	done

	counter=0
	for y in $(dolisting ${x})
	do
		counter=$((counter + 1))
	done
	if [ "${counter}" -gt 1 ] && [ "${x##*/}" != "net" ]
	then
		dblprovide="yes"
		errstr="${x##*/}"
	fi
done
if [ "${dblprovide}" = "yes" ]
then
	ewarn "PROVIDE:  it usually is not a good idea to have more than one"
	ewarn "          service provide the same virtual service (${errstr})!"
fi

popd &>/dev/null

eend


# vim:ts=4
