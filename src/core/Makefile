# Copyright (C) 2004,2005 Martin Schlemmer <azarah@nosferatu.za.org>
#
#
#      This program is free software; you can redistribute it and/or modify it
#      under the terms of the GNU General Public License as published by the
#      Free Software Foundation version 2 of the License.
#
#      This program is distributed in the hope that it will be useful, but
#      WITHOUT ANY WARRANTY; without even the implied warranty of
#      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#      General Public License for more details.
#
#      You should have received a copy of the GNU General Public License along
#      with this program; if not, write to the Free Software Foundation, Inc.,
#      675 Mass Ave, Cambridge, MA 02139, USA.
#
# $Header$

CC = gcc
CFLAGS = -Wall
EXTRA_CFLAGS = -DLEGACY_DEPSCAN
STRIP = strip

DEPSCAN = depscan

TARGETS = $(DEPSCAN)

all: $(TARGETS)

.ALL: all

OBJS = \
	parse.o \
	depend.o \
	simple-regex.o \
	misc.o

HEADERS = \
	parse.h \
	depend.h \
	simple-regex.h \
	misc.h \
	debug.h


# cc-option (from linux kernel sources)
# Usage: cflags-y += $(call gcc-option, -march=winchip-c6, -march=i586)

cc-option = $(shell if $(CC) $(1) -S -o /dev/null -xc /dev/null \
              > /dev/null 2>&1; then echo "$(1)"; else echo "$(2)"; fi ;)


ifeq ($(DEBUG),1)
  CFLAGS += -ggdb3
  CFLAGS += $(call cc-option, -fbounds-checking, -pipe)
  EXTRA_CFLAGS += -DRC_DEBUG
endif

$(DEPSCAN): $(OBJS) $(DEPSCAN).o
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -o $@ $^

$(OBJS): $(HEADERS)

.c.o:
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c -o $@ $<

strip: $(TARGETS)
	$(STRIP) -s --remove-section=.note --remove-section=.comment $(TARGETS)

clean:
	rm -f *.o $(TARGETS)
