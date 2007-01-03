# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

CC = gcc
LD = gcc

CFLAGS ?= -Wall -O2
DESTDIR =
LIBDIR = lib

BIN_TARGETS =
SBIN_TARGETS = consoletype runscript start-stop-daemon
SYS_WHITELIST = env_whitelist

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

OS = Linux
ifeq ($(OS),Linux)
LDFLAGS_RS  = -ldl
endif
ifeq ($(OS),BSD)
LDFLAGS_SSD = -lkvm
endif

override CFLAGS += -DLIBDIR=\"$(LIBDIR)\"

all: $(TARGET)

rs-misc.o: core/misc.c
	$(CC) $(CFLAGS) -c -o $@ $^

runscript: runscript.o rs-misc.o
	$(LD) $(LDFLAGS) -o $@ $^ $(LDFLAGS_RS)

start-stop-daemon: start-stop-daemon.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDFLAGS_SSD)

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/bin
	install -m 0755 -d $(DESTDIR)/sbin
#	install -m 0755 $(BIN_TARGETS) $(DESTDIR)/bin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin
	install -m 0755 -d $(DESTDIR)/$(LIBDIR)/rcscripts/conf.d
	install -m 0644 $(SYS_WHITELIST) $(DESTDIR)/$(LIBDIR)/rcscripts/conf.d

clean:
	rm -f $(TARGET)
	rm -f *.o *~
