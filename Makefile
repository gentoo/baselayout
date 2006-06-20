# baselayout Makefile
# Copyright (c) 2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)
#
# We've moved the installation logic from Gentoo ebuild into a generic
# Makefile so that the ebuild is much smaller and more simple.
# It also has the added bonus of being easier to install on systems
# without an ebuild style package manager.

NAME = baselayout
VERSION = 1.13.0_alpha1
PKG = $(NAME)-$(VERSION)

ARCH = x86
KERNEL = linux
DESTDIR =
ROOT = /
LIB = lib

DEVDIR = $(DESTDIR)/dev
BINDIR = $(DESTDIR)/bin
SBINDIR = $(DESTDIR)/sbin
LIBDIR = $(DESTDIR)/$(LIB)
INITDIR = $(DESTDIR)/etc/init.d
MANDIR = $(DESTDIR)/usr/share/man
LOGDIR = $(DESTDIR)/var/log
RUNDIR = $(DESTDIR)/var/run

RCDIR = $(LIBDIR)/rcscripts
SHDIR = $(RCDIR)/sh
NETDIR= $(RCDIR)/net
AWKDIR = $(RCDIR)/awk
LVLDIR = $(DESTDIR)/etc/runlevels

# Default init scripts for the boot runlevel
BOOT_LEVEL = bootmisc checkroot checkfs clock consolefont hostname keymaps \
	localmount modules net.lo rmnologin urandom 

# Default init scripts for the default runlevel
DEFAULT_LEVEL = hdparm local netmount

# Don't install these files if they already exist in ROOT
# Basically, don't hit the users key config files
ETC_SKIP = hosts passwd shadow group fstab

KEEP_DIRS = boot dev proc home sys \
	mnt/cdrom mnt/floppy \
	usr/local/bin usr/local/sbin usr/local/share/doc usr/local/share/man \
	var/lib/init.d var/run

SUBDIRS = src

SBINTOLIB = rc-daemon.sh rc-help.sh rc-services.sh \
	init.$(KERNEL).sh init-functions.sh init-common-pre.sh init-common-post.sh

default:
	for x in $(SUBDIRS) ; do \
		cd $$x ; \
		$(MAKE) $(AM_MAKEFLAGS) ; \
	done

clean:
	for x in $(SUBDIRS) ; do \
		cd $$x ; \
		$(MAKE) clean ; \
	done

basedev-linux:
	if ! test -d $(DEVDIR) ; then \
		install -m 0755 -d $(DEVDIR) ; \
	fi
	( curdir=`pwd` ; cd $(DEVDIR) ; \
		$$curdir/sbin/MAKEDEV generic-base ) 

dev-linux:
	install -m 0755 -d $(DEVDIR)
	( curdir=`pwd` ; cd $(DEVDIR) ; \
		suffix= ; \
		case $(ARCH) in \
			arm*)    suffix=-arm ;; \
			alpha)   suffix=-alpha ;; \
			amd64)   suffix=-i386 ;; \
			hppa)    suffix=-hppa ;; \
			ia64)    suffix=-ia64 ;; \
			m68k)    suffix=-m68k ;; \
			mips*)   suffix=-mips ;; \
			ppc*)    suffix=-powerpc ;; \
			s390*)   suffix=-s390 ;; \
			sh*)     suffix=-sh ;; \
			sparc*)  suffix=-sparc ;; \
			x86)     suffix=-i386 ;; \
		esac ; \
		$$curdir/sbin/MAKEDEV generic$$suffix ; \
		$$curdir/sbin/MAKEDEV sg scd rtc hde hdf hdg hdh ; \
		$$curdir/sbin/MAKEDEV input audio video ; \
	)

basedev: basedev-$(KERNEL)

dev: dev-$(KERNEL)
	ln -snf ../sbin/MAKEDEV $(DEVDIR)/MAKEDEV

layout:
	# Create base filesytem layout
	for x in $(KEEP_DIRS) ; do \
		install -m 0755 -d $(DESTDIR)/$$x ; \
		touch $(DESTDIR)/$$x/.keep ; \
	done
	# Special dirs
	install -m 0700 -d $(DESTDIR)/root
	touch $(DESTDIR)/root/.keep
	install -m 1777 -d $(DESTDIR)/var/tmp
	touch $(DESTDIR)/var/tmp/.keep
	install -m 1777 -d $(DESTDIR)/tmp
	touch $(DESTDIR)/tmp/.keep
	# Needed log files
	install -m 0755 -d $(LOGDIR)
	touch $(LOGDIR)/lastlog
	install -m 0644 -g utmp /dev/null $(LOGDIR)/wtmp
	install -m 0755 -d $(RUNDIR)
	install -m 0664 -g utmp /dev/null $(RUNDIR)/utmp
	# FHS compatibility symlinks stuff
	ln -snf /var/tmp $(DESTDIR)/usr/tmp
	ln -snf share/man $(DESTDIR)/usr/local/man

install:
	# bin
	install -m 0755 -d $(BINDIR)
	for x in `ls bin` ; do \
		install -m 0755 "bin/$$x" $(BINDIR) ; \
	done
	# sbin
	install -m 0755 -d $(SBINDIR)
	install -m 0644 sbin/functions.sh $(SBINDIR)
	for x in depscan.sh env-update.sh runscript.sh rc rc-update \
		modules-update MAKEDEV ; do \
		install -m 0755 "sbin/$$x" $(SBINDIR) ; \
	done
	# lib
	install -m 0755 -d $(SHDIR)
	for x in $(SBINTOLIB) ; do \
		n=`echo $$x | sed -e 's/\.$(KERNEL)//'` ; \
		install -m 0644 "sbin/$$x" $(SHDIR)/$$n ; \
	done
	# awk
	install -m 0755 -d $(AWKDIR)
	for x in `ls src/awk` ; do \
		install -m 0644 "src/awk/$$x" $(AWKDIR) ; \
		if test $(LIB) != "lib" ; then \
			sed -i -e 's:/lib/rcscripts:/'$(LIB)'/rcscripts:' $(AWKDIR)/$$x ; \
		fi ; \
	done
	# init.d
	install -m 0755 -d $(INITDIR)
	for x in `ls init.d` ; do \
		install -m 0755 "init.d/$$x" $(INITDIR) ; \
	done
	# Create our symlinks
	for x in depscan.sh functions.sh runscript.sh ; do \
		ln -snf ../../sbin/"$$x" $(INITDIR)/"$$x" ; \
	done
	# etc
	# Assume that everything is a flat layout
	for x in `ls -R etc` ; do \
		if test `echo "$$x" | sed -e 's/.*\(.\)$$/\1/'` = ":" ; then \
			d=`echo "$$x" | sed -e 's/\(.*\).$$/\1/'` ; \
			install -m 0755 -d $(DESTDIR)/"$$d" ; \
		elif test -f "$$d/$$x" ; then \
			skip=0 ; \
			for y in $(ETC_SKIP) ; do \
				if test "$$d/$$x" = "etc/$$y" ; then \
					if test -f $(ROOT)/$$d/$$x ; then \
						skip=1 ; \
						break ; \
					fi ; \
				fi ; \
			done ; \
			if test $$skip -eq 0 ; then \
				m=0644 ; \
				if test "$$d/$$x" = "etc/shadow" ; then \
					m=0600 ; \
				elif test "$$d/$$x" = "/etc/sysctl.conf" ; then \
					m=0640 ; \
				fi ; \
				install -m $$m "$$d/$$x" $(DESTDIR)/"$$d/$$x" ; \
			fi ; \
		fi; \
	done
	# net scripts
	install -m 0755 net-scripts/init.d/net.lo $(INITDIR)
	ln -snf net.lo $(INITDIR)/net.eth0
	for x in `ls net-scripts/conf.d` ; do \
		install -m 0644 net-scripts/conf.d/"$$x" $(DESTDIR)/etc/conf.d ; \
	done
	install -m 0755 -d $(NETDIR)
	for x in `ls net-scripts/net` ; do \
		install -m 0644 net-scripts/net/"$$x" $(NETDIR) ; \
	done
	# Wang our man pages in
	for x in `ls man` ; do \
		d=`echo "$$x" | sed -e 's/.*\.\([0-9]\+\)$$/\1/'` ; \
		install -m 0755 -d $(MANDIR)/man"$$d" ; \
		install -m 0644 man/"$$x" $(MANDIR)/man"$$d" ; \
	done
	# Populate our runlevel folders
	if ! test -d $(ROOT)/etc/runlevels/boot ; then \
		install -m 0755 -d $(LVLDIR)/boot ; \
		for x in $(BOOT_LEVEL) ; do \
			ln -snf ../../init.d/"$$x" $(LVLDIR)/boot/"$$x" ; \
		done ; \
	fi
	if ! test -d $(ROOT)/etc/runlevels/default ; then \
		install -m 0755 -d $(LVLDIR)/default ; \
		for x in $(DEFAULT_LEVEL) ; do \
			ln -snf ../../init.d/"$$x" $(LVLDIR)/default/"$$x" ; \
		done ; \
	fi
	# SPARC fixes
	# SPAC does not like stty, so we disable RC_INTERACTIVE which requires it
	# see Gentoo bug #104067.
	if test $(ARCH) = "sparc" ; then \
		sed -i -e  '/^KEYMAP=/s:us:sunkeymap:' $(DESTDIR)/etc/conf.d/keymaps ; \
		sed -i -e '/^RC_INTERACTIVE=/s:yes:no:' $(DESTDIR)/etc/conf.d/rc ; \
	fi
	# Now install our supporting utilities
	for x in $(SUBDIRS) ; do \
		cd $$x ; \
		$(MAKE) install ; \
	done

distcheck:
	svnfiles=`svn status 2>&1 | egrep -v '^(U|P)'` ; \
	if test "x$$svnfiles" != "x" ; then \
		echo "Refusing to package tarball until svn is in sync:" ; \
		echo "$$svnfiles" ; \
		echo "make distforce to force packaging" ; \
		exit 1 ; \
	fi 

distforce: clean
	install -d /tmp/$(PKG)
	cp -axr . /tmp/$(PKG)
	cd /tmp/$(PKG) ; \
	rm -rf *.sh rc-lists `find . -iname .svn` sbin/MAKEDEV-gentoo.patch \
		src/core ; \
	cd .. ; \
	tar -cvjpf $(PKG).tar.bz2 $(PKG)
	rm -rf /tmp/$(PKG)
	du /tmp/$(PKG).tar.bz2

dist: distcheck	distforce

# vim: set ts=4 :
