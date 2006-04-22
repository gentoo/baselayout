#!/bin/bash
export TMP="${TMP:-.}"
export V="1.6.15"
export DEST="${TMP}/rc-scripts-${V}"

if [[ $1 != "-f" ]] ; then
	echo "Performing sanity checks (run with -f to skip) ..."
	svnfiles=$( svn status 2>&1 | egrep -v '^(U|P)' )
	if [[ -n ${svnfiles} ]] ; then
		echo "Refusing to package tarball until svn is in sync:"
		echo "${svnfiles}"
		exit 1
	fi
fi

echo "Creating tarball ..."
rm -rf ${DEST}

svn export . ${DEST}

# do not yet package src/core stuff
rm -rf ${DEST}/src/core

# copy net-scripts and remove older stuff
install -d -m0755 ${DEST}/lib/rcscripts
mv ${DEST}/net-scripts/init.d/* ${DEST}/init.d/
mv ${DEST}/net-scripts/conf.d/* ${DEST}/etc/conf.d/
mv ${DEST}/net-scripts/net.modules.d ${DEST}/lib/rcscripts/
ln -sfn net.lo ${DEST}/init.d/net.eth0
rm -r ${DEST}/net-scripts

chown -R root:root ${DEST}
chmod 0755 ${DEST}/sbin/*
chmod 0755 ${DEST}/init.d/*
cd $TMP
tar cjvf ${TMP}/rc-scripts-${V}.tar.bz2 rc-scripts-${V}
rm -rf ${DEST}

echo
du -b ${TMP}/rc-scripts-${V}.tar.bz2

