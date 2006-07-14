AUTOMAKE_OPTIONS = dist-bzip2 no-dist-gzip

SUBDIRS = \
	data      \
	scripts   \
	include   \
	librcutil \
	librccore \
	src       \
	tests

if LIBNSS_SERVICE
SUBDIRS += libnss_service
endif

EXTRA_DIST = \
	autogen.sh  \
	ChangeLog.0

librccore: librcutil
libnss_service: librcutil librccore
src: librcutil librccore
tests: librcutil librccore
