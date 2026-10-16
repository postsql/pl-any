# Makefile for pl_jsonschema (100% pure SQL/JS/WASM trusted extension on top of plv8 / pljs)

EXTENSION = pl_jsonschema pl-jsonschema
DATA = pl_jsonschema--1.0.sql pl-jsonschema--1.0.sql pl_jsonschema_pgtle--1.0.sql

REGRESS = pl_jsonschema
REGRESS_PLV8_PREP = --load-extension=plv8 --load-extension=pl_jsonschema
REGRESS_PLJS_PREP = --load-extension=pljs --load-extension=pl_jsonschema
REGRESS_OPTS = $(REGRESS_PLV8_PREP)

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

installcheck-plv8:
	$(MAKE) installcheck PG_CONFIG=$(PG_CONFIG) REGRESS_OPTS="$(REGRESS_PLV8_PREP)"

installcheck-pljs:
	$(MAKE) installcheck PG_CONFIG=$(PG_CONFIG) REGRESS_OPTS="$(REGRESS_PLJS_PREP)"
