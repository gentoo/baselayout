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
OS = Linux
DESTDIR =
ROOT = /
LIB = lib

DEVDIR = $(DESTDIR)/dev
BINDIR = $(DESTDIR)/bin
SBINDIR = $(DESTDIR)/sbin
LIBDIR = $(DESTDIR)/$(LIB)
INITDIR = $(DESTDIR)/etc/init.d
CONFDIR = $(DESTDIR)/etc/conf.d
MANDIR = $(DESTDIR)/usr/share/man
LOGDIR = $(DESTDIR)/var/log
RUNDIR = $(DESTDIR)/var/run

RCDIR = $(LIBDIR)/rcscripts
SHDIR = $(RCDIR)/sh
NETDIR= $(RCDIR)/net
AWKDIR = $(RCDIR)/awk
LVLDIR = $(DESTDIR)/etc/runlevels

# Default init scripts for the boot runlevel
BOOT_LEVEL = bootmisc checkroot checkfs clock hostname localmount \
	urandom 
# Default init scripts for the default runlevel
DEFAULT_LEVEL = local netmount

# Don't install these files if they already exist in ROOT
# Basically, don't hit the users key config files
ETC_SKIP = hosts passwd shadow group fstab

KEEP_DIRS = boot dev proc home \
	mnt/cdrom mnt/floppy \
	usr/local/bin usr/local/sbin usr/local/share/doc usr/local/share/man \
	var/run lib/rcscripts/init.d lib/rcscripts/tmp

SUBDIRS = src

SBINTOLIB = rc-daemon.sh rc-help.sh rc-services.sh \
	init.$(OS).sh init-functions.sh init-common-pre.sh init-common-post.sh

ifeq ($(OS),Linux)
BOOTLEVEL += consolefont keymaps modules rmnologin
NET_LO = net.lo
DEFAULT_LEVEL += hdparm
KEEP_DIRS += sys
endif
ifeq ($(OS),BSD)
BOOTLEVEL += sysctl syscons
NET_LO = net.lo0
endif
BOOT_LEVEL += $(NET_LO)

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

basedev-Linux:
	if ! test -d $(DEVDIR) ; then \
		install -m 0755 -d $(DEVDIR) ; \
	fi
	( curdir=`pwd` ; cd $(DEVDIR) ; \
		$$curdir/sbin/MAKEDEV generic-base ) 

dev-Linux:
	install -m 0755 -d $(DEVDIR)
	ln -snf ../sbin/MAKEDEV $(DEVDIR)/MAKEDEV \
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

basedev: basedev-$(OS)

dev: dev-$(OS)

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
	for x in `find bin -type f ! -path "*/.svn/*"` ; do \
		install -m 0755 "$$x" $(BINDIR) ; \
	done
	# sbin
	install -m 0755 -d $(SBINDIR)
	install -m 0644 sbin/functions.sh $(SBINDIR)
	for x in depscan.sh env-update.sh runscript.sh rc rc-update ; do \
		install -m 0755 "sbin/$$x" $(SBINDIR) ; \
	done
	if test $(OS) = "Linux" ; then \
		install -m 0755 sbin/modules-update $(SBINDIR) ; \
		install -m 0755 sbin/MAKEDEV $(SBINDIR) ; \
	fi
	# lib
	install -m 0755 -d $(SHDIR)
	for x in $(SBINTOLIB) ; do \
		n=`echo $$x | sed -e 's/\.$(OS)//'` ; \
		if test $$x = "rc-help.sh" ; then \
			install -m 0755 "sbin/$$x" $(SHDIR)/$$n ; \
		else \
			install -m 0644 "sbin/$$x" $(SHDIR)/$$n ; \
		fi \
	done
	# awk
	install -m 0755 -d $(AWKDIR)
	for x in `find src/awk -type f ! -path "*/.svn/*"` ; do \
		install -m 0644 "$$x" $(AWKDIR) ; \
		if test $(LIB) != "lib" ; then \
			sed -i -e 's:/lib/rcscripts:/'$(LIB)'/rcscripts:' $(AWKDIR)/$$x ; \
		fi ; \
	done
	# init.d
	install -m 0755 -d $(INITDIR)
	for x in `find init.d -type f ! -path "*/.svn/*"` ; do \
		install -m 0755 "$$x" $(INITDIR) ; \
	done
	# Create our symlinks
	for x in depscan.sh functions.sh runscript.sh ; do \
		ln -snf ../../sbin/"$$x" $(INITDIR)/"$$x" ; \
	done
	# init.d for OS
	if test -d init.d.$(OS) ; then \
		for x in `find init.d.$(OS) -type f ! -path "*/.svn/*"` ; do \
			install -m 0755 "$$x" $(INITDIR) ; \
		done \
	fi
	# conf.d
	install -m 0755 -d $(CONFDIR)
	for x in `find conf.d -type f ! -path "*/.svn/*"` ; do \
		install -m 0755 "$$x" $(CONFDIR) ; \
	done
	# conf.d for OS
	if test -d conf.d.$(OS) ; then \
		for x in `find conf.d.$(OS) -type f ! -path "*/.svn/*"` ; do \
			install -m 0755 "$$x" $(CONFDIR) ; \
		done \
	fi
	# etc
	# Assume that everything is a flat layout
	for x in `find etc ! -path "*.svn*"` ; do \
		f=`basename "$$x"` ; \
		if test -d "$$x" ; then \
			d="$$x" ; \
			install -m 0755 -d $(DESTDIR)/"$$d" ; \
		elif test -f "$$x" ; then \
			skip=0 ; \
			for y in $(ETC_SKIP) ; do \
				if test "$$d/$$f" = "etc/$$y" ; then \
					if test -f $(ROOT)/$$d/$$f ; then \
						skip=1 ; \
						break ; \
					fi ; \
				fi ; \
			done ; \
			if test $$skip -eq 0 ; then \
				install -m 0644 "$$x" $(DESTDIR)/"$$d/$$f" ; \
			fi ; \
		fi ; \
	done
	# etc for OS
	# Assume that everything is a flat layout
	for x in `find etc.$(OS) ! -path "*.svn*"` ; do \
		f=`basename "$$x"` ; \
		if test -d "$$x" ; then \
			d=`echo "$$x" | sed -e 's/^etc.$(OS)/etc/'` ; \
			install -m 0755 -d $(DESTDIR)/"$$d" ; \
		elif test -f "$$x" ; then \
			skip=0 ; \
			for y in $(ETC_SKIP) ; do \
				if test "$$d/$$f" = "etc/$$y" ; then \
					if test -f $(ROOT)/$$d/$$f ; then \
						skip=1 ; \
						break ; \
					fi ; \
				fi ; \
			done ; \
			if test $$skip -eq 0 ; then \
				m=0644 ; \
				if test "$$d/$$f" = "etc/shadow" ; then \
					m=0600 ; \
				elif test "$$d/$$f" = "/etc/sysctl.conf" ; then \
					m=0640 ; \
				fi ; \
				install -m $$m "$$x" $(DESTDIR)/"$$d/$$f" ; \
			fi ; \
		fi; \
	done
	# net scripts
	install -m 0755 net-scripts/init.d/net.lo $(SHDIR)/net.lo
	ln -snf ../../lib/rcscripts/sh/net.lo $(INITDIR)/$(NET_LO)
	for x in `find net-scripts/conf.d -type f ! -path "*/.svn/*"` ; do \
		install -m 0644 "$$x" $(DESTDIR)/etc/conf.d ; \
	done
	install -m 0755 -d $(NETDIR)
	for x in `find net-scripts/net -type f ! -path "*/.svn/*"` ; do \
		install -m 0644 "$$x" $(NETDIR) ; \
	done
	for x in `find net-scripts/net.$(OS) -type f ! -path "*/.svn/*"` ; do \
		install -m 0644 "$$x" $(NETDIR) ; \
	done
	# Wang our man pages in
	for x in `find man -type f ! -path "*/.svn/*"` ; do \
		d=`echo "$$x" | sed -e 's/.*\.\([0-9]*\)$$/\1/'` ; \
		install -m 0755 -d $(MANDIR)/man"$$d" ; \
		install -m 0644 "$$x" $(MANDIR)/man"$$d" ; \
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
	cp -PRp . /tmp/$(PKG)
	cd /tmp/$(PKG) ; \
	rm -rf *.sh rc-lists `find . -name .svn` sbin/MAKEDEV-gentoo.patch \
		src/core po ; \
	cd .. ; \
	tar -cvjpf $(PKG).tar.bz2 $(PKG)
	rm -Rf /tmp/$(PKG)
	du /tmp/$(PKG).tar.bz2

dist: distcheck	distforce

# vim: set ts=4 :
