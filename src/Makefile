# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

CC = gcc
LD = gcc

CFLAGS = -Wall -O2
DESTDIR =

BIN_TARGETS =
SBIN_TARGETS = consoletype runscript start-stop-daemon

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

all: $(TARGET)

.o:
	$(CC) $(CFLAGS) -c $^

consoletype: consoletype.o
	$(LD) -o $@ $^

runscript: runscript.o
	$(LD) -o $@ $^ -ldl

start-stop-daemon: start-stop-daemon.o
	$(LD) -o $@ $^

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/bin
	install -m 0755 -d $(DESTDIR)/sbin
#	install -m 0755 $(BIN_TARGETS) $(DESTDIR)/bin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin

clean:
	rm -f $(TARGET)
	rm -f *.o *~ core

