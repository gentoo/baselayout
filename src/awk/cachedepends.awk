# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

function print_start() {
	print "source /sbin/functions.sh" 
	print "" 
	print "need() {" 
	print "	echo \"NEED $*\"; return 0" 
	print "}" 
	print "" 
	print "use() {" 
	print "	echo \"USE $*\"; return 0" 
	print "}" 
	print "" 
	print "before() {" 
	print "	echo \"BEFORE $*\"; return 0" 
	print "}" 
	print "" 
	print "after() {" 
	print "	echo \"AFTER $*\"; return 0" 
	print "}" 
	print "" 
	print "provide() {" 
	print "	echo \"PROVIDE $*\"; return 0" 
	print "}" 
	print "" 
	print "parallel() {"
	print "	echo \"PARALLEL $*\"; return 0"
	print "}"
	print ""
}

function print_header1() {
	print "#*** " MYFILENAME " ***" 
	print "" 
	print "myservice=\"" MYFILENAME "\"" 
	print "myservice=\"${myservice##*/}\"" 
	print "echo \"RCSCRIPT ${myservice}\"" 
	print "" 
}

function print_header2() {
	print "(" 
	print "  # Get settings for rc-script ..." 
	print "  [ -e /etc/conf.d/basic ]                 && source /etc/conf.d/basic" 
	print "" 
	print "  [ -e \"/etc/conf.d/${myservice}\" ]        && source \"/etc/conf.d/${myservice}\"" 
	print "" 
	print "  [ -e /etc/conf.d/net ]                   && \\" 
	print "  [ \"${myservice%%.*}\" = \"net\" ]           && \\" 
	print "  [ \"${myservice##*.}\" != \"${myservice}\" ] && source /etc/conf.d/net" 
	print "" 
	print "  [ -e /etc/rc.conf ]                      && source /etc/rc.conf" 
	print "" 
	print "  depend() {" 
	print "    return 0" 
	print "  }" 
	print "" 
}

function print_end() {
	print "" 
	print "  depend" 
	print ")" 
	print "" 
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

	if (RCCOUNT == 0) {
		eerror("No scripts to process!")
		exit 1
	}

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
					print_header1()
				} else  {
			
					NEXTFILE = 1
					continue
				}
			}

			# Filter out comments and only process if its a rcscript
			if (($0 !~ /^[[:space:]]*#/) && (ISRCSCRIPT)) {

				# If line contain 'depend()', set GOTDEPEND to 1
				if ($0 ~ /depend[[:space:]]*\(\)/) {
				
					GOTDEPEND = 1

					print_header2()
					print "  # Actual depend() function ..." 
				}
	
				# We have the depend function...
				if (GOTDEPEND) {

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
						print "  \treturn 0"
		
					# Print the depend() function
					print "  " $0 
		
					# If COUNT=0, and SBCOUNT>0, it means we have read
					# all matching '{' and '}' for depend(), so stop.
					if ((SBCOUNT > 0) && (COUNT == 0)) {

						GOTDEPEND = 0
						COUNT = 0
						SBCOUNT = 0
						ISRCSCRIPT = 0

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
}


# vim:ts=4
