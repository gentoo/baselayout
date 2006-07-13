AUTOMAKE_OPTIONS = foreign

INCLUDES = \
	-I$(top_srcdir)           \
	-I$(top_srcdir)/include   \
	-I$(top_builddir)/include

LIBRCCORE = $(top_builddir)/librccore/librccore.la

EXTRA_DIST = README nss_service.conf

librccore_a_LIBADD = $(LIBRCUTIL)

#bin_PROGRAMS = libnss_service.so
lib_LTLIBRARIES = libnss_service.la 

libnss_service_la_LIBADD = $(LIBRCCORE)
libnss_service_la_SOURCES = 	\
	nss_service.c		\
	nss_service.h		\
	service-alias.c		\
	service-automount.c	\
	service-ethers.h	\
	service-ethers.c	\
	service-grp.c 		\
	service-hosts.c		\
	service-netgrp.h	\
	service-netgrp.c	\
	service-network.c	\
	service-proto.c		\
	service-pwd.c		\
	service-rpc.c		\
	service-service.c

LIBC_VERS = `ls /lib/libc-*.so | tail -n 1 | sed -e 's,/lib/libc-\(.*\)\.so,\1,'`
NSS_SERVICE_LIBC_VERSIONED = libnss_service-$(LIBC_VERS).so
NSS_VERS = `ls /lib/libnss_files.so.? | tail -n 1 | sed -e 's,/lib/libnss_files\.so\.\(.*\),\1,'`
NSS_SERVICE_NSS_VERSIONED = libnss_service.so.$(NSS_VERS)

install-exec-local:
	$(mkinstalldirs) $(DESTDIR)$(libdir)
	-rm -f $(DESTDIR)$(libdir)/$(NSS_SERVICE_LIBC_VERSIONED)
	$(INSTALL_PROGRAM) .libs/libnss_service.so $(DESTDIR)$(libdir)/$(NSS_SERVICE_LIBC_VERSIONED)
	ln -sf $(NSS_SERVICE_LIBC_VERSIONED) $(DESTDIR)$(libdir)/$(NSS_SERVICE_NSS_VERSIONED)
	$(mkinstalldirs) $(DESTDIR)$(prefix)/usr/lib
	ln -sf ../../lib/$(NSS_SERVICE_NSS_VERSIONED) $(DESTDIR)$(prefix)/usr/lib

install-data-local:
	$(mkinstalldirs) $(DESTDIR)$(sysconfdir)
	$(INSTALL_DATA) nss_service.conf $(DESTDIR)$(sysconfdir)

uninstall-local:
	rm -f $(DESTDIR)$(libdir)/$(NSS_SERVICE_LIBC_VERSIONED)
	rm -f $(DESTDIR)$(libdir)/$(NSS_SERVICE_NSS_VERSIONED)
	rm -f $(DESTDIR)$(prefix)/usr/lib/$(NSS_SERVICE_NSS_VERSIONED)

install: install-exec-local install-data-local
