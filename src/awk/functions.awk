# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

function einfo(string)
{
	system("echo -e \" \\e[32;01m*\\e[0m " string "\"")
}

function ewarn(string)
{
	system("echo -e \" \\e[33;01m*\\e[0m " string "\"")
}

function eerror(string)
{
	system("echo -e \" \\e[31;01m*\\e[0m " string "\"")
}

function isfile(pathname,   x, ret, data)
{
	ret = 0
	data[1] = 1

	if (pathname == "")
		return 0

	ret = stat(pathname, data)
	if (ret < 0)
		return 0

	for (i in data) {
		if (i == "type")
			if (data[i] == "file")
				ret = 1
	}

	return ret
}

function islink(pathname, 	x, ret, data)
{
	ret = 0
	data[1] = 1

	if (pathname == "")
		return 0
	
	ret = stat(pathname, data)
	if (ret < 0)
		return 0
	
	for (i in data) {
		if (i == "type")
			if (data[i] == "symlink")
				ret = 1
	}

	return ret
}

function isdir(pathname, 	x, ret, data)
{
	ret = 0
	data[1] = 1

	if (pathname == "")
		return 0

	ret = stat(pathname, data)
	if (ret < 0)
		return 0

	for (i in data) {
		if (i == "type")
			if (data[i] == "directory")
				ret = 1
	}

	return ret
}

function mktree(pathname, mode,   x, max, ret, data, pathnodes, tmppath)
{
	ret = 0
	data[1] = 1
	pathnodes[1] = 1

	if (pathname == "")
		return 0

	if (pathname ~ /^\//)
		tmppath = ""
	else
		tmppath = "."

	split(pathname, pathnodes, "/")

	for (x in pathnodes)
		max++

	# We cannot use 'for (x in pathnodes)', as gawk likes to
	# sort the order indexes are processed ...
	for (x = 1;x <= max;x++) {
		if (pathnodes[x] == "")
			continue
	
		tmppath = tmppath "/" pathnodes[x]

		ret = stat(tmppath, data)
		if (ret < 0)
			if (mkdir(tmppath, mode) < 0)
				return 0
	}

	return 1
}

# symlink() wrapper that normalize return codes ...
function dosymlink(oldpath, newpath, 	ret)
{
	ret = 0

	ret = symlink(oldpath, newpath)
	if (ret < 0)
		return 0
	else
		return 1
}

# assert --- assert that a condition is true. Otherwise exit.
# This is from the gawk info manual.
function assert(condition, string)
{
	if (! condition) {
		printf("%s:%d: assertion failed: %s\n",
		        FILENAME, FNR, string) > "/dev/stderr"
		_assert_exit = 1
		exit 1
	}
}


# vim:ts=4
