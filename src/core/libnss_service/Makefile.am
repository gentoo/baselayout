AUTOMAKE_OPTIONS = foreign

INCLUDES = \
	-I$(top_srcdir)           \
	-I$(top_srcdir)/include   \
	-I$(top_builddir)/include

LIBRCCORE = $(top_builddir)/librccore/librccore.la

lib_LTLIBRARIES = libnss_service.la 

libnss_service_la_LIBADD = $(LIBRCCORE)
libnss_service_la_LDFLAGS = -avoid-version -shrext .so.2
libnss_service_la_SOURCES = \
	nss_service.c       \
	nss_service.h       \
	service-alias.c	    \
	service-automount.c \
	service-ethers.h    \
	service-ethers.c    \
	service-grp.c       \
	service-hosts.c     \
	service-netgrp.h    \
	service-netgrp.c    \
	service-network.c   \
	service-proto.c     \
	service-pwd.c       \
	service-rpc.c       \
	service-service.c

confdir = $(sysconfdir)
dist_conf_DATA = nss_service.conf

install-exec-hook:
	-rm -f $(DESTDIR)$(libdir)/libnss_service.la

EXTRA_DIST = README

