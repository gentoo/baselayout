INCLUDES = \
	-I$(top_srcdir)         \
	-I$(top_srcdir)/include

LIBRCUTIL = $(top_builddir)/librcutil/librcutil.la
LIBRCSCRIPTS = $(top_builddir)/librcscripts/librcscripts.la

TESTS = \
	test-dynbuf \
	test-mmap   \
	test-regex

noinst_PROGRAMS = \
	test-runlevels \
	$(TESTS)

test_dynbuf_LDADD = $(LIBRCUTIL)
test_dynbuf_SOURCES = test-dynbuf.c

test_mmap_LDADD = $(LIBRCUTIL)
test_mmap_SOURCES = test-mmap.c

test_regex_LDADD = $(LIBRCUTIL)
test_regex_SOURCES = test-regex.c

test_runlevels_LDADD = $(LIBRCSCRIPTS)
test_runlevels_SOURCES = test-runlevels.c
