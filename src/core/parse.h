/*
 * parse.h
 *
 * Parser for Gentoo style rc-scripts.
 *
 * Copyright (C) 2004,2005 Martin Schlemmer <azarah@nosferatu.za.org>
 *
 *
 *      This program is free software; you can redistribute it and/or modify it
 *      under the terms of the GNU General Public License as published by the
 *      Free Software Foundation version 2 of the License.
 *
 *      This program is distributed in the hope that it will be useful, but
 *      WITHOUT ANY WARRANTY; without even the implied warranty of
 *      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *      General Public License for more details.
 *
 *      You should have received a copy of the GNU General Public License along
 *      with this program; if not, write to the Free Software Foundation, Inc.,
 *      675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * $Header$
 */

#ifndef _PARSE_H
#define _PARSE_H

#include <sys/types.h>
#include "list.h"

#define RC_CONF_FILE_NAME	"/etc/rc.conf"
#define RC_CONFD_FILE_NAME	"/etc/conf.d/rc"
#define INITD_DIR_NAME		"/etc/init.d/"
#define CONFD_DIR_NAME		"/etc/conf.d/"

#define SVCDIR_CONFIG_ENTRY	"svcdir"

#define SHELL_PARSER		"/bin/bash"

#define LEGACY_CACHE_FILE_NAME	"deptree"

#define FIELD_RCSCRIPT	"RCSCRIPT"
#define FIELD_NEED	"NEED"
#define FIELD_USE	"USE"
#define FIELD_BEFORE	"BEFORE"
#define FIELD_AFTER	"AFTER"
#define FIELD_PROVIDE	"PROVIDE"
#define FIELD_PARALLEL	"PARALLEL"
#define FIELD_MTIME	"MTIME"

typedef struct {
	struct list_head node;

	char *filename;
	time_t mtime;
	time_t confd_mtime;
} rcscript_info_t;

struct list_head rcscript_list;

int get_rcscripts(void);
int check_rcscripts_mtime(char *cachefile);
size_t generate_stage1(char **data);
size_t generate_stage2(char **data);
size_t read_stage2(char **data);
int write_stage2(FILE *outfile);
size_t generate_stage3(char **data);
size_t read_stage3(char **data);
int write_stage3(FILE *outfile);
int write_legacy_stage3(FILE *output);
int parse_cache(const char *data, size_t lenght);

/*
 * 	get_rcscripts()
 * 		|
 * 		V
 * 	check_rcscripts_mtime()	------------------------------> read_stage3()
 * 		|							|
 * 		|							|
 * 		V							V
 * 	generate_stage1() (Called by generate_stage2())		parse_cache()
 * 		|							|
 * 		|							|
 * 		V							|
 * 	generate_stage2() ----> write_stage2() (Debugging)		|
 * 		|							|
 * 		|							|
 * 		|	    === parse_cache()				|
 * 		V	    |		|				|
 * 	generate_stage3() ==|		|				|
 * 		|	    |		|				|
 * 		|	    |		V				|
 *		|	    === service_resolve_dependencies()		|
 *		|							|
 *		|							|
 * 		|-------> write_legacy_stage3() (Proof of Concept	|
 * 		|				 or Debugging)		|
 * 		|							|
 * 		V							|
 * 	write_stage3()							|
 * 		|							|
 *		|							V
 * 		|<-------------------------------------------------------
 * 		|
 * 		V
 *
 */

#endif /* _PARSE_H */

