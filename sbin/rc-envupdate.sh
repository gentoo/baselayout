#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$


source /etc/init.d/functions.sh

if [ `id -u` -ne 0 ]
then
	eerror "${0}: must be root."
	exit 1
fi

usage() {
cat << FOO
usage: rc-envupdate.sh

note:
      This utility generates /etc/profile.env and /etc/csh.env
      from the contents of /etc/env.d/

FOO
	exit 1
}
		
parse_envd() {

	>${svcdir}/varlist
	>${svcdir}/vardata

	#generate our variable list
	for x in $(dolisting /etc/env.d/)
	do
		VARLIST="$(/bin/cat ${svcdir}/varlist)"
		local variable=""
		local value=""
		if [ -f ${x} ] || ([ -L ${x} ] && [ -f $(/bin/readlink ${x}) ])
		then
			(/bin/grep -v "#" ${x} | /bin/sed -e "s:\=:\t:g") | while read -r variable value
			do
				if [ "$(eval echo \${VARLIST/${variable}/})" = "${VARLIST}" ] && \
				   [ -n "${variable}" ] && [ -n "${value}" ]
				then
					if [ -n "${VARLIST}" ]
					then
						VARLIST="${VARLIST} ${variable}"
					else
						VARLIST="${variable}"
					fi
					echo "${VARLIST}" >${svcdir}/varlist
				fi
			done
		fi
	done

	#clear the environment of stale variables
	VARLIST="$(/bin/cat ${svcdir}/varlist)"
	for x in ${VARLIST/LDPATH}
	do
		echo "export $(eval echo ${x})=\"\"" >> ${svcdir}/vardata
	done
	
	#now generate the the variable data
	for x in $(dolisting /etc/env.d/)
	do
		source ${svcdir}/vardata
		VARLIST="$(/bin/cat ${svcdir}/varlist)"
		if [ -f ${x} ] || ([ -L ${x} ] && [ -f $(/bin/readlink ${x}) ])
		then
			(/bin/grep -v "#" ${x} | /bin/sed -e "s:\=:\t:g") | while read -r variable value
			do
				if [ -n "${variable}" ] && [ -n "${value}" ]
				then
					if [ -n "$(eval echo \${$variable})" ]
					then
						eval ${variable}\="\${$variable}:\${value}"
					else
						eval ${variable}\="\${value}"
					fi
				fi
				
				>${svcdir}/vardata
				for y in ${VARLIST/LDPATH}
				do
					echo "export $(eval echo ${y})='$(eval echo \${$y})'" >> \
						${svcdir}/vardata
				done
			done
		fi
	done

	#we do not want any '"' in here, else things will break
	/bin/sed -e "s:\"::g" \
		${svcdir}/vardata >${svcdir}/profile.env
	/bin/sed -e "s:export:setenv:g" -e "s:\=: :g" -e "s:\"::g" \
		${svcdir}/vardata >${svcdir}/csh.env
	
	/bin/rm -f ${svcdir}/vardata ${svcdir}/varlist
	/bin/mv -f ${svcdir}/profile.env /etc/profile.env
	/bin/mv -f ${svcdir}/csh.env /etc/csh.env
}

if [ "$#" -ne 0 ]
then
	usage
else
	parse_envd
fi

# vim:ts=4
