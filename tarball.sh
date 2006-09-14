#!/bin/bash
export TMP="${TMP:-/tmp}"
export V="1.13.0_alpha1"
export NAME="baselayout"
export DEST="${TMP}/${NAME}-${V}"

if [[ $1 != "-f" ]] ; then
	echo "Performing sanity checks (run with -f to skip) ..."

	# Check that we're updated
	svnfiles=$(svn status --no-ignore 2>&1 | egrep -v '^(U|P)')
	if [[ -n ${svnfiles} ]] ; then
		echo "Refusing to package tarball until svn is in sync:"
		echo "$svnfiles"
		exit 1
	fi
fi

echo "Creating tarball ..."
rm -rf ${DEST}
install -d -m0755 ${DEST}

cp -R . ${DEST}
rm -rf ${DEST}/tarball.sh ${DEST}/po ${DEST}/rc-lists

(cd ${DEST}/src; gmake clean)

# do not yet package src/core stuff
rm -rf ${DEST}/src/core
#[[ -f ${DEST}/Makefile ]] && (cd ${DEST}/src; gmake distclean)

( cd $TMP/${NAME}-${V} ; rm -rf `find . -name .svn` )

if [[ $(uname) == "Linux" ]] ; then
	chown -R root:root ${DEST}
else
	chown -R root:wheel ${DEST}
fi
chmod 0755 ${DEST}/sbin/*
chmod 0755 ${DEST}/init.d/*
cd $TMP
tar cjvf ${TMP}/${NAME}-${V}.tar.bz2 ${NAME}-${V}
rm -rf ${NAME}-${V}

echo
du -k ${TMP}/${NAME}-${V}.tar.bz2
