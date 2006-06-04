sbin_PROGRAMS = \
	depscan   \
	runscript

INCLUDES = \
	-I$(top_srcdir)         \
	-I$(top_srcdir)/include \
	$(RCSCRIPTS_DEFINES)

LIBRCUTIL = $(top_builddir)/librcutil/librcutil.la
LIBRCSCRIPTS = $(top_builddir)/librcscripts/librcscripts.la

depscan_CFLAGS = -DLEGACY_DEPSCAN
depscan_LDADD = $(LIBRCSCRIPTS)
depscan_SOURCES = depscan.c

runscript_LDADD = $(LIBRCUTIL) -ldl
runscript_SOURCES = runscript.c

