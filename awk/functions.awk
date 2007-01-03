# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

function einfo(string)
{
	printf(" %s %s%s", "\033[32;01m*\033[0m", string, "\n")
}

function ewarn(string)
{
	printf(" %s %s%s" , "\033[33;01m*\033[0m", string, "\n")
}

function eerror(string)
{
	printf(" %s %s%s" , "\033[31;01m*\033[0m", string, "\n")
}

function isfile(pathname)
{
	return dosystem("test -f \"" pathname "\"");
}

function islink(pathname)
{
	return dosystem("test -L \"" pathname "\"");
}

function isdir(pathname)
{
	return dosystem("test -d \"" pathname "\"");
}

# system() wrapper that normalize return codes ...
function dosystem(command, 	ret)
{
	ret = 0

	ret = system(command)
	if (ret == 0)
		return 1
	else
		return 0
}

# Insert sort routine - cannot use asort as it's GNU specific
function insert_sort(arr, start, end,		i,j,t) {
	for (i = start + 1; i <= end; i++) {
		if (arr[i] > arr[i-1])
			continue
		t = arr[i]
		j=i-1
		do 
			arr[j+1] = arr[j]; 
		while (--j>0 && t < arr[j]);
		arr[j+1] = t
	}
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
