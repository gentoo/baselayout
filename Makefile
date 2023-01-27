# baselayout Makefile
# Copyright 2006-2011 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
#
# We've moved the installation logic from Gentoo ebuild into a generic
# Makefile so that the ebuild is much smaller and more simple.
# It also has the added bonus of being easier to install on systems
# without an ebuild style package manager.

PV = 2.10
PKG = baselayout-$(PV)
DISTFILE = $(PKG).tar.bz2

CHANGELOG_LIMIT = --after="1 year ago"
INSTALL_DIR    = install -m 0755 -d
INSTALL_EXE    = install -m 0755
INSTALL_FILE   = install -m 0644
INSTALL_SECURE = install -m 0600

KEEP_DIRS = \
	/bin \
	/boot \
	/dev \
	/etc/profile.d \
	/home \
	/media \
	/mnt \
	/opt \
	/proc \
	/root \
	/run \
	/sbin \
	/sys \
	/usr/bin \
	/usr/local/bin \
	/usr/local/sbin \
	/usr/sbin \
	/usr/src \
	/var/cache \
	/var/empty \
	/var/lib \
	/var/log \
	/var/spool

all:

changelog:
	git log ${CHANGELOG_LIMIT} --format=full > ChangeLog

clean:

install:
	$(INSTALL_DIR) $(DESTDIR)/etc
	cp -pPR etc/* $(DESTDIR)/etc/
	echo "Gentoo Base System release ${PV}" > ${DESTDIR}/etc/gentoo-release
	$(INSTALL_DIR) $(DESTDIR)/lib
	cp -pPR lib/* $(DESTDIR)/lib/
	$(INSTALL_DIR) $(DESTDIR)/usr/lib
	ln -snf ../usr/lib/os-release ${DESTDIR}/etc/os-release
	./make_os_release ${PV} > $(DESTDIR)/usr/lib/os-release
	$(INSTALL_DIR) $(DESTDIR)/usr/share/baselayout
	cp -pPR share/* $(DESTDIR)/usr/share/baselayout/
	# FHS compatibility symlinks
	ln -snf ../proc/self/mounts $(DESTDIR)/etc/mtab
	ln -snf ../var/tmp $(DESTDIR)/usr/tmp
	$(INSTALL_DIR) $(DESTDIR)/var
	ln -snf ../run $(DESTDIR)/var/run
	ln -snf ../run/lock $(DESTDIR)/var/lock

layout:
	# Create base filesytem layout
	for x in $(KEEP_DIRS) ; do \
		$(INSTALL_DIR) $(DESTDIR)$$x ; \
	done
	# Special dirs
	chmod 0700 $(DESTDIR)/root
	chmod 1777 $(DESTDIR)/var/tmp
	chmod 1777 $(DESTDIR)/tmp

layout-usrmerge: layout
	rm -fr ${DESTDIR}/bin
	rm -fr ${DESTDIR}/sbin
	rm -fr ${DESTDIR}/usr/sbin
	ln -snf usr/bin ${DESTDIR}/bin
	ln -snf usr/bin ${DESTDIR}/sbin
	ln -snf bin ${DESTDIR}/usr/sbin

live:
	rm -rf /tmp/$(PKG)
	cp -r . /tmp/$(PKG)
	tar jcf /tmp/$(PKG).tar.bz2 -C /tmp $(PKG) --exclude=.git
	rm -rf /tmp/$(PKG)
	ls -l /tmp/$(PKG).tar.bz2

release:
	git show-ref -q --tags $(PKG)
	git archive --prefix=$(PKG)/ $(PKG) | bzip2 > $(DISTFILE)
	ls -l $(DISTFILE)

snapshot:
	git show-ref -q $(GITREF)
	git archive --prefix=$(PKG)/ $(GITREF) | bzip2 > $(PKG)-$(GITREF).tar.bz2
	ls -l $(PKG)-$(GITREF).tar.bz2

.PHONY: all changelog clean install layout  live release snapshot

# vim: set ts=4 :
