# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

BEGIN {

	extension("/lib/rcscripts/filefuncs.so", "dlload")

	NAME = 1
	NEED = 2
	USE = 3
	BEFORE = 4
	AFTER = 5
	PROVIDE = 6

	TYPENAMES[NEED] = "need"
	TYPENAMES[USE] = "use"
	TYPENAMES[BEFORE] = "before"
	TYPENAMES[AFTER] = "after"
	TYPENAMES[PROVIDE] = "provide"

	if (!isdir(SVCDIR))
		if (!mktree(SVCDIR, 0755)) {
			
			eerror("Could not create needed directories!")
			exit 1
		}

	svcdirs = "softscripts snapshot options broken started provide "
	svcdirs = svcdirs " " DEPTYPES " " ORDTYPES

	split (svcdirs, svcdirnodes)

	for (x in svcdirnodes) {

		if (!isdir(SVCDIR "/" svcdirnodes[x])) {

			if (!mktree(SVCDIR "/" svcdirnodes[x], 0755)) {
			
				eerror("Could not create needed directories!")
				exit 1
			}
		}
	}

	# Cleanup and fix a problem with 'for x in foo/*' if foo/ is empty
	system("rm -rf " SVCDIR "/need/*")
	system("rm -rf " SVCDIR "/use/*")
	system("rm -rf " SVCDIR "/before/*")
	system("rm -rf " SVCDIR "/after/*")
	system("rm -rf " SVCDIR "/broken/*")
	system("rm -rf " SVCDIR "/provide/*")
}

{
	if ($1 == "RCSCRIPT") {
		RCNUMBER++

		DEPTREE[RCNUMBER,NAME] = $2
	}

	if ($1 == "NEED") {
		sub(/NEED[[:space:]]*/, "")

		if ($0 != "")
			DEPTREE[RCNUMBER,NEED] = $0
	}

	if ($1 == "USE") {
		sub(/USE[[:space:]]*/, "")

		if ($0 != "")
			DEPTREE[RCNUMBER,USE] = $0
	}

	if ($1 == "BEFORE") {
		sub(/BEFORE[[:space:]]*/, "")

		if ($0 != "")
			DEPTREE[RCNUMBER,BEFORE] = $0
	}

	if ($1 == "AFTER") {
		sub(/AFTER[[:space:]]*/, "")

		if ($0 != "")
			DEPTREE[RCNUMBER,AFTER] = $0
	}

	if ($1 == "PROVIDE") {
		sub(/PROVIDE[[:space:]]*/, "")

		if ($0 != "")
			DEPTREE[RCNUMBER,PROVIDE] = $0
	}
}

function check_service(name, 	x)
{
	for (x = 1;x <= RCNUMBER;x++) {
		if (DEPTREE[x,NAME] == name)
			return 1
	}

	return 0
}

function depend_dbadd(type, service, deplist, 	x, deparray)
{
	deparray[1] = 1

	if ((type == "") || (service == "") || (deplist == ""))
		return

	if (!check_service(service))
		return
	
	split(deplist, deparray, " ")
	
	for (x in deparray) {
	
		# Handle 'need', as it is the only dependency type that
		# should handle invalid database entries currently.  The only
		# other type of interest is 'pretend' which *should* add
		# invalid database entries (no virtual depend should ever
		# actually have a matching rc-script).
		if (!check_service(deparray[x])) {
			
			if ((type == NEED) && (deparray[x] != "net") && 
			    (!isdir(SVCDIR "/provide/" deparray[x]))) {

				ewarn("NEED:  can't find service \"" deparray[x] "\" needed by \"" service "\";")
				ewarn("       continuing...")

				# service is broken due to missing 'need' dependancies
				if (!isdir(SVCDIR "/broken/" service))
					assert(mktree(SVCDIR "/broken/" service, 0755),
					       "mktree(" SVCDIR "/broken/" service ", 0755)")
				if (!isfile(SVCDIR "/broken/" service "/" deparray[x]))
					system("touch " SVCDIR "/broken/" service "/" deparray[x])

				continue
			}
			else if ((type != PROVIDE) && (deparray[x] != "net") &&
			         (!isdir(SVCDIR "/provide/" deparray[x])))
				continue
		}

		# Ugly bug ... if a service depends on itself, it creates
		# a 'mini fork bomb' effect, and breaks things...
		if (deparray[x] == service) {
		
			# Dont work too well with the '*' use and need
			if ((type != BEFORE) && (type != AFTER)) {
				ewarn("DEPEND:  service \"" deparray[x] "\" can't depend on itself;")
				ewarn("         continuing...")
			}

			continue
		}

		# NEED and USE override BEFORE and AFTER
		if ((((type == BEFORE) && (!islink(SVCDIR "/need/" deparray[x] "/" service))) &&
		     ((type == BEFORE) && (!islink(SVCDIR "/use/" deparray[x] "/" service)))) ||
		    (((type == AFTER) && (!islink(SVCDIR "/need/" service "/" deparray[x]))) &&
		     ((type == AFTER) && (!islink(SVCDIR "/use/" service "/" deparray[x])))) ||
		    ((type == NEED) || (type == USE) || (type == PROVIDE))) {

			if (!isdir(SVCDIR "/" TYPENAMES[type] "/" deparray[x]))
				assert(mktree(SVCDIR "/" TYPENAMES[type] "/" deparray[x], 0755),
				       "mktree(" SVCDIR "/" TYPENAMES[type] "/" deparray[x] ", 0755)")
			if (!islink(SVCDIR "/" TYPENAMES[type] "/" deparray[x] "/" service))
				assert(dosymlink("/etc/init.d/" service, SVCDIR "/" TYPENAMES[type] "/" deparray[x] "/" service),
				       "dosymlink(/etc/init.d/" service ", " SVCDIR "/" TYPENAMES[type] "/" deparray[x] "/" service")")
		}
	}
}

END {
	# Calculate all the provides ...
	for (x = 1;x <= RCNUMBER;x++) {
	
		if ((x,PROVIDE) in DEPTREE)
			depend_dbadd(PROVIDE, DEPTREE[x,NAME], DEPTREE[x,PROVIDE])
	}

	# Now do NEED and USE
	for (x = 1; x <= RCNUMBER;x++) {
	
		if ((x,NEED) in DEPTREE)
			depend_dbadd(NEED, DEPTREE[x,NAME], DEPTREE[x,NEED])

		if ((x,USE) in DEPTREE)
			depend_dbadd(USE, DEPTREE[x,NAME], DEPTREE[x,USE])
	}

	# Now do BEFORE and AFTER (we do them in a seperate cycle to
	# so that we can check for NEED or USE)
	for (x = 1; x <= RCNUMBER;x++) {
	
		if ((x,BEFORE) in DEPTREE) {

			depend_dbadd(BEFORE, DEPTREE[x,NAME], DEPTREE[x,BEFORE])

			split(DEPTREE[x,BEFORE], tmpsplit)

			# Reverse mapping
			for (y in tmpsplit)
				depend_dbadd(AFTER, tmpsplit[y], DEPTREE[x,NAME])
		}

		if ((x,AFTER) in DEPTREE) {

			depend_dbadd(AFTER, DEPTREE[x,NAME], DEPTREE[x,AFTER])

			split(DEPTREE[x,AFTER], tmpsplit)

			# Reverse mapping
			for (y in tmpsplit)
				depend_dbadd(BEFORE, tmpsplit[y], DEPTREE[x,NAME])
		}
	}

	# Lastly resolve provides
	dblprovide = 0
	for (x = 1; x <= RCNUMBER;x++) {

		if ((x,PROVIDE) in DEPTREE) {

			split(DEPTREE[x,PROVIDE], providesplit)

			for (y in providesplit) {

				split(DEPTYPES, typesplit)

				for (z in typesplit) {

					if (isdir(SVCDIR "/" typesplit[z] "/" providesplit[y])) {

						deps = ""
						
						pipe = "ls " SVCDIR "/" typesplit[z] "/" providesplit[y]
						while ((pipe | getline tmpstring) > 0)
							deps = deps " " tmpstring
						close(pipe)

						split(deps, depsplit)

						for (i in depsplit) {

							provides = ""
						
							pipe = "ls " SVCDIR "/provide/" providesplit[y]
							while ((pipe | getline tmpstring) > 0)
								provides = provides " " tmpstring
							close(pipe)

							for (j = 1; j <= 6; j++)
								if (TYPENAMES[j] == typesplit[z])
									depend_dbadd(j, depsplit[i], provides)
						}

						system("rm -rf " SVCDIR "/" typesplit[z] "/" providesplit[y])
					}
				}

				counter = 0
				provides = ""
				
				pipe = "ls " SVCDIR "/provide/" providesplit[y]
				while ((pipe | getline tmpstring) > 0)
					provides = provides " " tmpstring
				close(pipe)

				split(provides, tmpprovidesplit)

				for (i in tmpprovidesplit)
					counter++

				if ((counter > 1) && (providesplit[y] != "net")) {

					dblprovide = 1
					errstring = providesplit[y]
				}
			}
		}
	}

	if (dblprovide) {

		ewarn("PROVIDE:  it usually is not a good idea to have more than one")
		ewarn("          service provide the same virtual service (" errstring ")!")
	}
}


# vim:ts=4
