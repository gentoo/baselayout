#!/bin/bash
export TMP="${TMP:-/tmp}"
export V="1.13.0_alpha1"
export NAME="baselayout"
export DEST="${TMP}/${NAME}-${V}"

if [[ $1 != "-f" ]] ; then
	echo "Performing sanity checks (run with -f to skip) ..."

	# Check that we're updated
	svnfiles=$( svn status --no-ignore 2>&1 | egrep -v '^(U|P)' )
	if [[ -n ${svnfiles} ]] ; then
		echo "Refusing to package tarball until svn is in sync:"
		echo "$svnfiles"
		exit 1
	fi
fi

echo "Creating tarball ..."
rm -rf ${DEST}
install -d -m0755 ${DEST}

for x in ChangeLog Makefile bin etc init.d net-scripts sbin src rc-lists man ; do
	cp -ax $x ${DEST}
done

(cd ${DEST}/src; make clean)

# do not yet package src/core stuff
rm -rf ${DEST}/src/core
#[[ -f ${DEST}/Makefile ]] && (cd ${DEST}/src; make distclean)

chown -R root:root ${DEST}
chmod 0755 ${DEST}/sbin/*
chmod 0755 ${DEST}/init.d/*
( cd $TMP/${NAME}-${V} ; rm -rf `find -iname .svn` )
cd $TMP
tar cjvf ${TMP}/${NAME}-${V}.tar.bz2 ${NAME}-${V}
rm -rf ${NAME}-${V}

echo
du -b ${TMP}/${NAME}-${V}.tar.bz2
