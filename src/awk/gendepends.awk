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
	for (x = 1; x <= RC_NUMBER; x++) {
		if (DEPTREE[x,NAME] == name)
			return 1
	}

	return 0
}

# int get_service_index(name)
#
#   Return the index position in DEPTREE
#
function get_service_index(name,    x)
{
	for (x = 1; x <= RC_NUMBER; x++) {
		if (DEPTREE[x,NAME] == name)
			return x
	}

	return 0
}

# bool check_depend(service1, type, service2)
#
#   Returns true if 'service1' need/use/is_before/is_after 'service2'
#
function check_depend(service1, type, service2,    tmpsplit, x)
{
	if (check_service(service1)) {
		x = get_service_index(service1)

		if ((x,type) in DEPTREE) {
			split(DEPTREE[x,type], tmpsplit)

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
		# Do not fail here as we do have a service that resolves the virtual
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

# bool add_parallel(service, parallel)
#
#   Add 'yes' or 'no' to the parallel modifier of 'service'.
#
function add_parallel(service, parallel,    sindex)
{
	if ((parallel != "yes") && (parallel != "no")) {
		eerror(" The 'parallel' modifier can only take 'yes' or 'no' as argument!")
		eerror(" Please fix this in the '" service "' service.")
		return 0
	}
	
	if (check_service(service)) {
		sindex = get_service_index(service)
		
		RESOLVED_DEPTREE[sindex,PARALLEL] = parallel

		return 1
	} else
		eerror(" Service '" service "' do not exist!")

	return 0
}

# bool add_db_entry(service, type, item)
#
#   Add a entry to RESOLVED_DEPTREE
#
function add_db_entry(service, type, item,    x, sindex, tmpsplit)
{
	if (!check_service(service)) {
		eerror(" Service '" service "' do not exist!")
		return 0
	}

	sindex = get_service_index(service)

	if ((sindex,type) in RESOLVED_DEPTREE) {
		split(RESOLVED_DEPTREE[sindex,type], tmpsplit)

		for (x in tmpsplit) {
			if (tmpsplit[x] == item)
				return 1
		}
		
		RESOLVED_DEPTREE[sindex,type] = RESOLVED_DEPTREE[sindex,type] " " item
	} else {
		RESOLVED_DEPTREE[sindex,type] = item
	}

	return 1
}

# void resolve_depend(type, service, deplist)
#
#   Verify a depend entry(s) 'deplist' for service 'service' of type 'type',
#   and then add it to the DB.
#
function resolve_depend(type, service, deplist,    x, deparray)
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

	split(deplist, deparray)

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

			if (((type == NEED) || (type == NEEDME)) && (deparray[x] != "net")) {

				ewarn(" Can't find service '" deparray[x] "' needed by '" service "';  continuing...")

				# service is broken due to missing 'need' dependencies
				add_db_entry(service, BROKEN, deparray[x])

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
			}
			
			if (type == AFTER) {
				# NEED and USE override AFTER (service AFTER deparray[x])
				if (check_depend(deparray[x], NEED, service) ||
				    check_depend(deparray[x], USE, service))
					continue
			}

			# NEED override USE (service USE deparray[x])
			if ((type == USE) && (check_depend(deparray[x], NEED, service))) {
				ewarn(" Service '" deparray[x] "' NEED service '" service "', but service '" service "' wants")
				ewarn(" to USE service '" deparray[x] "'!")
				continue
			}

			# We do not want to add circular depends ...
			if (check_depend(deparray[x], type, service)) {
					
					if ((service,deparray[x],type) in CIRCULAR_DEPEND)
						continue
						
					if ((deparray[x],service,type) in CIRCULAR_DEPEND)
						continue
					
					ewarn(" Services '" service "' and '" deparray[x] "' have circular")
					ewarn(" dependency of type '" TYPE_NAMES[type] "';  continuing...")
					
					CIRCULAR_DEPEND[service,deparray[x],type] = "yes"
					
					continue
			}

			add_db_entry(service, type, deparray[x])

			# Reverse mapping
			if (type == NEED)
				add_db_entry(deparray[x], NEEDME, service)

			# Reverse mapping
			if (type == USE)
				add_db_entry(deparray[x], USEME, service)

			# Reverse mapping
			if (type == BEFORE)
				add_db_entry(deparray[x], AFTER, service)

			# Reverse mapping
			if (type == AFTER)
				add_db_entry(deparray[x], BEFORE, service)
		}
	}
}

BEGIN {
	NAME = 1
	RC_NUMBER = 0
	PROVIDE = 10

	# Types ...
	NEED = 2
	NEEDME = 3
	USE = 4
	USEME = 5
	BEFORE = 6
	AFTER = 7
	BROKEN = 8
	PARALLEL = 9
	TYPES_MIN = 2
	TYPES_MAX = 9

	TYPE_NAMES[NEED] = "ineed"
	TYPE_NAMES[NEEDME] = "needsme"
	TYPE_NAMES[USE] = "iuse"
	TYPE_NAMES[USEME] = "usesme"
	TYPE_NAMES[BEFORE] = "ibefore"
	TYPE_NAMES[AFTER] = "iafter"
	TYPE_NAMES[BROKEN] = "broken"
	TYPE_NAMES[PROVIDE] = "provide"
	TYPE_NAMES[PARALLEL] = "parallel"

	# Get our environment variables
	SVCDIR = ENVIRON["SVCDIR"]
	if (SVCDIR == "") {
		eerror("Could not get SVCDIR!")
		exit 1
	}

	# There we do not really use yet
	DEPTYPES = ENVIRON["DEPTYPES"]
	ORDTYPES = ENVIRON["ORDTYPES"]

	CACHEDTREE = SVCDIR "/deptree"

	assert(dosystem("rm -f " CACHEDTREE ), "system(rm -f " CACHEDTREE ")")
}

{
	#
	# Build our DEPTREE array
	#
	
	if ($1 == "RCSCRIPT") {
		RC_NUMBER++

		DEPTREE[RC_NUMBER,NAME] = $2
	}

	if ($1 == "NEED") {
		sub(/NEED[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RC_NUMBER, NEED, $0)
	}

	if ($1 == "USE") {
		sub(/USE[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RC_NUMBER, USE, $0)
	}

	if ($1 == "BEFORE") {
		sub(/BEFORE[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RC_NUMBER, BEFORE, $0)
	}

	if ($1 == "AFTER") {
		sub(/AFTER[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RC_NUMBER, AFTER, $0)
	}

	if ($1 == "PROVIDE") {
		sub(/PROVIDE[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RC_NUMBER, PROVIDE, $0)
	}

	if ($1 == "PARALLEL") {
		sub(/PARALLEL[[:space:]]*/, "")

		if ($0 != "")
			add_deptree_item(RC_NUMBER, PARALLEL, $0)
	}
}

END {
	# Add the 'net' service if it do not exist ...
	if (!check_service("net")) {
		RC_NUMBER++
		DEPTREE[RC_NUMBER,NAME] = "net"
	}
	
	# Calculate all the provides and parallels ...
	for (x = 1;x <= RC_NUMBER;x++) {

		if ((x,PROVIDE) in DEPTREE)
			add_provide(DEPTREE[x,NAME], DEPTREE[x,PROVIDE])
			
		if ((x,PARALLEL) in DEPTREE)
			add_parallel(DEPTREE[x,NAME], DEPTREE[x,PARALLEL])
	}

	# Now do NEED, USE, BEFORE and AFTER
	for (x = 1;x <= RC_NUMBER;x++) {
	
		if ((x,NEED) in DEPTREE)
			resolve_depend(NEED, DEPTREE[x,NAME], DEPTREE[x,NEED])

		if ((x,USE) in DEPTREE)
			resolve_depend(USE, DEPTREE[x,NAME], DEPTREE[x,USE])

		if ((x,BEFORE) in DEPTREE)
			resolve_depend(BEFORE, DEPTREE[x,NAME], DEPTREE[x,BEFORE])

		if ((x,AFTER) in DEPTREE)
			resolve_depend(AFTER, DEPTREE[x,NAME], DEPTREE[x,AFTER])
	}

	for (x = TYPES_MIN; x <= TYPES_MAX; x++)
		print "rc_type_" TYPE_NAMES[x] "=" x >> (CACHEDTREE)
	print "rc_index_scale=" (TYPES_MAX + 1) >> (CACHEDTREE)
	print "" >> (CACHEDTREE)
	print "declare -a RC_DEPEND_TREE" >> (CACHEDTREE)
	print "" >> (CACHEDTREE)
	print "RC_DEPEND_TREE[0]=" RC_NUMBER >> (CACHEDTREE)
	print "" >> (CACHEDTREE)

	# Generate the resolved CACHEDTREE
	#
	# NOTE:  We used to use depinfo_<scriptname>() function to resolve our
	#        rc_<type> variables, but that do not scale when the names of
	#        the scripts include invalid bash variable characters (+,.,etc).
	#
	for (x = 1;x <= RC_NUMBER;x++) {

		print "RC_DEPEND_TREE[" (x * (TYPES_MAX + 1)) "]=\"" DEPTREE[x,NAME] "\"" >> (CACHEDTREE)

		for (y = TYPES_MIN; y <= TYPES_MAX; y++) {

			tmpname = "RC_DEPEND_TREE[" (x * (TYPES_MAX + 1)) "+" y "]"

			if ((x,y) in RESOLVED_DEPTREE) {
			
				split(RESOLVED_DEPTREE[x,y], tmparray1)
				count = asort(tmparray1, tmparray2)
				tmpstr = tmparray2[1]
				
				for (i = 2;i <= count;i++)
					tmpstr = tmpstr " " tmparray2[i]
				
				print tmpname "=\"" tmpstr "\"" >> (CACHEDTREE)
			} else
				print tmpname "=" >> (CACHEDTREE)
		}

		print "" >> (CACHEDTREE)
	}

	# Do not export these, as we want them local
	print "RC_GOT_DEPTREE_INFO=\"yes\"" >> (CACHEDTREE)
	print "" >> (CACHEDTREE)

	if (check_provide("logger"))
		print "LOGGER_SERVICE=\"" get_provide("logger") "\"" >> (CACHEDTREE)
	else
		print "LOGGER_SERVICE=" >> (CACHEDTREE)
		
	close(CACHEDTREE)
}


# vim:ts=4
