# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

BEGIN {

	extension("/lib/rcscripts/filefuncs.so", "dlload")

	DEPCACHE=SVCDIR "/depcache"

	unlink(DEPCACHE)

	print_start()
}

function print_start() {
	print "need() {" >> (DEPCACHE)
	print "	echo \"NEED $*\"; return 0" >> (DEPCACHE)
	print "}" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "use() {" >> (DEPCACHE)
	print "	echo \"USE $*\"; return 0" >> (DEPCACHE)
	print "}" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "before() {" >> (DEPCACHE)
	print "	echo \"BEFORE $*\"; return 0" >> (DEPCACHE)
	print "}" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "after() {" >> (DEPCACHE)
	print "	echo \"AFTER $*\"; return 0" >> (DEPCACHE)
	print "}" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "provide() {" >> (DEPCACHE)
	print "	echo \"PROVIDE $*\"; return 0" >> (DEPCACHE)
	print "}" >> (DEPCACHE)
	print "" >> (DEPCACHE)
}

function print_header() {
	print "#*** " FILENAME " ***" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "myservice=\"" FILENAME "\"" >> (DEPCACHE)
	print "myservice=\"${myservice##*/}\"" >> (DEPCACHE)
	print "echo \"RCSCRIPT ${myservice}\"" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "depend() {" >> (DEPCACHE)
	print " return 0" >> (DEPCACHE)
	print "}" >> (DEPCACHE)
	print "" >> (DEPCACHE)
}

function print_end() {
	print "" >> (DEPCACHE)
	print "depend" >> (DEPCACHE)
	print "" >> (DEPCACHE)
}

{
	# If line start with a '#' and is the first line
	if (($0 ~ /^[[:space:]]*#/) && (FNR == 1)) {
	
		# Remove any spaces and tabs
		gsub(/[[:space:]]+/, "")

		if ($0 == "#!/sbin/runscript") {
			ISRCSCRIPT = 1

			print_header()
		} else
			nextfile
	}

	# Filter out comments and only process if its a rcscript
	if (($0 !~ /[[:space:]]*#/) && (ISRCSCRIPT == 1 )) {

		# If line contain 'depend()', set GOTDEPEND to 1
		if ($0 ~ /depend[[:space:]]*\(\)/)
			GOTDEPEND = 1
	
		# We have the depend function...
		if (GOTDEPEND == 1) {

			# Basic theory is that COUNT will be 0 when we
			# have matching '{' and '}'
			COUNT += gsub(/{/, "{")
			COUNT -= gsub(/}/, "}")
		
			# This is just to verify that we have started with
			# the body of depend()
			SBCOUNT += gsub(/{/, "{")
		
			# Print the depend() function
			print >> (DEPCACHE)
		
			# If COUNT=0, and SBCOUNT>0, it means we have read
			# all matching '{' and '}' for depend(), so stop.
			if ((SBCOUNT > 0) && (COUNT == 0)) {

				GOTDEPEND = 0
				ISRCSCRIPT = 0
				COUNT = 0
				SBCOUNT = 0

				print_end()
			}
		}
	}
}

END {
	close (DEPCACHE)
}

