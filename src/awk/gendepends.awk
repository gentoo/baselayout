# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

# bool check_service(name)
#
#   Returns true if the service exists
#
function check_service(name,    x)
{
	for (x = 1; x <= RCNUMBER; x++) {
		if (DEPTREE[x,NAME] == name)
			return 1
		else
			continue
	}

	return 0
}

# int get_service_position(name)
#
#   Return the index position in DEPTREE
#
function get_service_position(name,    x)
{
	for (x = 1; x <= RCNUMBER; x++) {
		if (DEPTREE[x,NAME] == name)
			return x
		else
			continue
	}

	return 0
}

# bool check_depend(service1, type, service2)
#
#   Returns true if 'service1' need/use/is_before/is_after 'service2'
#
function check_depend(service1, type, service2,    tmpsplit, x)
{
	if (get_service_position(service1)) {
		x = get_service_position(service1)

		if ((x,type) in DEPTREE) {
			split(DEPTREE[x,type], tmpsplit, " ")

			for (x in tmpsplit) {
				if (tmpsplit[x] == service2)
					return 1
			}
		}
	}

	return 0
}

# bool add_deptree_item(rcnumber, type, item)
#
#   Add an item(s) 'item' to the DEPTREE array at index [rcnumber,type]
#
function add_deptree_item(rcnumber, type, item)
{
	if (DEPTREE[rcnumber,type] != "")
		DEPTREE[rcnumber,type] = DEPTREE[rcnumber,type] " " item
	else
		DEPTREE[rcnumber,type] = item

	return 1
}

# bool add_provide(service, provide)
#
#   Add a name of a virtual service ('provide') that 'service' Provides
#
function add_provide(service, provide)
{
	# We cannot have a service Provide a virtual service with the same name as
	# an existing service ...
	if (check_service(provide)) {
		eerror(" Cannot add provide '" provide "', as a service with the same name exists!")
		return 0
	}
		
	if (check_provide(provide)) {
		# We cannot have more than one service Providing a virtual ...
		ewarn(" Service '" get_provide(provide) "' already provide '" provide "'!;")
		ewarn(" Not adding service '" service "'...")
	} else {
		# Sanity check
		if (check_service(service)) {
			PROVIDE_LIST[provide] = service
		} else {
			eerror(" Cannot add provide '" provide "', as service '" service "' do not exist!")
			return 0
		}
	}

	return 1
}

# string get_provide(provide)
#
#   Return the name of the service that Provides 'provide'
#
function get_provide(provide)
{
	if (provide in PROVIDE_LIST)
		if (check_service(PROVIDE_LIST[provide]))
			return PROVIDE_LIST[provide]
	
	return ""
}

# bool check_provide(provide)
#
#   Return true if any service Provides the virtual service with name 'provide'
#
function check_provide(provide)
{
	if (provide in PROVIDE_LIST)
		return 1
	
	return 0
}

# void depend_dbadd(type, service, deplist)
#
#   Add an DB entry(s) 'deplist' for service 'service' of type 'type'
#
function depend_dbadd(type, service, deplist,    x, deparray)
{
	if ((type == "") || (service == "") || (deplist == ""))
		return

	# If there are no existing service 'service', resolve possible
	# provided services
	if (!check_service(service)) {
		if (check_provide(service))
			service = get_provide(service)
		else
			return
	}

	split(deplist, deparray, " ")

	for (x in deparray) {

		# If there are no existing service 'deparray[x]', resolve possible
		# provided services
		if (!check_service(deparray[x])) {
			if (check_provide(deparray[x]))
				deparray[x] = get_provide(deparray[x])
		}

		# Handle 'need', as it is the only dependency type that
		# should handle invalid database entries currently.
		if (!check_service(deparray[x])) {

			if ((type == NEED) && (deparray[x] != "net")) {

				ewarn(" Can't find service '" deparray[x] "' needed by '" service "';  continuing...")

				# service is broken due to missing 'need' dependencies
				if (!isdir(SVCDIR "/broken/" service))
					assert(mktree(SVCDIR "/broken/" service, 0755),
					       "mktree(" SVCDIR "/broken/" service ", 0755)")
				if (!isfile(SVCDIR "/broken/" service "/" deparray[x]))
					assert(dosystem("touch " SVCDIR "/broken/" service "/" deparray[x]),
					       "system(touch " SVCDIR "/broken/" service "/" deparray[x] ")")

				continue
			}
			else if (deparray[x] != "net")
				continue
		}

		# Ugly bug ... if a service depends on itself, it creates
		# a 'mini fork bomb' effect, and breaks things...
		if (deparray[x] == service) {

			# Dont work too well with the '*' use and need
			if ((type != BEFORE) && (type != AFTER))
				ewarn(" Service '" deparray[x] "' can't depend on itself;  continuing...")

			continue
		}

		# Currently only these depend/order types are supported
		if ((type == NEED) || (type == USE) || (type == BEFORE) || (type == AFTER)) {
	
			if (type == BEFORE) {
				# NEED and USE override BEFORE (service BEFORE deparray[x])
				if (check_depend(service, NEED, deparray[x]) ||
				    check_depend(service, USE, deparray[x]))
					continue

				# Do not all circular ordering
				if (check_depend(service, AFTER, deparray[x]))
					continue
			}
			
			if (type == AFTER) {
				# NEED and USE override AFTER (service AFTER deparray[x])
				if (check_depend(deparray[x], NEED, service) ||
				    check_depend(deparray[x], USE, service))
					continue
				
				# Do not all circular ordering
				if (check_depend(service, BEFORE, deparray[x]))
					continue
			}

			# NEED override USE (service USE deparray[x])
			if ((type == USE) && (check_depend(deparray[x], NEED, service))) {
				ewarn(" Service '" deparray[x] "' NEED service '" service "', but service '" service "' wants")
				ewarn(" to USE service '" deparray[x] "'!")
				continue
			}

			# Ok, add our db entry ...
			if (!isdir(SVCDIR "/" TYPENAMES[type] "/" deparray[x]))
				assert(mktree(SVCDIR "/" TYPENAMES[type] "/" deparray[x], 0755),
				       "mktree(" SVCDIR "/" TYPENAMES[type] "/" deparray[x] ", 0755)")
			if (!islink(SVCDIR "/" TYPENAMES[type] "/" deparray[x] "/" service))
				assert(dosymlink("/etc/init.d/" service, SVCDIR "/" TYPENAMES[type] "/" deparray[x] "/" service),
				       "dosymlink(/etc/init.d/" service ", " SVCDIR "/" TYPENAMES[type] "/" deparray[x] "/" service")")
		}
	}
}

BEGIN {

	extension("/lib/rcscripts/filefuncs.so", "dlload")

	NAME = 1
	NEED = 2
	USE = 3
	BEFORE = 4
	AFTER = 5
	PROVIDE = 6
	RCNUMBER = 0

	TYPENAMES[NEED] = "need"
	TYPENAMES[USE] = "use"
	TYPENAMES[BEFORE] = "before"
	TYPENAMES[AFTER] = "after"
	TYPENAMES[PROVIDE] = "provide"

	if (!isdir(SVCDIR))
		if (!mktree(SVCDIR, 0755)) {
			
			eerror(" Could not create needed directories!")
			exit 1
		}

	svcdirs = "softscripts snapshot options broken started"
	svcdirs = svcdirs " " DEPTYPES " " ORDTYPES

	split (svcdirs, svcdirnodes)

	for (x in svcdirnodes) {

		if (!isdir(SVCDIR "/" svcdirnodes[x])) {

			if (!mktree(SVCDIR "/" svcdirnodes[x], 0755)) {
			
				eerror(" Could not create needed directories!")
				exit 1
			}
		}
	}

	# Cleanup and fix a problem with 'for x in foo/*' if foo/ is empty
	system("rm -rf " SVCDIR "/{need,use,before,after,broken}/*")
}

{
	#
	# Build our DEPTREE array
	#
	
	if ($1 == "RCSCRIPT") {
		RCNUMBER++

		DEPTREE[RCNUMBER,NAME] = $2
	}

	if ($1 == "NEED") {
		sub(/NEED[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RCNUMBER, NEED, $0)
	}

	if ($1 == "USE") {
		sub(/USE[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RCNUMBER, USE, $0)
	}

	if ($1 == "BEFORE") {
		sub(/BEFORE[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RCNUMBER, BEFORE, $0)
	}

	if ($1 == "AFTER") {
		sub(/AFTER[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RCNUMBER, AFTER, $0)
	}

	if ($1 == "PROVIDE") {
		sub(/PROVIDE[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RCNUMBER, PROVIDE, $0)
	}
}

END {
	# Calculate all the provides ...
	for (x = 1;x <= RCNUMBER;x++) {

		if ((x,PROVIDE) in DEPTREE)
			add_provide(DEPTREE[x,NAME], DEPTREE[x,PROVIDE])
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
}


# vim:ts=4
