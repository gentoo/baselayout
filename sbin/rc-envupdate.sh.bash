#!/bin/bash
# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$


source /etc/init.d/functions.sh

if [ "${EUID}" -ne 0 ]
then
	eerror "$0: must be root."
	exit 1
fi

usage() {
echo "usage: rc-envupdate.sh

note:
      This utility generates /etc/profile.env and /etc/csh.env
      from the contents of /etc/env.d/
"
	exit 1
}
		
parse_envd() {

	>${svcdir}/varlist
	>${svcdir}/vardata

	local myenvd_files=""

	#generate our variable list
	for x in $(dolisting /etc/env.d/)
	do
		# Ignore backup files
		if [ "$(echo ${x} | /bin/sed "s:\~$::")" = "${x}" -a \
		     "$(echo ${x} | /bin/sed "s:\.bak$::")" = "${x}" ]
		then
			myenvd_files="${myenvd_files} ${x}"
		else
			continue
		fi

		VARLIST="$(<${svcdir}/varlist)"
		local variable=""
		local value=""
		if [ -f ${x} ] || ([ -L ${x} ] && [ -f $(/bin/readlink ${x}) ])
		then
			(/bin/awk '!/^#|^\t+#/ { gsub ( /=/, "\t" ) ; print $0 }' ${x}) | \
				while read -r variable value
			do
				if [ "$(eval echo \${VARLIST/ ${variable} /})" = "$(eval echo \${VARLIST/# /})" -a \
				     -n "${variable}" -a -n "${value}" ]
				then
					if [ -n "${VARLIST}" ]
					then
						VARLIST="${VARLIST} ${variable} "
					else
						VARLIST=" ${variable} "
					fi
					echo "${VARLIST}" >${svcdir}/varlist
				fi
			done
		fi
	done

	#clear the environment of stale variables
	VARLIST="$(<${svcdir}/varlist)"
	for x in ${VARLIST/LDPATH}
	do
		echo "export $(eval echo ${x})=\"\"" >> ${svcdir}/vardata
	done
	
	#now generate the the variable data
	for x in ${myenvd_files}
	do
		source ${svcdir}/vardata
		VARLIST="$(<${svcdir}/varlist)"
		if [ -f ${x} ] || ([ -L ${x} ] && [ -f $(/bin/readlink ${x}) ])
		then
			(/bin/awk '!/^#|^\t+#/ { gsub ( /=/, "\t" ) ; print $0 }' ${x}) | \
				while read -r variable value
			do
				if [ -n "${variable}" -a -n "${value}" ]
				then
					if [ -n "$(eval echo \${$variable})" ]
					then
						# $KDEDIR and $QTDIR should be set only to the highest
						# env.d files's value ....
						if [ "${variable}" != "KDEDIR" -a \
						     "${variable}" != "QTDIR" ]
						then
							eval ${variable}\="\${$variable}:\${value}"
						else
							eval ${variable}\="\${value}"
						fi
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
