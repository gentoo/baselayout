#!/bin/bash
export TMP="/tmp"
export V="1.4.5"
export DEST="${TMP}/rc-scripts-${V}"
rm -rf ${DEST}
install -d -m0755 ${DEST}
for x in bin etc init.d sbin src rc-lists man
do
	cp -ax $x ${DEST}
done
cp ChangeLog ${DEST}
chown -R root.root ${DEST}
chmod 0755 ${DEST}/sbin/*
chmod 0755 ${DEST}/init.d/*
( cd $TMP/rc-scripts-${V} ; rm -rf `find -iname CVS` )
cd $TMP
tar cjvf ${TMP}/rc-scripts-${V}.tar.bz2 rc-scripts-${V}
rm -rf rc-scripts-${V}
