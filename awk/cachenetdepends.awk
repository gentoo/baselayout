# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

function print_start() {
	print ". /sbin/functions.sh" >> TMPCACHE
	print "" >> TMPCACHE
	print "before() {" >> TMPCACHE
	print "	echo \"BEFORE $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
	print "after() {" >> TMPCACHE
	print "	echo \"AFTER $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
	print "provide() {" >> TMPCACHE
	print "	echo \"PROVIDE $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "variables() {" >> TMPCACHE
	print "	echo \"VARIABLES $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "functions() {" >> TMPCACHE
	print "	echo \"FUNCTIONS $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "installed() {" >> TMPCACHE
	print "	echo \"INSTALLED $*\"; return 0" >> TMPCACHE
	print "}" >> TMPCACHE
	print "" >> TMPCACHE
}

function print_header1() {
	print "#*** " MYFILENAME " ***" >> TMPCACHE
	print "" >> TMPCACHE
	print "SVCNAME=\"" MYFILENAME "\"" >> TMPCACHE
	print "SVCNAME=\"${SVCNAME##*/}\"" >> TMPCACHE
	print "SVCNAME=\"${SVCNAME%.sh*}\"" >> TMPCACHE

	print "echo \"RCSCRIPT ${SVCNAME}\"" >> TMPCACHE
	print "" >> TMPCACHE
}

function print_header2() {
	print "(" >> TMPCACHE
	print "  depend() {" >> TMPCACHE
	print "    return 0" >> TMPCACHE
	print "  }" >> TMPCACHE
	print "" >> TMPCACHE
}

function print_end() {
	print "" >> TMPCACHE
	print "  depend" >> TMPCACHE
	print ")" >> TMPCACHE
	print "" >> TMPCACHE
}

BEGIN {
	# Get our environment variables
	SVCDIR = ENVIRON["SVCDIR"]
	if (SVCDIR == "") {
		eerror("Could not get SVCDIR!")
		exit 1
	}

	SVCLIB = ENVIRON["SVCLIB"]
	if (SVCLIB == "") {
		eerror("Could not get SVCLIB!")
		exit 1
	}

	# Since this could be called more than once simultaneously, use a
	# temporary cache and rename when finished.  See bug 47111
	("echo -n \"${SVCDIR}/netdepcache.$$\"") | getline TMPCACHE
	if (TMPCACHE == "") {
		eerror("Failed to create temporary cache!")
		exit 1
	}

	pipe = "ls "SVCLIB"/net/*.sh"
	while ((pipe | getline tmpstring) > 0)
		scripts = scripts " " tmpstring
	close(pipe)

	split(scripts, TMPRCSCRIPTS)

	# Make sure that its a file we are working with,
	# and do not process scripts, source or backup files.
	for (x in TMPRCSCRIPTS)
		if (isfile(TMPRCSCRIPTS[x]) || islink(TMPRCSCRIPTS[x])) {
			RCCOUNT++
			RCSCRIPTS[RCCOUNT] = TMPRCSCRIPTS[x]
		}

	if (RCCOUNT == 0) {
		eerror("No scripts to process!")
		dosystem("rm -f "TMPCACHE)
		exit 1
	}

	print_start()

	for (count = 1;count <= RCCOUNT;count++) {
		
		GOTDEPEND = 0
		MYFILENAME = RCSCRIPTS[count]
		print_header1()
		COUNT = 0
		SBCOUNT = 0
		LC = 0

		while (((getline < (RCSCRIPTS[count])) > 0) && (!NEXTFILE)) {

			# Filter out comments and only process if its a rcscript
			if ($0 ~ /^[[:space:]]*#/)
				continue
				
			# If line contain 'depend()', set GOTDEPEND to 1
			if ($0 ~ /depend[[:space:]]*\(\)/) {

				GOTDEPEND = 1

				print_header2()
				print "  # Actual depend() function ..." >> TMPCACHE
			}
	
			# We have the depend function...
			if (!GOTDEPEND)
				continue

			# Basic theory is that COUNT will be 0 when we
			# have matching '{' and '}'
			COUNT += gsub(/{/, "{")
			COUNT -= gsub(/}/, "}")

			# This is just to verify that we have started with
			# the body of depend()
			SBCOUNT += gsub(/{/, "{")

			# Make sure depend() contain something, else bash
			# errors out (empty function).
			if ((SBCOUNT > 0) && (COUNT == 0))
				print "  \treturn 0" >> TMPCACHE

			# Print the depend() function
			if (LC == 0)
				print "  depend() {" >> TMPCACHE
			else
				print "  " $0 >> TMPCACHE
			LC ++

			# If COUNT=0, and SBCOUNT>0, it means we have read
			# all matching '{' and '}' for depend(), so stop.
			if ((SBCOUNT > 0) && (COUNT == 0)) {
				NEXTFILE = 1
				print_end()
			}	
		}

		close(RCSCRIPTS[count])
		NEXTFILE = 0
	}

	assert(dosystem("rm -f "SVCDIR"/netdepcache"), "system(rm -f "SVCDIR"/netdepcache)")
	assert(dosystem("mv "TMPCACHE" "SVCDIR"/netdepcache"), "system(mv "TMPCACHE" "SVCDIR"/netdepcache)")
}

# vim: set ts=4 :
