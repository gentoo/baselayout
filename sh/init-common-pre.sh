# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# Setup initial $PATH just in case
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:${PATH}"

# Help users recover their systems incase these go missing
[[ -c /dev/null ]] && dev_null=1 || dev_null=0
[[ -c /dev/console ]] && dev_console=1 || dev_console=0

echo
echo -e "${GOOD}Gentoo/$(uname) $(get_base_ver); ${BRACKET}http://www.gentoo.org/${NORMAL}"
echo -e " Copyright 1999-2007 Gentoo Foundation; Distributed under the GPLv2"
echo
if [[ ${RC_INTERACTIVE} == "yes" ]] ; then
	echo -e "Press ${GOOD}I${NORMAL} to enter interactive boot mode"
	echo
fi

# vim: set ts=4 :
