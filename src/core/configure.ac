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

AC_PREFIX_DEFAULT([])

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
AC_TYPE_SIGNAL
AC_FUNC_STAT
AC_CHECK_FUNCS([remove])

dnl Check if gcc provides va_copy or __va_copy
AC_MSG_CHECKING([for va_copy])
AC_TRY_COMPILE([
    #include <stdarg.h>
  ], [
    va_list ap, aq;
    va_copy(ap, aq);
  ],
  [va_copy="va_copy"],
  [AC_TRY_COMPILE([
      #include <stdarg.h>
    ], [
      va_list ap, aq;
      __va_copy(ap, aq);
    ],
    [va_copy="__va_copy"],
    [AC_MSG_ERROR([Unable to determine name of va_copy macro])]
  )]
)
AC_MSG_RESULT([$va_copy])
if test x"$va_copy" != xva_copy ; then
  AC_DEFINE_UNQUOTED([va_copy], [$va_copy],
    [Define to name of va_copy macro proviced by gcc if its not `va_copy'.]
  )
fi

dnl Check if we want SELinux support
AC_ARG_ENABLE([selinux],
  AS_HELP_STRING([--enable-selinux],
    [enable SELinux support (default=disabled)]),
  [enable_selinux="$enableval"],
  [enable_selinux="no"]
)

if test x"$enable_selinux" != xno ; then
  AC_DEFINE([WANT_SELINUX], [], [Define if SELinux support is required.])
fi

dnl Check if we want debugging
AC_ARG_ENABLE([debug],
  AS_HELP_STRING([--enable-debug],
    [enable debugging - very verbose (default=disabled)]),
  [enable_debug="$enableval"],
  [enable_debug="no"]
)

if test x"$enable_debug" != xno ; then
  CFLAGS="$CFLAGS -ggdb -DRC_DEBUG -Wshadow -Wmissing-prototypes -Wmissing-declarations -Wredundant-decls -Wnested-externs"
fi

CFLAGS="$CFLAGS -Wall"

RCSCRIPTS_DEFINES='-DETCDIR="\"$(sysconfdir)\"" -DLIBDIR="\"$(libdir)\"" -DBINDIR="\"$(bindir)\"" -DSBINDIR="\"$(sbindir)\""'
AC_SUBST([RCSCRIPTS_DEFINES])

AM_DL

AC_OUTPUT([
  Makefile
  scripts/Makefile
  data/Makefile
  librcscripts/Makefile
  src/Makefile
  tests/Makefile
])

