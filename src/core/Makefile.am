AUTOMAKE_OPTIONS = dist-bzip2 no-dist-gzip

SUBDIRS = \
	data         \
	scripts      \
	include      \
	librcutil    \
	librcscripts \
	src          \
	tests

EXTRA_DIST = \
	autogen.sh  \
	ChangeLog.0

librcscripts: librcutil
src: librcutil librcscripts
tests: librcutil librcscripts
