# baselayout Makefile
# Copyright 2006-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)
#
# We've moved the installation logic from Gentoo ebuild into a generic
# Makefile so that the ebuild is much smaller and more simple.
# It also has the added bonus of being easier to install on systems
# without an ebuild style package manager.

SUBDIRS = awk bin conf.d etc init.d man net sbin sh share src

NAME = baselayout
VERSION = 1.13.0_alpha11
PKG = $(NAME)-$(VERSION)

ARCH = x86
OS = Linux

BASE_DIRS = /$(LIB)/rcscripts/init.d /$(LIB)/rcscripts/tmp
KEEP_DIRS = /boot /home /mnt /root \
	/usr/local/bin /usr/local/sbin /usr/local/share/doc /usr/local/share/man \
	/var/lock /var/run

ifeq ($(OS),Linux)
	KEEP_DIRS += /dev /sys
	NET_LO = net.lo
endif
ifneq ($(OS),Linux)
	NET_LO = net.lo0
endif

TOPDIR = .
include $(TOPDIR)/default.mk

install::
	# These dirs may not exist from prior versions
	for x in $(BASE_DIRS) ; do \
		$(INSTALL_DIR) $(DESTDIR)$$x || exit $$? ; \
		touch $(DESTDIR)$$x/.keep || exit $$? ; \
	done
	# Don't install runlevels if they already exist
	if ! test -d $(DESTDIR)etc/runlevels ; then \
		(cd runlevels; $(MAKE) install) ; \
		test -d runlevels.$(OS) && (cd runlevels.$(OS); $(MAKE) install) ; \
		$(INSTALL_DIR) $(DESTDIR)etc/runlevels/single || exit $$? ; \
		$(INSTALL_DIR) $(DESTDIR)etc/runlevels/nonetwork || exit $$? ; \
	fi
	ln -snf ../../$(LIB)/rcscripts/sh/net.sh $(DESTDIR)/etc/init.d/$(NET_LO) || exit $$?
	for x in depscan.sh functions.sh runscript.sh ; do \
		ln -snf ../../sbin/$$x $(DESTDIR)/etc/init.d || exit $$? ; \
	done
	# Handle lib correctly
	if test $(LIB) != "lib" ; then \
		sed -i '/^declare -r svclib=/ s,/lib/,/$(LIB)/,' $(DESTDIR)/sbin/functions.sh || exit $$? ; \
		for x in cachedepends.awk genenviron.awk ; do \
			sed -i 's,/lib/,/$(LIB)/,g' $(DESTDIR)/$(LIB)/rcscripts/awk/$$x || exit $$? ; \
		done ; \
	fi

.PHONY: all clean install

layout:
	# Create base filesytem layout
	for x in $(KEEP_DIRS) ; do \
		$(INSTALL_DIR) $(DESTDIR)$$x || exit $$? ; \
		touch $(DESTDIR)$$x/.keep || exit $$? ; \
	done
	# Special dirs
	install -m 0700 -d $(DESTDIR)/root || exit $$?
	touch $(DESTDIR)/root/.keep || exit $$?
	install -m 1777 -d $(DESTDIR)/var/tmp || exit $$?
	touch $(DESTDIR)/var/tmp/.keep || exit $$?
	install -m 1777 -d $(DESTDIR)/tmp || exit $$?
	touch $(DESTDIR)/tmp/.keep || exit $$?
	# FHS compatibility symlinks stuff
	ln -snf /var/tmp $(DESTDIR)/usr/tmp || exit $$?
	ln -snf share/man $(DESTDIR)/usr/local/man || exit $$?

distcheck:
	svnfiles=`svn status 2>&1 | egrep -v '^(U|P)'` ; \
	if test "x$$svnfiles" != "x" ; then \
		echo "Refusing to package tarball until svn is in sync:" ; \
		echo "$$svnfiles" ; \
		echo "make distforce to force packaging" ; \
		exit 1 ; \
	fi 

distforce:
	install -d /tmp/$(PKG)
	cp -PRp . /tmp/$(PKG)
	find /tmp/$(PKG) -depth -path "*/.svn/*" -delete
	find /tmp/$(PKG) -depth -path "*/.svn" -delete
	rm -rf /tmp/$(PKG)/src/core /tmp/$(PKG)/po
	$(MAKE) -C /tmp/$(PKG) clean
	tar -C /tmp -cvjpf /tmp/$(PKG).tar.bz2 $(PKG)
	rm -Rf /tmp/$(PKG)
	du /tmp/$(PKG).tar.bz2

dist: distcheck	distforce

# vim: set ts=4 :
