/*
   rc-depend
   rc service dependency and ordering
   Copyright 2006-2007 Gentoo Foundation
   Written by Roy Marples <uberlord@gentoo.org>

   For optimum operation, we need to get several variables.
   The easiest way is via the environment, so these should be set before
   running rc-order :-
   SOFTLEVEL
   BOOTLEVEL

   We can also handle other dependency files and types, like Gentoos
   net modules. These are used with the --deptree and --awlaysvalid flags.
   */

#define SVCDIR 		"/lib/rcscripts/init.d"
#define DEPTREE 	SVCDIR "/deptree"
#define RUNLEVELDIR 	"/etc/runlevels"
#define INITDIR		"/etc/init.d"

#define BOOTLEVEL	"boot"
#define SOFTLEVEL	"default"
#define RCNETCHECK	"no"

#define MAXTYPES 	20 /* We currently only go upto 10 (providedby) */
#define LINEBUFFER	2048

#include <sys/types.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

char *bootlevel;
char *softlevel;
char *svcname;
bool always_valid = false;
bool strict = false;

struct linkedlist
{
  char *item;
  struct linkedlist *next;
} linkedlist;

struct deptype
{
  char *type;
  char *services;
  struct deptype *next;
} deptype;

struct depinfo
{
  char *service;
  struct deptype *deps;
  struct depinfo *next;
} depinfo;

void *xmalloc (size_t size)
{
  register void *value = malloc (size);

  if (value)
    return value;

  errx (EXIT_FAILURE, "memory exhausted");
}

struct linkedlist *add_linkedlist (struct linkedlist *linkedlist,
				   const char *item)
{
  if (! linkedlist || ! item)
    return NULL;

  struct linkedlist *p = linkedlist;
  if (! p->item)
    {
      p->item = strdup (item);
      return p;
    }

  while (p->next)
    p = p->next;

  p->next = xmalloc (sizeof (struct linkedlist));
  p = p->next;
  memset (p, 0, sizeof (struct linkedlist));
  p->item = strdup (item);

  return p;
}

void free_linkedlist (struct linkedlist *linkedlist)
{
  struct linkedlist *p = linkedlist;
  struct linkedlist *n = NULL;

  while (p)
    {
      n = p->next;
      if (p->item)
	free (p->item);
      free (p);
      p = n;
    }
}

char *get_shell_value (char *string)
{
  if (! string)
    return NULL;

  char *p = string;
  if (*p == '"')
    p++;
  char *e = p + strlen (p) - 1;
  if (*e == '\n')
    *e-- = 0;
  if (*e == '"')
    *e-- = 0;

  if (*p != 0)
    return p;

  return NULL;
}

bool is_runlevel_start ()
{
  struct stat sb;

  if (stat (SVCDIR "/softscripts.old", &sb) == 0)
    return true;
  return false;
}

bool is_runlevel_stop ()
{
  struct stat sb;

  if (stat (SVCDIR "/softscripts.new", &sb) == 0)
    return true;
  return false;
}

bool exists_dir_file (const char *dir, const char *file)
{
  int l = strlen (dir) + strlen (file) + 2;
  char *f = xmalloc (l);
  snprintf (f, l, "%s/%s", dir, file);

  bool result = false;
  struct stat sb;
  if (stat (f, &sb) == 0)
    result = true; 
  free (f);
  return (result);
}

bool exists_dir_dir_file (const char *dir1, const char *dir2, const char *file)
{
  int l = strlen (dir1) + strlen (dir2) + 2;
  char *d = xmalloc (l);
  snprintf (d, l, "%s/%s", dir1, dir2);

  bool result = exists_dir_file (d, file);
  free (d);
  return (result);
}

bool in_runlevel (const char *level, const char *service)
{
  return exists_dir_dir_file (RUNLEVELDIR, level, service);
}

bool service_coldplugged (const char *service)
{
  return exists_dir_dir_file (SVCDIR, "coldplugged", service);
}

bool service_starting (const char *service)
{
  return exists_dir_dir_file (SVCDIR, "starting", service);
}

bool service_inactive (const char *service)
{
  return exists_dir_dir_file (SVCDIR, "inactive", service);
}

bool service_started (const char *service)
{
  return exists_dir_dir_file (SVCDIR, "started", service);
}

bool service_stopping (const char *service)
{
  return exists_dir_dir_file (SVCDIR, "stopping", service);
}

bool service_stopped (const char *service)
{
  if (service_starting (service)
      || service_started (service)
      || service_inactive (service)
      || service_stopping (service))
    return false;

  return true;
}


void free_deptree (struct depinfo *deptree)
{
  struct depinfo *di = deptree;
  while (di)
    {
      free (di->service);
      struct depinfo *dip = di->next;
      struct deptype *dt = di->deps;
      while (dt)
	{
	  free (dt->type);  
	  free (dt->services);
	  struct deptype *dtp = dt->next;
	  free (dt);
	  dt = dtp;
	}
      free (di);
      di = dip;
    }
}

/* Load our deptree
   Although the deptree file is pure sh, it is in a fixed format created
   by gendeptree awk script. We depend on this, if you pardon the pun ;)
   */
struct depinfo *load_deptree (char *file)
{
  FILE *fp;
  if (! (fp = fopen (file, "r")))
    err (EXIT_FAILURE, "Failed to open deptree `%s'", file);

  char *types[MAXTYPES];
  memset (types, 0, MAXTYPES);

  struct depinfo *deptree = xmalloc (sizeof (struct depinfo));
  memset (deptree, 0, sizeof (struct depinfo));
  struct depinfo *depinfo = NULL;
  struct deptype *deptype = NULL;
  char buffer [LINEBUFFER];
  int rc_type_len = strlen ("declare -r rc_type_");
  int rc_depend_tree_len = strlen ("RC_DEPEND_TREE[");
  int max_type = 0;
  char *p, *e, *f;

  while (fgets (buffer, LINEBUFFER, fp))
    {
      /* Grab our types first */
      if (strncmp (buffer, "declare -r rc_type_", rc_type_len) == 0)
	{
	  p = buffer + rc_type_len;
	  if (! (e = strchr(p, '=')))
	    continue;

	  /* Blank out the = sign so we can just copy the text later */
	  *e = 0;
	  e++;

	  errno = 0;
	  long t = strtol (e, &f, 10);
	  if ((errno == ERANGE && (t == LONG_MAX || t == LONG_MIN))
	      || (errno != 0 && t == 0))
	    continue;

	  types[t] = strdup (p);
	  if (t > max_type)
	    max_type = t;

	  continue;
	}

      if (strncmp (buffer, "RC_DEPEND_TREE[", rc_depend_tree_len))
	continue;

      p = buffer + rc_depend_tree_len;
      e = NULL;

      errno = 0;
      long idx = strtol (p, &e, 10);
      if ((errno == ERANGE && (idx == LONG_MAX || idx == LONG_MIN))
	  || (errno != 0 && idx == 0))
	{
	  warnx ("load_deptree: `%s' is not an index", p);
	  continue;
	}

      if (idx == 0)
	continue;

      /* If we don't have a + then we're a new service
	 OK, this is a hack, but it works :) */
      if (*e == ']')
	{
	  e += 2; // ]=
	  if (! depinfo)
	    depinfo = deptree;
	  else
	    {
	      depinfo->next = xmalloc (sizeof (struct depinfo));
	      depinfo = depinfo->next;
	      memset (depinfo, 0, sizeof (struct depinfo));
	    }
	  deptype = NULL;
	  depinfo->service = strdup (get_shell_value (e));
	  continue;
	}

      /* Sanity */
      if (*e != '+')
	{
	  warnx ("load_deptree: expecting `+', got `%s'", e);
	  continue;
	}

      /* Now we need to work out our service value */
      p = e + 1;
      errno = 0;
      long val = strtol (p, &e, 10);
      if ((errno == ERANGE && (val == LONG_MAX || val == LONG_MIN))
	  || (errno != 0 && val == 0))
	{
	  warnx ("load_deptree: `%s' is not an service type", p);
	  continue;
	}

      if (! types[val])
	{
	  warnx ("load_deptree: we don't value a type for index `%li'", val);
	  continue;
	}

      if (*e != ']')
	{
	  warnx ("load_deptree: expecting `]', got `%s'", e);
	  continue;
	}
      e++;
      if (*e != '=')
	{
	  warnx ("load_deptree: expecting `=', got `%s'", e);
	  continue;
	}
      e++;

      /* If we don't have a value then don't bother to add the dep */
      char *x = get_shell_value (e++);
      if (! x)
	continue;

      if (deptype)
	{
	  deptype->next = xmalloc (sizeof (struct deptype));
	  deptype = deptype->next;
	}
      else
	{
	  depinfo->deps = xmalloc (sizeof (struct deptype));
	  deptype = depinfo->deps;
	}
      memset (deptype, 0, sizeof (struct deptype));

      deptype->type = strdup (types[val]);
      deptype->services = strdup (x);
    }

  fclose (fp);

  if (! depinfo)
    {
      free (deptree);
      deptree = NULL;
    }

  int i;
  for (i = 0; i <= max_type; i++)
    if (types[i])
      free (types[i]);

  return deptree;
}

struct depinfo *get_depinfo (struct depinfo *deptree, const char *service)
{
  if (! deptree || ! service)
    return NULL;

  struct depinfo *di;
  for (di = deptree; di; di = di->next)
    if (strcmp (di->service, service) == 0)
      return di;

  return NULL;
}

struct deptype *get_deptype (struct depinfo *depinfo, const char *type)
{
  if (! depinfo || !type)
    return NULL;

  struct deptype *dt;
  for (dt = depinfo->deps; dt; dt = dt->next)
    if (strcmp (dt->type, type) == 0)
      return dt;

  return NULL;
}

bool valid_service (const char *service)
{
  return (always_valid
	  || exists_dir_dir_file (RUNLEVELDIR, bootlevel, service)
	  || exists_dir_dir_file (RUNLEVELDIR, softlevel, service)
	  || service_coldplugged (service) || service_started (service));
}

/* Work out if a service is provided by another service.
   For example metalog provides logger.
   We need to be able to handle syslogd providing logger too.
   We do this by checking whats running, then what's starting/stopping,
   then what's run in the runlevels and finally alphabetical order.
   */
struct linkedlist *get_provided (struct depinfo *deptree,
				 struct depinfo *depinfo)
{
  if (exists_dir_file (INITDIR, depinfo->service))
    return NULL;

  struct deptype *dt = get_deptype (depinfo, "providedby");
  if (! dt)
    return NULL;

  struct linkedlist *providers = xmalloc (sizeof (struct linkedlist));
  struct linkedlist *lp = providers;
  memset (providers, 0, sizeof (struct linkedlist));
  char *p, *op, *service;
  bool r_start = is_runlevel_start ();
  bool r_stop = is_runlevel_stop ();

  /* If we're not strict then the first started service in our runlevel
     will do */
  if (! strict && ! r_stop)
    {
      op = p = strdup (dt->services);
      int i = 0;
      while ((service = strsep (&p, " ")))
	if (in_runlevel (softlevel, service) && service_started (service))
	  {
	    if (i++ == 1)
	      {
		free_linkedlist (providers);
		return NULL;
	      }
	    lp = add_linkedlist (lp, service);
	  }
      free (op);

      if (providers->item)
	return (providers);
    }

  op = p = strdup (dt->services);
  while ((service = strsep (&p, " ")))
    {
      if (always_valid)
	{
	  lp = add_linkedlist (lp, service);
	  continue;
	}

      if (in_runlevel (softlevel, service)
	  || (strcmp (softlevel, bootlevel) == 0
	      && service_coldplugged (service))
	 )
	if (get_depinfo (deptree, service))
	  if (exists_dir_file (INITDIR, service))
	    lp = add_linkedlist (lp, service);
    }
  free (op);

  if (always_valid)
    {
      if (providers->item)
	return (providers);

      free (providers);
      return NULL;
    }

  /* Check running only if runlevel is stopping or starting.
     Should we also check running if no provides are in runlevels?
     Well, I think that we should provide only if one service is running
     as a laptop could have wired and wireless, neither being in the runlevel
     as both are optional. However, things like openvpn, netmount etc will
     require at least one up. */
  if (r_start || r_stop || (! providers->item && ! strict))
    {
      op = p = strdup (dt->services);
      while ((service = strsep (&p, " ")))
	{
	  bool ok = false;
	  if (r_stop)
	    {
	      // if (service_started (service) || service_stopping (service))
		ok = true;
	    }
	  else
	    {
	      if (service_started (service))
		ok = true;
	    }
	  if (ok && get_depinfo (deptree, service))
	    lp = add_linkedlist (lp, service);
	}
      free (op);
    }

  /* If we still have nothing, then see if anything is inactive. */
  if (! providers->item && ! strict)
    {
      op = p = strdup (dt->services);
      while ((service = strsep (&p, " ")))
	{
	  if (service_inactive (service))
	    if (get_depinfo (deptree, service))
	      lp = add_linkedlist (lp, service);
	}
      free (op);
    }

  /* Lastly, check the boot runlevel if we're not in it. */
  if (strcmp (softlevel, bootlevel) != 0)
    {
      op = p = strdup (dt->services);
      while ((service = strsep (&p, " ")))
	{
	  if (in_runlevel (bootlevel, service)
	      || (service_coldplugged (service) && ! providers->item))
	    if (get_depinfo (deptree, service))
	      if (exists_dir_file (INITDIR, service))
		lp = add_linkedlist (lp, service);
	}
      free (op);
    }

  if (providers->item)
    return (providers);

  free (providers);
  return NULL;
}

void visit_service (struct depinfo *deptree,
		    struct linkedlist *types,
		    struct linkedlist *sorted, struct linkedlist *visited,
		    struct depinfo *depinfo,
		    bool descend)
{
  if (! deptree || !sorted || !visited || !depinfo)
    return;

  struct linkedlist *s;
  struct linkedlist *l = NULL;

  /* Check if we have already visited this service or not */
  for (s = visited; s; s = s->next)
    {
      if (s->item && strcmp (s->item, depinfo->service) == 0)
	return;
      l = s;
    }

  /* Add ourselves as a visited service */
  l = add_linkedlist(l, depinfo->service);

  char *p, *op;
  char *service;

  struct linkedlist *provides;
  struct linkedlist *type;
  struct linkedlist *lp;
  struct depinfo *di;
  struct deptype *dt;

  for (type = types; type; type = type->next)
    {
      if ((dt = get_deptype (depinfo, type->item)))
	{
	  op = p = strdup (dt->services);
	  while ((service = strsep (&p, " ")))
	    {
	      if (! descend || strcmp (type->item, "iprovide") == 0)
		{
		  add_linkedlist (sorted, service);
		  continue;
		}

	      di = get_depinfo (deptree, service);
	      if ((provides = get_provided (deptree, di)))
		{
		  for (lp = provides; lp; lp = lp->next)
		    {
		      di = get_depinfo (deptree, lp->item);
		      if (di && (strcmp (type->item, "ineed") == 0
				 || valid_service (di->service)))
			visit_service (deptree, types, sorted, visited, di,
				       true);
		    }
		  free_linkedlist (provides);
		}
	      else
		if (di && (strcmp (type->item, "ineed") == 0
			   || valid_service (service)))
		  visit_service (deptree, types, sorted, visited, di, true);
	    }
	  free (op);
	}
    }

  /* Now visit the stuff we provide for */
  if ((dt = get_deptype (depinfo, "iprovide")) && descend)
    {
      op = p = strdup (dt->services);
      while ((service = strsep (&p, " ")))
	{
	  if ((di = get_depinfo (deptree, service)))
	    if ((provides = get_provided (deptree, di)))
	      {
		for (lp = provides; lp; lp = lp->next)
		  if (strcmp (lp->item, depinfo->service) == 0)
		    {
		      visit_service (deptree, types, sorted, visited, di, true);
		      break;
		    }
		free_linkedlist (provides);
	      }
	}
      free (op);
    }

  /* We've visited everything we need, so add ourselves unless we
     are also the service calling us or we are provided by something */
  if (! svcname || strcmp (svcname, depinfo->service) != 0)
    if (! get_deptype (depinfo, "providedby"))
      add_linkedlist (sorted, depinfo->service);
}

int main (int argc, char **argv)
{

  int i;
  struct linkedlist *types = xmalloc (sizeof (struct linkedlist));
  struct linkedlist *services = xmalloc (sizeof (struct linkedlist));
  memset (types, 0, sizeof (struct linkedlist));
  memset (services, 0, sizeof (struct linkedlist));

  struct linkedlist *lasttype = types;
  struct linkedlist *lastservice = services;
  struct depinfo *di = NULL;
  bool trace = true;

  struct depinfo *deptree = NULL;
  for (i = 1; i < argc; i++)
    {
      if (strcmp (argv[i], "--alwaysvalid") == 0)
	{
	  always_valid = true;
	  continue;
	}

      if (strcmp (argv[i], "--strict") == 0)
	{
	  strict = true;
	  continue;
	}

      if (strcmp (argv[i], "--deptree") == 0)
	{
	  i++;
	  if (i == argc)
	    errx (EXIT_FAILURE, "no deptree specified");

	  if ((deptree = load_deptree (argv[i])) == NULL)
	    {
	      free_linkedlist (types);
	      free_linkedlist (services);
	      errx (EXIT_FAILURE, "failed to load deptree `%s'", argv[i]);
	    }

	  continue;
	}

      if (strcmp (argv[i], "--notrace") == 0)
	{
	  trace = false;
	  continue;
	}

      if (argv[i][0] == '-')
	{
	  argv[i]++;
	  lasttype = add_linkedlist (lasttype, argv[i]);
	}
      else
	{
	  if (! deptree && ((deptree = load_deptree (DEPTREE)) == NULL))
	    {
	      free_linkedlist (types);
	      free_linkedlist (services);
	      errx (EXIT_FAILURE, "failed to load deptree `%s'", DEPTREE);
	    }

	  di = get_depinfo (deptree, argv[i]);
	  if (! di)
	    warnx ("no dependency info for service `%s'", argv[i]);
	  else
	    lastservice = add_linkedlist (lastservice, argv[i]);
	}
    }

  if (! services->item)
    {
      free_linkedlist (types);
      free_linkedlist (services);
      free_deptree (deptree);
      errx (EXIT_FAILURE, "no services specified");
    }

  /* If we don't have any types, then supply some defaults */
  if (! types->item)
    {
      lasttype = add_linkedlist (lasttype, "ineed");
      lasttype = add_linkedlist (lasttype, "iuse");
    }

  /* Setup our runlevels */
  bootlevel = getenv ("BOOTLEVEL");
  if (! bootlevel)
    bootlevel = BOOTLEVEL;
  if (is_runlevel_stop ())
    softlevel = getenv ("OLDSOFTLEVEL");
  else
    softlevel = getenv ("SOFTLEVEL");
  if (! softlevel)
    softlevel = SOFTLEVEL;
  svcname = getenv ("SVCNAME");

  struct linkedlist *sorted = xmalloc (sizeof (struct linkedlist));
  struct linkedlist *visited = xmalloc (sizeof (struct linkedlist));
  memset (sorted, 0, sizeof (struct linkedlist));
  memset (visited, 0, sizeof (struct linkedlist));

  struct linkedlist *service;
  for (service = services; service; service = service->next)
    {
      di = get_depinfo (deptree, service->item);
      visit_service (deptree, types, sorted, visited, di, trace);
    }

  if (sorted->item)
    {
      struct linkedlist *s;
      bool first = true;
      for (s = sorted; s; s = s->next)
	{
	  if (first)
	    first = false;
	  else
	    printf (" ");
	  if (s->item)
	    printf ("%s", s->item);
	}
      printf ("\n");
    }

  free_linkedlist (sorted);
  free_linkedlist (visited);
  free_linkedlist (types);
  free_linkedlist (services);
  free_deptree (deptree);
  return (0);
}
