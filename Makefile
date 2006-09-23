# baselayout Makefile
# Copyright (c) 2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# Contributed by Roy Marples (uberlord@gentoo.org)
#
# We've moved the installation logic from Gentoo ebuild into a generic
# Makefile so that the ebuild is much smaller and more simple.
# It also has the added bonus of being easier to install on systems
# without an ebuild style package manager.

SUBDIRS = bin conf.d etc init.d man net sbin sh

NAME = baselayout
VERSION = 1.13.0_alpha1
PKG = $(NAME)-$(VERSION)

ARCH = x86
OS = Linux

ifeq ($(OS),Linux)
	NET_LO = net.lo
endif
ifneq ($(OS),Linux)
	NET_LO = net.lo0
endif

TOPDIR = .
include $(TOPDIR)/default.mk

install::
	ln -snf ../../$(LIB)/rcscripts/sh/net.sh $(DESTDIR)/etc/init.d/$(NET_LO)

.PHONY: all clean install

# vim: set ts=4 :
