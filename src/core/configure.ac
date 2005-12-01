AC_PREREQ([2.59])
AC_INIT([rcscript-core], [0.1], [base-system@gentoo.org])
AM_INIT_AUTOMAKE
AC_CONFIG_HEADER([config.h])

dnl Checks for programs.
AC_PROG_CC
AC_ISC_POSIX
AC_PROG_INSTALL
AC_PROG_MAKE_SET
AC_PROG_AWK

AC_ENABLE_SHARED
AC_DISABLE_STATIC
dnl Next four lines is a hack to prevent libtool checking for CXX/F77
m4_undefine([AC_PROG_CXX])
m4_defun([AC_PROG_CXX],[])
m4_undefine([AC_PROG_F77])
m4_defun([AC_PROG_F77],[])
AC_PROG_LIBTOOL

AC_PREFIX_DEFAULT([/])

dnl Checks for libraries.
dnl Checks for header files.
AC_FUNC_ALLOCA
AC_HEADER_STDC

dnl Checks for typedefs, structures, and compiler characteristics.
AC_C_CONST
AC_TYPE_UID_T
AC_TYPE_MODE_T
AC_TYPE_SIZE_T

dnl Checks for library functions.
AC_FUNC_FORK
AC_FUNC_LSTAT
AC_FUNC_LSTAT_FOLLOWS_SLASHED_SYMLINK
AC_FUNC_MALLOC
AC_FUNC_REALLOC
AC_TYPE_SIGNAL
AC_FUNC_STAT

dnl check if we have 32bit or 64bit output
AC_ARG_ENABLE([debug],
	AS_HELP_STRING([--enable-debug],
		[enable debugging - very verbose (default=disabled)]),
	[enable_debug="$enableval"],
	[enable_debug="no"]
)

if test x"$enable_debug" != xno ; then
	CFLAGS="$CFLAGS -ggdb -DRC_DEBUG"
fi

AC_OUTPUT([
	Makefile
	scripts/Makefile
	data/Makefile
	librcscripts/Makefile
	src/Makefile
	tests/Makefile
])
