# Makefile for pl_jsonschema (100% pure SQL/JS trusted extension on top of plv8 / pljs)

EXTENSION = pl_jsonschema pl-jsonschema
EXTVERSION = 1.0
DATA = pl_jsonschema--$(EXTVERSION).sql pl-jsonschema--$(EXTVERSION).sql pl_jsonschema_pgtle--$(EXTVERSION).sql

REGRESS = pl_jsonschema

PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

.PHONY: installcheck-plv8 installcheck-pljs rebuild-bundle

installcheck-plv8:
	PGOPTIONS="$(PGOPTIONS) -c pl_jsonschema.engine=plv8" $(MAKE) installcheck PG_CONFIG=$(PG_CONFIG)

installcheck-pljs:
	PGOPTIONS="$(PGOPTIONS) -c pl_jsonschema.engine=pljs" $(MAKE) installcheck PG_CONFIG=$(PG_CONFIG)

rebuild-bundle: pl_jsonschema.sql.in ajv_bundle.sql.gz
	python3 $(srcdir)/scripts/build_bundle.py
