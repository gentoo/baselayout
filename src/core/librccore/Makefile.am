AUTOMAKE_OPTIONS = foreign

INCLUDES = \
	-I$(top_srcdir)/include \
	$(RCSCRIPTS_DEFINES)

LIBRCUTIL = $(top_builddir)/librcutil/librcutil.la

lib_LTLIBRARIES = librccore.la

librccore_la_LIBADD = $(LIBRCUTIL)
librccore_la_SOURCES = \
	scripts.c       \
	api/scripts.h   \
	runlevels.c     \
	api/runlevels.h \
	parse.c         \
	api/parse.h     \
	depend.c        \
	api/depend.h
