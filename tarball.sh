#!/bin/bash
export TMP="/tmp"
export V="1.0"
export DEST="${TMP}/rc-scripts-${V}"
rm -rf ${DEST}
install -d -m0755 ${DEST}
for x in etc init.d sbin
do
	cp -ax $x ${DEST}
done
chown -R root.root ${DEST}
chmod 0755 ${DEST}/sbin/*
chmod 0755 ${DEST}/init.d/*
cd $TMP
tar cjvf ${TMP}/rc-scripts-${V}.tar.bz2 rc-scripts-${V}
