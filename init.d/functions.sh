# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


#daemontools dir
SVCDIR=/var/lib/supervise
#rc-scripts dir
svcdir=/dev/shm/.init.d
#different types of dependancies
deptypes="need use"

getcols() {
	echo $2
}

COLS=`stty size`
COLS=`getcols $COLS`
COLS=$(( $COLS - 7 ))
ENDCOL=$'\e[A\e['$COLS'G'
#now, ${ENDCOL} will move us to the end of the column; irregardless of character width

NORMAL="\033[0m"
GOOD=$'\e[32;01m'
WARN=$'\e[33;01m'
BAD=$'\e[31;01m'
NORMAL=$'\e[0m'

HILITE=$'\e[36;01m'

ebegin() {
	echo -e " ${GOOD}*${NORMAL} ${*}..."
}

ewarn() {
	echo -e " ${WARN}*${NORMAL} ${*}"
}

eerror() {
	echo -e " ${BAD}*${NORMAL} ${*}"
}

einfo() {
	echo -e " ${GOOD}*${NORMAL} ${*}"
}

einfon() {
	echo -ne " ${GOOD}*${NORMAL} ${*}"
}

eend() {
	if [ $# -eq 0 ] || [ $1 -eq 0 ]
	then
		echo -e "$ENDCOL  \e[34;01m[ ${GOOD}ok \e[34;01m]${NORMAL}"
	else
		local returnme
		returnme=$1
		if [ $# -ge 2 ]
		then
			shift
			eerror $*
		fi
		echo -e "$ENDCOL  \e[34;01m[ ${BAD}!! \e[34;01m]${NORMAL}"
		echo
		#extra spacing makes it easier to read
		return $returnme
	fi
}

ewend() {
	if [ $# -eq 0 ] || [ $1 -eq 0 ]
	then
		echo -e "$ENDCOL  \e[34;01m[ ${GOOD}ok \e[34;01m]${NORMAL}"
	else
		local returnme
		returnme=$1
		if [ $# -ge 2 ]
		then
			shift
			ewarn $*
		fi
		echo -e "$ENDCOL  \e[34;01m[ ${WARN}!! \e[34;01m]${NORMAL}"
		echo
		#extra spacing makes it easier to read
		return $returnme
	fi
}
