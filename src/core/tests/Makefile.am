INCLUDES = -I$(top_srcdir)

LIBRCSCRIPTS = $(top_builddir)/librcscripts/librcscripts.la

TESTS = \
	test-dynbuf \
	test-mmap   \
	test-regex

noinst_PROGRAMS = \
	test-runlevels \
	$(TESTS)

test_dynbuf_LDADD = $(LIBRCSCRIPTS)
test_dynbuf_SOURCES = test-dynbuf.c

test_mmap_LDADD = $(LIBRCSCRIPTS)
test_mmap_SOURCES = test-mmap.c

test_regex_LDADD = $(LIBRCSCRIPTS)
test_regex_SOURCES = test-regex.c

test_runlevels_LDADD = $(LIBRCSCRIPTS)
test_runlevels_SOURCES = test-runlevels.c
