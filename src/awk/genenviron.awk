# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

BEGIN {

	extension("/lib/rcscripts/filefuncs.so", "dlload")

	pipe = "ls /etc/env.d/*"
	while ((pipe | getline tmpstring) > 0)
		scripts = scripts " " tmpstring
	close(pipe)

	split(scripts, TMPENVFILES)

	# Make sure that its a file we are working with,
	# and do not process scripts, source or backup files.
	for (x in TMPENVFILES)
		if ((isfile(TMPENVFILES[x])) &&
		    (TMPENVFILES[x] !~ /((\.(sh|c|bak))|\~)$/)) {

			ENVCOUNT++

			ENVFILES[ENVCOUNT] = TMPENVFILES[x]
		}

	ENVCACHE = SVCDIR "/envcache"
	SHPROFILE = "/etc/profile.env"
	CSHPROFILE = "/etc/csh.env"

	unlink(ENVCACHE)

	for (count = 1;count <= ENVCOUNT;count++) {
		
		while ((getline < (ENVFILES[count])) > 0) {

			# Filter out comments
			if ($0 !~ /[[:space:]]*#/) {

				split($0, envnode, "=")

				if (envnode[2] == "")
					continue

				if ($0 == "")
					continue

				# LDPATH should not be in environment
				if (envnode[1] == "LDPATH")
					continue

				# strip variable name and '=' from data
				sub(/.*=/, "")
				# Strip all '"' and '\''
				gsub(/\"/, "")
				gsub(/\'/, "")

				# KDEDIR and QTDIR should be handled specially
				if ((envnode[1] in ENVTREE) &&
				    ((envnode[1] != "KDEDIR") && (envnode[1] != "QTDIR")))
					ENVTREE[envnode[1]] = ENVTREE[envnode[1]] ":" $0
				else
					ENVTREE[envnode[1]] = $0
			}
		}

		close(ENVFILES[count])
	}

	for (x in ENVTREE)
		print "export " x "=\"" ENVTREE[x] "\"" >> (ENVCACHE)

	for (x in ENVTREE) {
	
		# Print this a second time to make sure all variables
		# are expanded ..
		print "export " x "=\"" ENVTREE[x] "\"" >> (ENVCACHE)
		print "echo \"" x "=${" x "}\"" >> (ENVCACHE)
	}

	close (ENVCACHE)

	unlink(SHPROFILE)
	unlink(CSHPROFILE)

	pipe = "bash " ENVCACHE
	while ((pipe | getline) > 0) {

		sub(/=/, "='")
		sub(/$/, "'")

		print "export " $0 >> (SHPROFILE)

		sub(/=/, " ")

		print "setenv " $0 >> (CSHPROFILE)
	}
	
	close(pipe)
	close(SHPROFILE)
	close(CSHPROFILE)
}


# vim:ts=4
