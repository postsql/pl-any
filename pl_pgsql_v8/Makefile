# Makefile for pl_pgsql_v8 (100% pure SQL/JS/WASM trusted extension on top of plv8 / pljs)

EXTENSION = pl_pgsql_v8
DATA = pl_pgsql_v8--1.0.sql pl_pgsql_v8_pgtle--1.0.sql

REGRESS = plpgsql_v8
REGRESS_PLV8_PREP = --load-extension=plv8 --load-extension=pl_pgsql_v8
REGRESS_PLJS_PREP = --load-extension=pljs --load-extension=pl_pgsql_v8
REGRESS_OPTS = $(REGRESS_PLV8_PREP)

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

installcheck-plv8:
	$(MAKE) installcheck PG_CONFIG=$(PG_CONFIG) REGRESS_OPTS="$(REGRESS_PLV8_PREP)"

installcheck-pljs:
	$(MAKE) installcheck PG_CONFIG=$(PG_CONFIG) REGRESS_OPTS="$(REGRESS_PLJS_PREP)"
