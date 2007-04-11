/*
   rc-misc.c
   rc misc functions
   Copyright 2007 Gentoo Foundation
   */

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/utsname.h>

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <regex.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "einfo.h"
#include "rc-misc.h"
#include "rc.h"
#include "strlist.h"

#define ERRX 		eerrorx("out of memory");

#define PROFILE_ENV	"/etc/profile.env"
#define SYS_WHITELIST	RC_LIBDIR "conf.d/env_whitelist"
#define USR_WHITELIST	"/etc/conf.d/env_whitelist"
#define RC_CONFIG	"/etc/conf.d/rc"

#define PATH_PREFIX 	RC_LIBDIR "bin:/bin:/sbin:/usr/bin:/usr/sbin"

#ifndef S_IXUGO
# define S_IXUGO (S_IXUSR | S_IXGRP | S_IXOTH)
#endif

void *rc_xcalloc (size_t n, size_t size)
{
  void *value = calloc (n, size);

  if (value)
    return value;

  ERRX
}

void *rc_xmalloc (size_t size)
{
  void *value = malloc (size);

  if (value)
    return (value);

  ERRX
}

void *rc_xrealloc (void *ptr, size_t size)
{
  void *value = realloc (ptr, size);

  if (value)
    return (value);

  ERRX
}


char *rc_xstrdup (const char *str)
{
  char *value;

  if (! str)
    return (NULL);

  value = strdup (str);

  if (value)
    return (value);

  ERRX
}

bool rc_is_env (const char *var, const char *val)
{
  char *v;

  if (! var)
    return (false);

  v = getenv (var);
  if (! v)
    return (val == NULL ? true : false);

  return (strcasecmp (v, val) == 0 ? true : false);
}

char *rc_strcatpaths (const char *path1, const char *paths, ...)
{
  va_list ap;
  int length;
  int i;
  char *p;
  char *path;
  char *pathp;

  if (! path1 || ! paths)
    return (NULL);

  length = strlen (path1) + strlen (paths) + 3;
  i = 0;
  va_start (ap, paths);
  while ((p = va_arg (ap, char *)) != NULL)
    length += strlen (p) + 1;
  va_end (ap);

  path = rc_xmalloc (length);
  memset (path, 0, length);
  memcpy (path, path1, strlen (path1));
  pathp = path + strlen (path1) - 1;
  if (*pathp != '/')
    {
      pathp++;
      *pathp++ = '/';
    }
  else
    pathp++;
  memcpy (pathp, paths, strlen (paths));
  pathp += strlen (paths);

  va_start (ap, paths);
  while ((p = va_arg (ap, char *)) != NULL)
    {
      if (*pathp != '/')
        *pathp++ = '/';
      i = strlen (p);
      memcpy (pathp, p, i);
      pathp += i;
    }
  va_end (ap);

  *pathp++ = 0;

  return (path);
}

bool rc_exists (const char *pathname)
{
  struct stat buf;

  if (! pathname)
    return (false);

  if (stat (pathname, &buf) == 0)
    return (true);

  errno = 0;
  return (false);
}

bool rc_is_file (const char *pathname)
{
  struct stat buf;

  if (! pathname)
    return (false);

  if (stat (pathname, &buf) == 0)
    return (S_ISREG (buf.st_mode));

  errno = 0;
  return (false);
}

bool rc_is_dir (const char *pathname)
{
  struct stat buf;

  if (! pathname)
    return (false); 

  if (stat (pathname, &buf) == 0)
    return (S_ISDIR (buf.st_mode));

  errno = 0;
  return (false);
}

bool rc_is_link (const char *pathname)
{
  struct stat buf;

  if (! pathname)
    return (false); 

  if (lstat (pathname, &buf) == 0)
    return (S_ISLNK (buf.st_mode));

  errno = 0;
  return (false);
}

bool rc_is_exec (const char *pathname)
{
  struct stat buf;

  if (! pathname)
    return (false);

  if (lstat (pathname, &buf) == 0)
    return (buf.st_mode & S_IXUGO);

  errno = 0;
  return (false);
}

char **rc_ls_dir (char **list, const char *dir, int options)
{
  DIR *dp;
  struct dirent *d;

  if (! dir)
    return (list);

  if ((dp = opendir (dir)) == NULL)
    {
      eerror ("failed to opendir `%s': %s", dir, strerror (errno));
      return (list);
    }

  errno = 0;
  while (((d = readdir (dp)) != NULL) && errno == 0)
    {
      if (d->d_name[0] != '.')
        {
          if (options & RC_LS_INITD)
            {
              int l = strlen (d->d_name);
              char *init = rc_strcatpaths (RC_INITDIR, d->d_name,
                                           (char *) NULL);
              bool ok = rc_exists (init);
              free (init);
              if (! ok)
                continue;

              /* .sh files are not init scripts */
              if (l > 2 && d->d_name[l - 3] == '.' &&
                  d->d_name[l - 2] == 's' &&
                  d->d_name[l - 1] == 'h')
                continue;
            }
          list = rc_strlist_addsort (list, d->d_name);
        }
    }
  closedir (dp);

  if (errno != 0)
    {
      eerror ("failed to readdir `%s': %s", dir, strerror (errno));
      rc_strlist_free (list);
      return (NULL);
    }

  return (list);
}

bool rc_rm_dir (const char *pathname, bool top)
{
  DIR *dp;
  struct dirent *d;

  if (! pathname)
    return (false);

  if ((dp = opendir (pathname)) == NULL)
    {
      eerror ("failed to opendir `%s': %s", pathname, strerror (errno));
      return (false);
    }

  errno = 0;
  while (((d = readdir (dp)) != NULL) && errno == 0)
    {
      if (strcmp (d->d_name, ".") != 0 && strcmp (d->d_name, "..") != 0)
        {
          char *tmp = rc_strcatpaths (pathname, d->d_name, (char *) NULL);
          if (d->d_type == DT_DIR)
            {
              if (! rc_rm_dir (tmp, true))
                {
                  free (tmp);
                  closedir (dp);
                  return (false);
                }
            }
          else
            {
              if (unlink (tmp))
                {
                  eerror ("failed to unlink `%s': %s", tmp, strerror (errno));
                  free (tmp);
                  closedir (dp);
                  return (false);
                }
            }
          free (tmp);
        }
    }
  if (errno != 0)
    eerror ("failed to readdir `%s': %s", pathname, strerror (errno));
  closedir (dp);

  if (top && rmdir (pathname) != 0)
    {
      eerror ("failed to rmdir `%s': %s", pathname, strerror (errno));
      return false;
    }

  return (true);
}

char **rc_get_config (char **list, const char *file)
{
  FILE *fp;
  char buffer[RC_LINEBUFFER];
  char *p;
  char *token;
  char *line;
  char *linep;
  char *linetok;
  int i = 0;
  bool replaced;
  char *entry;
  char *newline;

  if (! (fp = fopen (file, "r")))
    {
      ewarn ("load_config_file `%s': %s", file, strerror (errno));
      return (list);
    }

  while (fgets (buffer, RC_LINEBUFFER, fp))
    {
      p = buffer;

      /* Strip leading spaces/tabs */
      while ((*p == ' ') || (*p == '\t'))
        p++;

      if (! p || strlen (p) < 3 || p[0] == '#')
        continue;

      /* Get entry */
      token = strsep (&p, "=");
      if (! token)
        continue;

      entry = rc_xstrdup (token);

      do
        {
          /* Bash variables are usually quoted */
          token = strsep (&p, "\"\'");
        }
      while ((token) && (strlen (token) == 0));

      /* Drop a newline if that's all we have */
      i = strlen (token) - 1;
      if (token[i] == 10)
        token[i] = 0;

      i = strlen (entry) + strlen (token) + 2;
      newline = rc_xmalloc (i);
      snprintf (newline, i, "%s=%s", entry, token);

      replaced = false;
      /* In shells the last item takes precedence, so we need to remove
         any prior values we may already have */
      STRLIST_FOREACH (list, line, i)
        {
          char *tmp = rc_xstrdup (line);
          linep = tmp; 
          linetok = strsep (&linep, "=");
          if (strcmp (linetok, entry) == 0)
            {
              /* We have a match now - to save time we directly replace it */
              free (list[i - 1]);
              list[i - 1] = newline; 
              replaced = true;
              free (tmp);
              break;
            }
          free (tmp);
        }

      if (! replaced)
        {
          list = rc_strlist_addsort (list, newline);
          free (newline);
        }
      free (entry);
    }
  fclose (fp);

  return (list);
}

char *rc_get_config_entry (char **list, const char *entry)
{
  char *line;
  int i;
  char *p;

  STRLIST_FOREACH (list, line, i)
    {
      p = strchr (line, '=');
      if (p && strncmp (entry, line, p - line) == 0)
        return (p += 1);
    }

  return (NULL);
}

char **rc_get_list (char **list, const char *file)
{
  FILE *fp;
  char buffer[RC_LINEBUFFER];
  char *p;
  char *token;

  if (! (fp = fopen (file, "r")))
    {
      ewarn ("rc_get_list `%s': %s", file, strerror (errno));
      return (list);
    }

  while (fgets (buffer, RC_LINEBUFFER, fp))
    {
      p = buffer;

      /* Strip leading spaces/tabs */
      while ((*p == ' ') || (*p == '\t'))
        p++;

      /* Get entry - we do not want comments */
      token = strsep (&p, "#");
      if (token && (strlen (token) > 1))
        {
          /* Stip the newline if present */
          if (token[strlen (token) - 1] == '\n')
            token[strlen (token) - 1] = 0;

          list = rc_strlist_add (list, token);
        }
    }
  fclose (fp);

  return (list);
}

char **rc_filter_env (void)
{
  char **env = NULL;
  char **whitelist = NULL;
  char *env_name = NULL;
  char **profile = NULL;
  int count = 0;
  bool got_path = false;
  char *env_var;
  int env_len;
  char *p;
  char *token;
  char *sep;
  char *e;
  int pplen = strlen (PATH_PREFIX);

  whitelist = rc_get_list (whitelist, SYS_WHITELIST);
  if (! whitelist)
    ewarn ("system environment whitelist (" SYS_WHITELIST ") missing");

  whitelist = rc_get_list (whitelist, USR_WHITELIST);

  if (! whitelist)
    return (NULL);

  if (rc_is_file (PROFILE_ENV))
    profile = rc_get_config (profile, PROFILE_ENV);

  STRLIST_FOREACH (whitelist, env_name, count)
    {
      char *space = strchr (env_name, ' ');
      if (space)
        *space = 0;

      env_var = getenv (env_name);

      if (! env_var && profile)
        {
          env_len = strlen (env_name) + strlen ("export ") + 1;
          p = rc_xmalloc (sizeof (char *) * env_len);
          snprintf (p, env_len, "export %s", env_name);
          env_var = rc_get_config_entry (profile, p);
          free (p);
        }

      if (! env_var)
        continue;

      /* Ensure our PATH is prefixed with the system locations first
         for a little extra security */
      if (strcmp (env_name, "PATH") == 0 &&
          strncmp (PATH_PREFIX, env_var, pplen) != 0)
        {
          got_path = true;
          env_len = strlen (env_name) + strlen (env_var) + pplen + 2;
          e = p = rc_xmalloc (sizeof (char *) * env_len);
          p += snprintf (e, env_len, "%s=%s", env_name, PATH_PREFIX);

          /* Now go through the env var and only add bits not in our PREFIX */
          sep = env_var;
          while ((token = strsep (&sep, ":")))
            {
              char *np = strdup (PATH_PREFIX);
              char *npp = np;
              char *tok = NULL;
              while ((tok = strsep (&npp, ":")))
                if (strcmp (tok, token) == 0)
                  break;
              if (! tok)
                p += snprintf (p, env_len - (p - e), ":%s", token);
              free (np);
            }
          *p++ = 0;
        }
      else
        {
          env_len = strlen (env_name) + strlen (env_var) + 2;
          e = rc_xmalloc (sizeof (char *) * env_len);
          snprintf (e, env_len, "%s=%s", env_name, env_var);
        }

      env = rc_strlist_add (env, e);
      free (e);
    }

  /* We filtered the env but didn't get a PATH? Very odd.
     However, we do need a path, so use a default. */
  if (! got_path)
    {
      env_len = strlen ("PATH=") + strlen (PATH_PREFIX) + 2;
      p = rc_xmalloc (sizeof (char *) * env_len);
      snprintf (p, env_len, "PATH=%s", PATH_PREFIX);
      env = rc_strlist_add (env, p);
      free (p);
    }

  rc_strlist_free (whitelist);
  rc_strlist_free (profile);

  return (env);
}

/* Other systems may need this at some point, but for now it's Linux only */
#ifdef __linux__
static bool file_regex (const char *file, const char *regex)
{
  FILE *fp;
  char buffer[RC_LINEBUFFER];
  regex_t re;
  bool retval = false;
  int result;

  if (! rc_exists (file))
    return (false);

  if (! (fp = fopen (file, "r")))
    {
      ewarn ("file_regex `%s': %s", file, strerror (errno));
      return (false);
    }

  if ((result = regcomp (&re, regex, REG_EXTENDED | REG_NOSUB)) != 0)
    {
      fclose (fp);
      regerror (result, &re, buffer, sizeof (buffer));
      eerror ("file_regex: %s", buffer);
      return (false);
    }

  while (fgets (buffer, RC_LINEBUFFER, fp))
    {
      if (regexec (&re, buffer, 0, NULL, 0) == 0)
        {
          retval = true;
          break;
        }
    }
  fclose (fp);
  regfree (&re);

  return (retval);
}
#endif

char **rc_config_env (char **env)
{
  char *line;
  int i;
  char *p;
  char **config = rc_get_config (NULL, RC_CONFIG);
  char *e;
  char sys[6];
  struct utsname uts;
  bool has_net_fs_list = false;
  FILE *fp;
  char buffer[PATH_MAX];

  STRLIST_FOREACH (config, line, i)
    {
      p = strchr (line, '=');
      if (! p)
        continue;

      *p = 0;
      e = getenv (line);
      if (! e)
        {
          *p = '=';
          env = rc_strlist_add (env, line);
        }
      else
        {
          int len = strlen (line) + strlen (e) + 2;
          char *new = rc_xmalloc (sizeof (char *) * len);
          snprintf (new, len, "%s=%s", line, e);
          env = rc_strlist_add (env, new);
          free (new);
        }
    }
  rc_strlist_free (config);

  /* One char less to drop the trailing / */
  i = strlen ("RC_LIBDIR=") + strlen (RC_LIBDIR);
  line = rc_xmalloc (sizeof (char *) * i);
  snprintf (line, i, "RC_LIBDIR=" RC_LIBDIR);
  env = rc_strlist_add (env, line);
  free (line);

  /* One char less to drop the trailing / */
  i = strlen ("RC_SVCDIR=") + strlen (RC_SVCDIR);
  line = rc_xmalloc (sizeof (char *) * i);
  snprintf (line, i, "RC_SVCDIR=" RC_SVCDIR);
  env = rc_strlist_add (env, line);
  free (line);

  env = rc_strlist_add (env, "RC_BOOTLEVEL=" RC_LEVEL_BOOT);

  p = rc_get_runlevel ();
  i = strlen ("RC_SOFTLEVEL=") + strlen (p) + 1;
  line = rc_xmalloc (sizeof (char *) * i);
  snprintf (line, i, "RC_SOFTLEVEL=%s", p);
  env = rc_strlist_add (env, line);
  free (line);

  if (rc_exists (RC_SVCDIR "ksoftlevel"))
    {
      if (! (fp = fopen (RC_SVCDIR "ksoftlevel", "r")))
        eerror ("fopen `%s': %s", RC_SVCDIR "ksoftlevel",
                strerror (errno));
      else
        {
          memset (buffer, 0, sizeof (buffer));
          if (fgets (buffer, sizeof (buffer), fp))
            {
              i = strlen (buffer) - 1;
              if (buffer[i] == '\n')
                buffer[i] = 0;
              i += strlen ("RC_DEFAULTLEVEL=") + 2;
              line = rc_xmalloc (sizeof (char *) * i);
              snprintf (line, i, "RC_DEFAULTLEVEL=%s", buffer);
              env = rc_strlist_add (env, line);
              free (line);
            }
          fclose (fp);
        }
    }
  else
    env = rc_strlist_add (env, "RC_DEFAULTLEVEL=" RC_LEVEL_DEFAULT);

  memset (sys, 0, sizeof (sys));

  /* Linux can run some funky stuff like Xen, VServer, UML, etc
     We store this special system in RC_SYS so our scripts run fast */
#ifdef __linux__
  if (rc_is_dir ("/proc/xen"))
    {
      fp = fopen ("/proc/xen/capabilities", "r");
      if (fp)
        {
          fclose (fp);
          if (file_regex ("/proc/xen/capabilities", "control_d"))
            snprintf (sys, sizeof (sys), "XENU");
        }
      if (! sys)
        snprintf (sys, sizeof (sys), "XEN0");
    }
  else if (file_regex ("/proc/cpuinfo", "UML"))
    snprintf (sys, sizeof (sys), "UML");
  else if (file_regex ("/proc/self/status",
                       "(s_context|VxID|envID):[[:space:]]*[1-9]"))
                                                  snprintf (sys, sizeof (sys), "VPS"); 
#endif

  /* Only add a NET_FS list if not defined */
  STRLIST_FOREACH (env, line, i)
   if (strncmp (line, "RC_NET_FS_LIST=", strlen ("RC_NET_FS_LIST=")) == 0)
     {
       has_net_fs_list = true;
       break;
     }
  if (! has_net_fs_list)
    {
      i = strlen ("RC_NET_FS_LIST=") + strlen (RC_NET_FS_LIST_DEFAULT) + 1;
      line = rc_xmalloc (sizeof (char *) * i);
      snprintf (line, i, "RC_NET_FS_LIST=%s", RC_NET_FS_LIST_DEFAULT);
      env = rc_strlist_add (env, line);
      free (line);
    }

  if (sys[0])
    {
      i = strlen ("RC_SYS=") + strlen (sys) + 2;
      line = rc_xmalloc (sizeof (char *) * i);
      snprintf (line, i, "RC_SYS=%s", sys);
      env = rc_strlist_add (env, line);
      free (line);
    }

  /* Some scripts may need to take a different code path if Linux/FreeBSD, etc
     To save on calling uname, we store it in an environment variable */
  if (uname (&uts) == 0)
    {
      i = strlen ("RC_UNAME=") + strlen (uts.sysname) + 2;
      line = rc_xmalloc (sizeof (char *) * i);
      snprintf (line, i, "RC_UNAME=%s", uts.sysname);
      env = rc_strlist_add (env, line);
      free (line);
    }

  return (env);
}