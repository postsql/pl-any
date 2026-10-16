# Poor Man's SQL/PGQ (`pl-pgq`): Implementation Walk-Through & Patch Guide

This document provides a technical deep dive into the internal architecture of **`pl-pgq`** ("Poor Man's SQL/PGQ"), how it leverages **PL/v8 v4.0's custom language handler subsystem**, **WebAssembly**, and **PL/v8 v4.0's core dynamic table-macro & planner `prosupport` primitives** to implement ISO/IEC 9075-16:2023 (SQL/PGQ) as a **100% self-contained, user-installable pure SQL/JS/WASM (`pl/<lang>`) package with zero C files (`no .so` module)**—without modifying PostgreSQL's core C parser (`gram.y`).

---

## Part 1: Architectural Overview

### 1.1 Why a 100% Pure SQL/JS/WASM (`pl/<lang>`) Extension on Top of PL/v8 v4.0?

Upstream PostgreSQL 19's native SQL/PGQ implementation modifies the core bison grammar (`gram.y`), catalog tables (`pg_propgraph_*`), and query rewrite engine (`rewriteGraphTable.c`). While integrated into PG 19+, those changes cannot be installed as an extension on unmodified PostgreSQL servers or managed PostgreSQL services where users cannot compile and install custom C `.so` shared libraries per language extension.

By moving the generic low-level system primitives (parse-time `TupleDesc` inference, planner `prosupport` subquery inlining with `LATERAL` correlation, and runtime `RETURNS SETOF record` introspection / SPI streaming) into **core `pl/v8` v4.0**, **`pl-pgq` requires zero C files of its own** and ships as a single pure-SQL/JS/WASM script (`plpgq--1.0.sql`):

1. **Zero Core PostgreSQL Grammar Changes**: All SQL/PGQ syntax lives inside:
   - `CREATE FUNCTION ... RETURNS "PROPERTY GRAPH" LANGUAGE "CREATE PROPERTY GRAPH" AS $$ ... $$` (for DDL), and
   - `GRAPH_TABLE(graph_fn, 'MATCH ... WHERE ... COLUMNS (...)' [, jsonb_params])` (for queries).
2. **100% Self-Contained Pure SQL/JS/WASM Package**: The entire SQL/PGQ lexer, WebAssembly character classifier, DDL parser, catalog validator, `MATCH` parser, and SQL code generator are implemented in modular JavaScript + WebAssembly (~2,900 LOC across `src/*.js`) bundled into `plpgq--1.0.sql` (`plv8.packages` / `plv8.modules`).
3. **Reusable Core `pl/v8` Primitives for Any `pl/<lang>` or Plain `pl/v8` Function**: The C++ hooks in `plv8` (`plv8_source`, `plv8_call_support`, `plv8.register_column_inference()`, `plv8.register_support()`, `plv8.expected_columns()`, `plv8.return_query()`, `plv8.set_function_columns()`) are completely generic and available to any compiled-to-JS language or plain `pl/v8` function.

### 1.2 End-to-End Execution Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ 1. DDL Phase: CREATE FUNCTION my_graph() RETURNS "PROPERTY GRAPH"            │
│               LANGUAGE "CREATE PROPERTY GRAPH" AS $$ VERTEX TABLES ... $$    │
└───────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ PL/v8 v4.0 Language Handler (`plv8_compile_function` -> `pl-pgq` compiler)   │
│  • WasmLexer + Lexer tokenizes VERTEX/NODE & EDGE/RELATIONSHIP clauses       │
│  • DDLParser builds AST                                                      │
│  • CatalogValidator queries pg_class / pg_attribute / pg_constraint via SPI  │
│    - Auto-discovers PKs & FKs when omitted                                   │
│    - Validates all 18 PG 19 catalog & label consistency rules                │
│    - Resolves exact SQL type, typmod, and collation for every property       │
│  • Emits JS function returning frozen Graph Metadata JSONB object            │
└───────────────────────────────────────┬──────────────────────────────────────┘
                                        │
                                        ▼
┌──────────────────────────────────────────────────────────────────────────────┐
│ 2. Query Phase: SELECT * FROM GRAPH_TABLE(my_graph(), 'MATCH ... COLUMNS..') │
└───────────────────┬───────────────────────────────────────┬──────────────────┘
                    │                                       │
     (A) Parse-Time Type Input Hook          (B) Planner `prosupport` Hook
     (`plv8_source_in` in core `plv8.cc`)    (`plv8_call_support` in core `plv8.cc`)
                    │                                       │
                    ▼                                       ▼
┌───────────────────────────────────────┐ ┌────────────────────────────────────┐
│ • Calls registered JS callback        │ │ • Calls registered JS callback     │
│   `pgq_infer_columns_tsv`             │ │   `pgq_compile_graph_table_tsv`    │
│ • Inspects `debug_query_string` or    │ │ • Extracts `LATERAL` outer `Var`s  │
│   `pg_prepared_statements` to find    │ │   and substitutes `$1..$N`         │
│   the enclosing `GRAPH_TABLE(...)`    │ │ • Compiles `MATCH` AST via         │
│ • Compiles `MATCH` + `COLUMNS`        │ │   `SQLCodegen` (Section 6.5        │
│ • Dynamically updates `GRAPH_TABLE`'s │ │   `UNION ALL` + `WITH RECURSIVE`)  │
│   `proargtypes`/`proallargtypes`      │ │ • Emits `plv8_inline_helper_N`     │
│   (`OUT` parameters) or               │ │   and invokes PostgreSQL's         │
│   `plv8.plv8_single_col_holder`       │ │   `inline_set_returning_function`  │
│   BEFORE `ParseFuncOrColumn` builds   │ │ • Outer `WHERE`, `JOIN`, `ORDER BY`│
│   the `TupleDesc`!                    │ │   push down directly into base     │
│                                       │ │   vertex/edge B-tree indexes!      │
└───────────────────────────────────────┘ └────────────────────────────────────┘
```

---

## Part 2: Component-by-Component Walk-Through

### 2.1 Core `pl/v8` v4.0 Dynamic Table Function & Planner `prosupport` Subsystem (`plv8`)

To eliminate any extension-specific C code from `pl-pgq` and make dynamic table macros available to all `pl/<lang>` extensions and plain `pl/v8` functions, core `pl/v8` provides three integrated mechanisms in [`plv8.cc`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8.cc), [`plv8_func.cc`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8_func.cc), and [`plv8.sql.common`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8.sql.common):

1. **Runtime `RETURNS SETOF record` Introspection & Fast SPI Streaming ([`plv8_func.cc`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8_func.cc))**:
   - [`plv8_ExpectedColumns`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8_func.cc) (`plv8.expected_columns()`): Inspects `plv8_current_exec_env()->rsinfo->expectedDesc` (the call-site `TupleDesc` from `AS (col type, ...)` or `OUT` parameters) and returns an array of `{ name, type_oid, type_name, typmod, collation }` objects to JavaScript.
   - [`plv8_ReturnQuery`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8_func.cc) (`plv8.return_query(sql [, args])`): Executes a SQL query via `SPI_execute` / `SPI_execute_with_args`, resolves per-column type coercions against `rsinfo->expectedDesc->attrs[i]`, and appends all rows directly into the function's `tuplestorestate` in C++ without marshaling each row through V8 objects.
   - [`plv8_SetFunctionColumns`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8_func.cc) (`plv8.set_function_columns(func_name, cols)`): Programmatically updates a function's `OUT` parameters (`proargtypes`, `proallargtypes`, `proargmodes`, `proargnames`, `prorettype`) in `pg_proc`.

2. **Parse-Time Column Inference Hook (`plv8_source` + `plv8.register_column_inference()`)**:
   - Standard PostgreSQL requires `FROM some_srf(...) AS (col1 type1, ...)` when a function returns `SETOF record` without fixed `OUT` parameters.
   - Core `pl/v8` defines the base type `plv8_source` (with implicit casts from `text` and `varchar`) backed by [`plv8_source_in`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8.cc).
   - Because PostgreSQL's `ParseFuncOrColumn` evaluates constant type-input functions (`plv8_source_in`) **before** calling `get_expr_result_type` to construct the `RTE_FUNCTION` `TupleDesc`, `plv8_source_in` invokes any registered JavaScript column-inference callbacks (`plv8.register_column_inference(target_func_name, infer_callback_name)`):
     - **0 columns returned**: Resets the target function's `pg_proc` entry to `RETURNS SETOF record` with no `OUT` parameters so explicit `AS (col1 type1, ...)` clauses work normally.
     - **1 column returned**: Updates `plv8.plv8_single_col_holder`'s attribute in `pg_attribute` to `(col_name, type_oid, typmod, collation)` and sets the target function's `prorettype = plv8.plv8_single_col_holder` (working around PostgreSQL's rule that a function with 1 `OUT` parameter returns a scalar rather than a named 1-column composite tuple).
     - **$\ge 2$ columns returned**: Updates `proallargtypes`, `proargmodes` (`'i'` + `'o'`), and `proargnames` on the target function's `pg_proc` tuple and sets `prorettype = RECORDOID`, then flushes syscache via `CommandCounterIncrement()`.

3. **Planner `prosupport` Subquery Inlining with `LATERAL` Correlation (`plv8_call_support` + `plv8.register_support()`)**:
   - Functions annotated with `SUPPORT plv8_call_support` trigger [`plv8_call_support`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8.cc) during `SupportRequestInlineInFrom` (and `SupportRequestSimplify`).
   - `plv8_call_support` inspects the function's arguments, extracts any `LATERAL` outer `Var` expressions from a `jsonb_build_object('k1', outer.col1, ...)` argument, invokes the registered JS compiler callback (`plv8.register_support(target_func_name, support_callback_name)`), dynamically updates `plv8_inline_helper_N`'s `prosrc` to the generated SQL query, and delegates to PostgreSQL's native `inline_set_returning_function(root, helper_rte)`.

---

### 2.2 WebAssembly Character Classifier & SQL/PGQ Lexer (`src/wasm_lexer.js`, `src/lexer.js`)

- **[`src/wasm_lexer.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/wasm_lexer.js)**:
  - Contains a hand-assembled 199-byte WebAssembly binary (`WASM_CHAR_CLASSIFIER_BYTES`) compiled synchronously via `new WebAssembly.Module(...)` and `new WebAssembly.Instance(...)` inside V8.
  - Exports `classify_char(code: i32) -> i32`, classifying ASCII characters in branchless Wasm instructions into:
    - `1`: Whitespace (`' '`, `'\t'`, `'\n'`, `'\r'`, `'\f'`, `'\v'`)
    - `2`: Identifier start (`A-Z`, `a-z`, `_`, or `>= 128`)
    - `3`: Digit (`0-9`)
    - `4`: Single quote (`'`)
    - `5`: Double quote (`"`)
    - `6`: Operator / punctuation (`-`, `>`, `<`, `[`, `]`, `(`, `)`, `{`, `}`, `|`, `&`, `!`, `:`, `,`, `.`, `+`, `*`, `?`, `%`, `=`, `/`, `$`)
- **[`src/lexer.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/lexer.js)**:
  - Uses `WasmLexer.classifyChar` to scan SQL/PGQ input into a stream of tokens (`IDENT`, `NUMBER`, `STRING`, `PARAM`, `PUNCT`, `EOF`) annotated with exact byte offsets (`pos`).
  - Supports `--` line comments, nested `/* ... */` block comments, doubled `''` / `""` escapes, `$tag$...$tag$` dollar-quoted strings, `$1` positional parameters, and multi-character operators (`->`, `<-`, `::`, `<=`, `>=`, `<>`, `!=`, `||`).

---

### 2.3 `CREATE PROPERTY GRAPH` Parser & PG 19 Catalog Validator (`src/ddl_parser.js`, `src/catalog.js`)

- **[`src/ddl_parser.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/ddl_parser.js)**:
  - Recursive-descent parser for the body of `LANGUAGE "CREATE PROPERTY GRAPH"` functions.
  - Accepts optional leading `CREATE [TEMP|TEMPORARY] PROPERTY GRAPH <name>` headers or direct `VERTEX TABLES (...)` / `NODE TABLES (...)` + `EDGE TABLES (...)` / `RELATIONSHIP TABLES (...)` definitions.
  - Parses element table aliases (`table_name AS alias`), explicit `KEY (...)` or omitted keys, edge `SOURCE KEY (...) REFERENCES vertex_table [(...)]` and `DESTINATION KEY (...) REFERENCES vertex_table [(...)]` (or `REFERENCES vertex_table VIA fk_constraint_name`), `DEFAULT LABEL`, multiple `LABEL <name>` clauses, `NO PROPERTIES`, `PROPERTIES ALL [COLUMNS] [EXCEPT (...)]`, and `PROPERTIES (expr [AS prop_name], ...)`.
- **[`src/catalog.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/catalog.js)**:
  - Queries `pg_class`, `pg_namespace`, `pg_attribute`, `pg_constraint`, and `pg_type` via `plv8.execute`.
  - **Key Auto-Discovery**:
    - When `KEY (...)` is omitted on a vertex or edge table, queries `pg_constraint` (`contype = 'p'`) to find the primary key.
    - When `KEY (...)` is omitted on a `SOURCE` or `DESTINATION` endpoint, queries `pg_constraint` (`contype = 'f'`) between the edge relation and the referenced vertex relation.
  - **Expression Type & Collation Inference**:
    - For `PROPERTIES (expr AS alias)`, executes `SELECT pg_typeof(expr)::oid AS type_oid, pg_typeof(expr)::text AS type_name, format_type(pg_typeof(expr), NULL) AS formatted_type, pg_collation_for(expr) ... FROM schema.rel LIMIT 0` (falling back cleanly for non-collatable types).
  - **Full PG 19 Semantic Validation**:
    - Enforces all 18 error conditions tested by PostgreSQL 19's `create_property_graph.sql` (duplicate vertex/edge aliases, duplicate labels per element, duplicate property names per label, `EXCEPT` column validation, cross-element property count & name set mismatches for shared labels, and cross-element property data type / typmod / collation mismatches).

---

### 2.4 `GRAPH_TABLE` `MATCH` Parser & SQL Code Generator (`src/match_parser.js`, `src/codegen_sql.js`)

- **[`src/match_parser.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/match_parser.js)**:
  - Parses `[MATCH] <path_pattern_list> [WHERE <expr>] [COLUMNS (<col_item>, ...)]`.
  - Supports path modes (`WALK`, `TRAIL`, `ACYCLIC`, `SIMPLE`), shortest/cheapest path selectors (`ANY SHORTEST`, `ALL SHORTEST`, `ANY CHEAPEST`, `ALL CHEAPEST`), parenthesized subpath patterns with `WHERE` and `COST` clauses, quantifiers (`+`, `*`, `?`, `{m,n}`, `{m,}`), label boolean expressions (`|`, `&`, `!`, `%`), and `COLUMNS` projections (`v.prop`, `v.*`, general expressions with `ELEMENT_NUMBER(v)`, `PATH_LENGTH(p)`, `COST(p)`, `COUNT(*)`, `CASE WHEN ...`).
- **[`src/codegen_sql.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/codegen_sql.js)**:
  - **Step 1: Factor Analysis & Candidate Element Resolution**:
    - Splits the path into alternating vertex and edge factors (and quantified subpath steps).
    - Evaluates each factor's boolean label expression (`evalLabelExpr`) against the property graph's vertex/edge tables.
    - Collects all referenced properties for each variable so only required columns are projected.
  - **Step 2: SQL/PGQ Section 6.5 Multi-Label Table Unions (`buildElementSourceSQL`)**:
    - If a vertex or edge variable matches a single underlying table, emits a direct table reference (`schema.table AS __el_0`)—enabling zero-overhead index scans.
    - If a variable matches multiple underlying tables (e.g., `(a IS l1 | l2)`), emits a `UNION ALL` subquery where every branch projects:
      - `__elem_id`: Composite `jsonb_build_array('elem_alias', key_cols...)` for cyclic variable identity and `ELEMENT_NUMBER()` compatibility.
      - `__src_key_0..k` and `__dst_key_0..k` (for edges) or `__key_0..k` (for vertices).
      - Union of all referenced properties across the matched labels, using typed `NULL::type` padding for properties absent from a specific table branch.
  - **Step 3: Fixed-Length Join & Cyclic Variable Unification**:
    - Joins consecutive `vertex_i -> edge_i -> vertex_{i+1}` factors on their source/destination keys (handling `->`, `<-`, and undirected `-` via dual-direction `UNION ALL` with self-loop deduplication).
    - If the same variable name `v` appears multiple times in a pattern (e.g., `(a)->(b)->(a)`), unifies their identity (`__el_0.__key = __el_2.__key` or `__elem_id` equality) and binds property references to the canonical first occurrence.
  - **Step 4: Quantified Paths, Shortest Paths, and Cheapest Paths (`WITH RECURSIVE`)**:
    - Generates a recursive CTE (`__pgq_qpath_i`) that tracks `__src_key`, `__dst_key`, `__depth`, `__cost`, and `__visited` (`ARRAY[...]` for `TRAIL`/`ACYCLIC`/`SIMPLE` cycle prevention).
    - For `ANY SHORTEST` / `ANY CHEAPEST`, applies `DISTINCT ON (__src_key, __dst_key)` ordered by `__depth ASC` or `__cost ASC` inside the CTE and outer selection so PostgreSQL prunes suboptimal paths early.

---

### 2.5 How `pl-pgq` Wires Into Core `pl/v8` (`src/index.js` & `plpgq.sql.in`)

In [`src/index.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/index.js) and [`plpgq.sql.in`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/plpgq.sql.in):

1. **Custom Domain over `plv8_source`**:
   ```sql
   CREATE DOMAIN pgq_pattern AS plv8_source;
   ```
   Because `pgq_pattern` is a domain over `plv8_source`, passing a string literal as the second argument of `GRAPH_TABLE(graph, 'MATCH ...')` automatically triggers `plv8_source_in` during parse analysis.
2. **Registering Parse-Time Inference & Planner Inlining Callbacks**:
   At module load time in [`src/index.js`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/src/index.js), `pl-pgq` registers its two SQL/JS callbacks with core `pl/v8`:
   ```javascript
   if (typeof plv8 !== 'undefined') {
     if (typeof plv8.register_column_inference === 'function') {
       plv8.register_column_inference('graph_table', 'pgq_infer_columns_tsv');
     }
     if (typeof plv8.register_support === 'function') {
       plv8.register_support('graph_table', 'pgq_compile_graph_table_tsv');
     }
   }
   ```
3. **`GRAPH_TABLE` Declarations in Pure SQL (`LANGUAGE plv8 SUPPORT plv8_call_support`)**:
   ```sql
   CREATE OR REPLACE FUNCTION GRAPH_TABLE(graph "PROPERTY GRAPH", pattern pgq_pattern)
   RETURNS SETOF record
   LANGUAGE plv8 STABLE SUPPORT plv8_call_support AS $$
     const mod = plv8.find_function('__plpgq_boot')();
     mod.executeGraphTableRuntime(graph, pattern, null);
   $$;
   ```
   When the planner inlines `GRAPH_TABLE` via `plv8_call_support`, the query is replaced by the compiled relational SQL subquery (`plv8_inline_helper_N`). If planner inlining does not apply (e.g., non-constant graph/pattern arguments at runtime), `executeGraphTableRuntime` uses `plv8.expected_columns()` and `plv8.return_query()` to execute the compiled SQL directly via C++ SPI streaming.

---

## Part 3: Patch List & Explanation of What Each Patch Does

### Part A: Core `pl/v8` Patch ([`plv8/patches/`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/patches/))

| Patch File | Subject | Files Modified |
| :--- | :--- | :--- |
| [`0001-Core-plv8-dynamic-table-function-and-planner-prosupp.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/patches/0001-Core-plv8-dynamic-table-function-and-planner-prosupp.patch) | Core `pl/v8` dynamic table function (`RETURNS SETOF record`), parse-time column inference (`plv8_source`), and planner `prosupport` inlining (`plv8_call_support`) | `Makefile`, `plv8.h`, `plv8_func.cc`, `plv8.cc`, `plv8.sql.common`, `sql/table_macro_support.sql`, `expected/table_macro_support.out`, `docs/LANGUAGE_HANDLER_DESIGN.md`, `docs/LANGUAGE_HANDLER_USER_GUIDE.md` |

- **What it does**:
  - Adds `plv8.expected_columns()`, `plv8.return_query(sql [, args])`, `plv8.set_function_columns(func_name, cols)`, `plv8.register_column_inference(func_name, infer_sql_fn)`, and `plv8.register_support(func_name, support_sql_fn)` in [`plv8_func.cc`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8_func.cc) and [`plv8.cc`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8.cc).
  - Adds the `plv8_source` scalar type (`plv8_source_in` / `plv8_source_out`), `plv8.plv8_single_col_holder` composite type, `plv8_call_support(internal)` planner support hook, and `plv8_inline_helper_0..7` SQL helper functions in [`plv8.sql.common`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/plv8.sql.common).
  - Adds regression test suite [`sql/table_macro_support.sql`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/sql/table_macro_support.sql) and documentation in [`docs/LANGUAGE_HANDLER_DESIGN.md`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/docs/LANGUAGE_HANDLER_DESIGN.md) and [`docs/LANGUAGE_HANDLER_USER_GUIDE.md`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/plv8/docs/LANGUAGE_HANDLER_USER_GUIDE.md).

---

### Part B: `pl-pgq` Extension Patch Series ([`pl-pgq/patches/`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/))

The `pl-pgq` extension is organized into 7 self-contained, chronological patches in [`/google/src/cloud/hannuk/port_plv8_to_pljs/google3/{scratch}/pl-pgq/patches/`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/) (plus a single combined patch `plpgq_combined.patch`):

| Patch File | Phase / Subject | Files Modified |
| :--- | :--- | :--- |
| [`0001-Phase-1-Extension-skeleton-PGXS-build-and-PL-v8-v4.0.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0001-Phase-1-Extension-skeleton-PGXS-build-and-PL-v8-v4.0.patch) | Phase 1: Pure SQL/JS/WASM extension skeleton, PGXS build, and PL/v8 v4.0 bindings | `Makefile`, `plpgq.control`, `pl_pgq.control`, `pl-pgq.control`, `scripts/build_bundle.py`, `plpgq.sql.in` |
| [`0002-Phase-2-WebAssembly-character-classifier-and-SQL-PGQ.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0002-Phase-2-WebAssembly-character-classifier-and-SQL-PGQ.patch) | Phase 2: WebAssembly character classifier and SQL/PGQ lexical scanner | `src/wasm_lexer.js`, `src/lexer.js` |
| [`0003-Phase-3-CREATE-PROPERTY-GRAPH-DDL-parser-and-PG-19-c.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0003-Phase-3-CREATE-PROPERTY-GRAPH-DDL-parser-and-PG-19-c.patch) | Phase 3: `CREATE PROPERTY GRAPH` DDL parser and PG 19 catalog validator | `src/ddl_parser.js`, `src/catalog.js`, `sql/01_create_property_graph.sql`, `expected/01_create_property_graph.out` |
| [`0004-Phase-4-GRAPH_TABLE-MATCH-path-pattern-parser.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0004-Phase-4-GRAPH_TABLE-MATCH-path-pattern-parser.patch) | Phase 4: `GRAPH_TABLE` `MATCH` path pattern parser | `src/match_parser.js` |
| [`0005-Phase-5-SQL-PGQ-to-SQL-compiler-Section-6.5-unions-a.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0005-Phase-5-SQL-PGQ-to-SQL-compiler-Section-6.5-unions-a.patch) | Phase 5: SQL/PGQ-to-SQL compiler, Section 6.5 unions, and recursive shortest/cheapest paths | `src/codegen_sql.js`, `src/index.js`, `sql/02_graph_table_pg19.sql`, `expected/02_graph_table_pg19.out`, `sql/03_quantified_shortest_paths.sql`, `expected/03_quantified_shortest_paths.out` |
| [`0006-Phase-6-Inlining-LATERAL-correlation-and-security-ro.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0006-Phase-6-Inlining-LATERAL-correlation-and-security-ro.patch) | Phase 6: Planner inlining, `LATERAL` correlation, and security roles regression suites | `sql/04_inlining_and_lateral.sql`, `expected/04_inlining_and_lateral.out`, `sql/05_security_roles.sql`, `expected/05_security_roles.out` |
| [`0007-Phase-7-Documentation-User-Guide-and-Implementation-.patch`](file:///google/src/cloud/hannuk/port_plv8_to_pljs/google3/%7Bscratch%7D/pl-pgq/patches/0007-Phase-7-Documentation-User-Guide-and-Implementation-.patch) | Phase 7: Documentation, User Guide, and Implementation Walk-Through | `README.md`, `docs/USER_GUIDE.md`, `docs/IMPLEMENTATION_WALKTHROUGH.md` |
