# Copyright 1999-2004 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$

CC = gcc
LD = gcc

CFLAGS = -Wall -O2
DESTDIR =

BIN_TARGETS =
SBIN_TARGETS = consoletype runscript start-stop-daemon

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

all: $(TARGET)

consoletype: consoletype.o
	$(LD) -o $@ $^

runscript: runscript.o
	$(LD) -o $@ $^ -ldl

start-stop-daemon: start-stop-daemon.c
	$(CC) -o $@ $(CFLAGS) -DHAVE_ERROR_H -DHAVE_TIOCNOTTY -DHAVE_SETSID $^

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/bin
	install -m 0755 -d $(DESTDIR)/sbin
#	install -m 0755 $(BIN_TARGETS) $(DESTDIR)/bin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin

clean:
	rm -f $(TARGET)
	rm -f *.o *~ core
