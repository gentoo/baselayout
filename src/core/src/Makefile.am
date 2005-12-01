sbin_PROGRAMS = \
	depscan   \
	runscript

INCLUDES = $(RCSCRIPTS_DEFINES)

LIBRCSCRIPTS = $(top_builddir)/librcscripts/librcscripts.la

depscan_CFLAGS = -DLEGACY_DEPSCAN
depscan_LDADD = $(LIBRCSCRIPTS)
depscan_SOURCES = depscan.c

runscript_LDADD = $(LIBRCSCRIPTS) -ldl
runscript_SOURCES = runscript.c

