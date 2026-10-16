# Top-level Makefile for pl-any (pure-SQL/JS/WASM trusted procedural languages)

SUBDIRS ?= $(sort $(patsubst %/Makefile,%,$(wildcard pl_*/Makefile)))
PG_CONFIG ?= pg_config

.PHONY: all install installcheck clean $(SUBDIRS)

all:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir PG_CONFIG=$(PG_CONFIG) all || exit 1; done

install:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir PG_CONFIG=$(PG_CONFIG) install || exit 1; done

installcheck:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir PG_CONFIG=$(PG_CONFIG) installcheck || exit 1; done

clean:
	@for dir in $(SUBDIRS); do $(MAKE) -C $$dir PG_CONFIG=$(PG_CONFIG) clean || exit 1; done
