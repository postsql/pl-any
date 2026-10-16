# Makefile for pl_pgq (100% pure SQL/JS/WASM trusted extension on top of plv8 / pljs)

EXTENSION = pl_pgq plpgq pl-pgq
DATA = pl_pgq--1.0.sql plpgq--1.0.sql pl-pgq--1.0.sql pl_pgq_pgtle--1.0.sql

REGRESS = 01_create_property_graph 02_graph_table_pg19 03_quantified_shortest_paths 04_inlining_and_lateral 05_security_roles
REGRESS_PLV8_PREP = --load-extension=plv8 --load-extension=pl_pgq
REGRESS_PLJS_PREP = --load-extension=pljs --load-extension=pl_pgq
REGRESS_OPTS = $(REGRESS_PLV8_PREP)

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

installcheck-plv8:
	$(MAKE) installcheck PG_CONFIG=$(PG_CONFIG) REGRESS_OPTS="$(REGRESS_PLV8_PREP)"

installcheck-pljs:
	$(MAKE) installcheck PG_CONFIG=$(PG_CONFIG) REGRESS_OPTS="$(REGRESS_PLJS_PREP)"
