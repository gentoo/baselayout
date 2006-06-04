sbin_PROGRAMS = \
	depscan   \
	runscript

INCLUDES = \
	-I$(top_srcdir)           \
	-I$(top_srcdir)/include   \
	-I$(top_srcdir)/librccore \
	-I$(top_builddir)/include \
	$(RCSCRIPTS_DEFINES)

LIBRCUTIL = $(top_builddir)/librcutil/librcutil.la
LIBRCCORE = $(top_builddir)/librccore/librccore.la

depscan_CFLAGS = -DLEGACY_DEPSCAN
depscan_LDADD = $(LIBRCCORE)
depscan_SOURCES = depscan.c

runscript_LDADD = $(LIBRCUTIL) -ldl
runscript_SOURCES = runscript.c

