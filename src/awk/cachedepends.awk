# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

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
	print "#*** " MYFILENAME " ***" >> (DEPCACHE)
	print "" >> (DEPCACHE)
	print "myservice=\"" MYFILENAME "\"" >> (DEPCACHE)
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

BEGIN {

	extension("/lib/rcscripts/filefuncs.so", "dlload")

	pipe = "ls /etc/init.d/*"
	while ((pipe | getline tmpstring) > 0)
		scripts = scripts " " tmpstring
	close(pipe)

	split(scripts, TMPRCSCRIPTS)

	# Make sure that its a file we are working with,
	# and do not process scripts, source or backup files.
	for (x in TMPRCSCRIPTS)
		if ((isfile(TMPRCSCRIPTS[x])) &&
		    (TMPRCSCRIPTS[x] !~ /((\.(sh|c|bak))|\~)$/)) {

			RCCOUNT++

			RCSCRIPTS[RCCOUNT] = TMPRCSCRIPTS[x]
		}

	DEPCACHE=SVCDIR "/depcache"

	unlink(DEPCACHE)

	print_start()

	for (count = 1;count <= RCCOUNT;count++) {
		
		MYFNR = 1
		MYFILENAME = RCSCRIPTS[count]

		while (((getline < (RCSCRIPTS[count])) > 0) && (!NEXTFILE)) {

			# If line start with a '#' and is the first line
			if (($0 ~ /^[[:space:]]*#/) && (MYFNR == 1)) {
	
				# Remove any spaces and tabs
				gsub(/[[:space:]]+/, "")

				if ($0 == "#!/sbin/runscript") {
				
					ISRCSCRIPT = 1
					print_header()
				} else  {
			
					NEXTFILE = 1
					continue
				}
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

						NEXTFILE = 1
						continue
					}
				}
			}

			MYFNR++
		}

		close(RCSCRIPTS[count])

		NEXTFILE = 0

	}

	close (DEPCACHE)
}


# vim:ts=4
