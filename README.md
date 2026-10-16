# `pl_any`: Standalone Trusted Compile-to-JS/WASM Procedural Languages for PostgreSQL

Every directory under `pl_any/` is a **100% pure-SQL/JS/WASM PostgreSQL extension** (`trusted = true`, zero C `.so` modules) that runs on top of `plv8` (or `pljs`) and can be installed by non-privileged database owners via either:
1. `CREATE EXTENSION <ext_name>;` (standard PostgreSQL filesystem extension with `trusted = true`), or
2. `psql -f <ext_name>_pgtle--1.0.sql` followed by `CREATE EXTENSION <ext_name>;` (`pg_tle`).

| Subdirectory | Extension Name | Registered Language Names | Description |
| :--- | :--- | :--- | :--- |
| `pl_pgsql_v8/` | `pl_pgsql_v8` | `pl_pgsql_v8`, `plpgsql_v8`, `"pl/pgsql+v8"` | Full PL/pgSQL compiler targeting V8 JavaScript |
| `pl_sqltsm/` | `pl_sqltsm` | `pl_sqltsm`, `sqltsm_v8`, `"sql/tsm"` | SQL/TSM (T-SQL Module dialect) compiler targeting V8 JavaScript |
| `pl_sqlpsm/` | `pl_sqlpsm` | `pl_sqlpsm`, `sqlpsm_v8`, `"sql/psm"` | ISO/IEC 9075-4 SQL/PSM compiler targeting V8 JavaScript |
| `pl_tsql/` | `pl_tsql` | `pl_tsql`, `tsql_v8`, `"pl/tsql+v8"` | T-SQL compiler + `tsql.*` helper schema & operators on V8 |
| `pl_minipython_v8/` | `pl_minipython_v8` | `pl_minipython_v8`, `"pl/minipython+v8"`, `plminipython_v8` | MiniPython 3.15 subset compiler + WebAssembly runtime on V8 |
| `pl_python3_v8/` | `pl_python3_v8` | `pl_python3_v8`, `"pl/python3+v8"`, `plfullpython_v8` | Full Python 3.15 AST compiler + WebAssembly runtime + Binary Slot Buffer SPI |
| `pl_micropython_v8/` | `pl_micropython_v8` | `pl_micropython_v8`, `"pl/micropython+v8"`, `plmicropython`, `"pl/micropython"` | MicroPython v1.24.1 WebAssembly runtime on V8 / QuickJS |
| `pl_datalog/` | `pl_datalog` | `pl_datalog`, `"pl/datalog"`, `datalog`, `pldatalog` | Stratified Datalog (semi-naive fixpoint + WASM bitset joins) on V8 |
| `pl_pgq/` | `pl_pgq` | `pl_pgq`, `"CREATE PROPERTY GRAPH"`, `property_graph`, `sqlpgq_v8` | ISO/IEC 9075-16 SQL/PGQ Property Graph DDL & `GRAPH_TABLE` compiler on V8 |
| `pl_jsonschema/` | `pl_jsonschema` | `pl_jsonschema`, `jsonschema` | JSON Schema Draft 2020-12 validator procedural language on V8 / QuickJS |
