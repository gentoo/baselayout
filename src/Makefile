# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

CC = gcc
LD = gcc

CFLAGS = -Wall -O2
DESTDIR =

BIN_TARGETS =
SBIN_TARGETS = consoletype runscript start-stop-daemon

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

OS = Linux
ifeq ($(OS),Linux)
LDFLAGS_RS  = -ldl
endif
ifeq ($(OS),BSD)
LDFLAGS_SSD = -lkvm
endif

all: $(TARGET)

runscript: runscript.o
	$(LD) $(LDFLAGS) $(LDFLAGS_RS) $^ -o $@

start-stop-daemon: start-stop-daemon.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDFLAGS_SSD) $^ -o $@

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/bin
	install -m 0755 -d $(DESTDIR)/sbin
#	install -m 0755 $(BIN_TARGETS) $(DESTDIR)/bin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin

clean:
	rm -f $(TARGET)
	rm -f *.o *~ core
