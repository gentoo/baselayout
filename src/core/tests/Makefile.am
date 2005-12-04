INCLUDES = -I$(top_srcdir)

LIBRCSCRIPTS = $(top_builddir)/librcscripts/librcscripts.la

TESTS = test-regex test-dynbuf

noinst_PROGRAMS = \
	test-runlevels \
	$(TESTS)

test_dynbuf_LDADD = $(LIBRCSCRIPTS)
test_dynbuf_SOURCES = test-dynbuf.c

test_regex_LDADD = $(LIBRCSCRIPTS)
test_regex_SOURCES = test-regex.c

test_runlevels_LDADD = $(LIBRCSCRIPTS)
test_runlevels_SOURCES = test-runlevels.c
