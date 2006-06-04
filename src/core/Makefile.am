AUTOMAKE_OPTIONS = dist-bzip2 no-dist-gzip

SUBDIRS = \
	data      \
	scripts   \
	include   \
	librcutil \
	librccore \
	src       \
	tests

EXTRA_DIST = \
	autogen.sh  \
	ChangeLog.0

librccore: librcutil
src: librcutil librccore
tests: librcutil librccore
