/*
 * test-regex.c
 *
 * Test for the simple-regex module.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "librcscripts/debug.h"
#include "librcscripts/simple-regex.h"

char *test_data[] = {
  /* string, pattern, match (1 = yes, 0 = no) */
  "ab", "a?[ab]b", "1",
  "abb", "a?[ab]b", "1",
  "aab", "a?[ab]b", "1",
  "a", "a?a?a?a", "1",
  "aa", "a?a?a?a", "1",
  "aa", "a?a?a?aa", "1",
  "aaa", "a?a?a?aa", "1",
  "ab", "[ab]*", "1",
  "abc", "[ab]*.", "1",
  "ab", "[ab]*b+", "1",
  "ab", "a?[ab]*b+", "1",
  "aaaaaaaaaaaaaaaaaaaaaaa", "a*b", "0",
  "aaaaaaaaabaaabbaaaaaa", "a*b+a*b*ba+", "1",
  "ababababab", "a.*", "1",
  "baaaaaaaab", "a*", "0",
  NULL
};

int main (void)
{
  regex_data_t tmp_data;
  char buf[256], string[100], regex[100];
  int i;

  for (i = 0; NULL != test_data[i]; i += 3)
    {
      snprintf (string, 99, "'%s'", test_data[i]);
      snprintf (regex, 99, "'%s'", test_data[i + 1]);
      snprintf (buf, 255, "string = %s, pattern = %s", string, regex);
#if TEST_VERBOSE
      printf ("%-60s", buf);
#endif
      
      DO_REGEX (tmp_data, test_data[i], test_data[i + 1], error);
      
      if (REGEX_MATCH (tmp_data) && (REGEX_FULL_MATCH == tmp_data.match))
	{
	  if (0 != strncmp (test_data[i + 2], "1", 1))
	    goto error;
	}
      else
	{
	  if (0 != strncmp (test_data[i + 2], "0", 1))
	    goto error;
	}

#if TEST_VERBOSE
      printf ("%s\n", "[ \033[32;01mOK\033[0m ]");
#endif
    }

  return 0;
  
error:
#if TEST_VERBOSE
  printf ("%s\n", "[ \033[31;01m!!\033[0m ]");
#endif

  return 1;
}

