# `plpgsql_v8`: PL/pgSQL-to-JavaScript Transpiler & Runtime on V8

## Design Document & Implementation Walk-Through

---

## Table of Contents

- [Part I: High-Level Design](#part-i-high-level-design)
  - [1. Overview & Motivation](#1-overview--motivation)
  - [2. Goals & Non-Goals](#2-goals--non-goals)
  - [3. System Architecture](#3-system-architecture)
  - [4. End-to-End Compilation & Execution Pipeline](#4-end-to-end-compilation--execution-pipeline)
- [Part II: Detailed Design](#part-ii-detailed-design)
  - [5. C++ `plv8` Engine Enhancements](#5-c-plv8-engine-enhancements)
    - [5.1 Language Handler Chaining & Dependency Tracking](#51-language-handler-chaining--dependency-tracking)
    - [5.2 Opt-In Raw Byte Passing (`pass_user_types_as_bytes`)](#52-opt-in-raw-byte-passing-pass_user_types_as_bytes)
    - [5.3 Rich PostgreSQL Error Diagnostics Across Subtransactions](#53-rich-postgresql-error-diagnostics-across-subtransactions)
    - [5.4 Subtransaction Safety Across SPI Prepare, Plan, and Cursor Operations](#54-subtransaction-safety-across-spi-prepare-plan-and-cursor-operations)
  - [6. Lexical Analysis (`tokenize`)](#6-lexical-analysis-tokenize)
  - [7. Catalog Introspection & Lexical Scope Architecture](#7-catalog-introspection--lexical-scope-architecture)
    - [7.1 Catalog Metadata Resolution](#71-catalog-metadata-resolution)
    - [7.2 Scope Stack, Labels, and Variable Naming](#72-scope-stack-labels-and-variable-naming)
    - [7.3 Composite, Rowtype, Record, and `%TYPE` Variables](#73-composite-rowtype-record-and-type-variables)
  - [8. Hybrid Expression Compilation & Runtime Semantics](#8-hybrid-expression-compilation--runtime-semantics)
    - [8.1 Fast-Path Pure-JavaScript Recursive-Descent Compiler](#81-fast-path-pure-javascript-recursive-descent-compiler)
    - [8.2 Automatic Parameterized SQL Fallback](#82-automatic-parameterized-sql-fallback)
    - [8.3 SQL Three-Valued Logic (3VL) and NULL Semantics](#83-sql-three-valued-logic-3vl-and-null-semantics)
    - [8.4 64-Bit `BigInt` Arithmetic & Static Integer vs Float Division](#84-64-bit-bigint-arithmetic--static-integer-vs-float-division)
    - [8.5 1-Based Array Indexing, Slicing, and Copy-on-Write Mutation](#85-1-based-array-indexing-slicing-and-copy-on-write-mutation)
  - [9. Context-Aware SQL Token Rewriting](#9-context-aware-sql-token-rewriting)
    - [9.1 Parameterized Binding Model](#91-parameterized-binding-model)
    - [9.2 Disambiguating PL/pgSQL Variables from SQL Column Identifiers](#92-disambiguating-plpgsql-variables-from-sql-column-identifiers)
  - [10. Subtransaction & Exception Architecture](#10-subtransaction--exception-architecture)
    - [10.1 Mapping `BEGIN ... EXCEPTION` to `plv8.subtransaction()`](#101-mapping-begin--exception-to-plv8subtransaction)
    - [10.2 Non-Local Control Unwinding (`__ctrl`) Without Rolling Back](#102-non-local-control-unwinding-__ctrl-without-rolling-back)
    - [10.3 Condition Matching (`COND_MAP`) and Lexical Stacked Diagnostics](#103-condition-matching-cond_map-and-lexical-stacked-diagnostics)
  - [11. Cursors, Set-Returning Functions, Procedures, and Triggers](#11-cursors-set-returning-functions-procedures-and-triggers)
    - [11.1 Bound and Unbound Cursors](#111-bound-and-unbound-cursors)
    - [11.2 Set-Returning Functions (`RETURN NEXT`, `RETURN QUERY`, `RETURNS TABLE`)](#112-set-returning-functions-return-next-return-query-returns-table)
    - [11.3 Stored Procedures (`OUT`/`INOUT` and Transaction Control)](#113-stored-procedures-outinout-and-transaction-control)
    - [11.4 Trigger Functions (`NEW`, `OLD`, `TG_*`, 0-Indexed `TG_ARGV`)](#114-trigger-functions-new-old-tg_-0-indexed-tg_argv)
  - [12. Security & Isolation Model](#12-security--isolation-model)
- [Part III: Implementation Walk-Through](#part-iii-implementation-walk-through)
  - [13. Source File Map](#13-source-file-map)
  - [14. Walk-Through of C++ Engine Changes (`plv8.h`, `plv8.cc`, `plv8_func.cc`)](#14-walk-through-of-c-engine-changes-plv8h-plv8cc-plv8_funccc)
  - [15. Walk-Through of the `plpgsql_v8` Compiler & Runtime (`plv8.sql.common`)](#15-walk-through-of-the-plpgsql_v8-compiler--runtime-plv8sqlcommon)
  - [16. End-to-End Transpilation Examples](#16-end-to-end-transpilation-examples)
  - [17. Regression Test Suite Walk-Through (`sql/plpgsql_v8.sql`)](#17-regression-test-suite-walk-through-sqlplpgsql_v8sql)

---

# Part I: High-Level Design

## 1. Overview & Motivation

PostgreSQL's built-in `plpgsql` procedural language executes functions using an AST interpreter tightly coupled to the PostgreSQL Server Programming Interface (SPI). In native `plpgsql`, even simple scalar arithmetic, boolean conditions, and loop bounds are frequently evaluated as SPI expressions or SQL plans, and procedural control flow runs through an interpreted statement walker.

`plpgsql_v8` (`CREATE TRUSTED LANGUAGE plpgsql_v8`) is a full-featured PL/pgSQL-to-JavaScript compiler and runtime built directly on top of `plv8`'s chained language handler architecture. When a function, procedure, trigger, or `DO` block is written in `LANGUAGE plpgsql_v8`:

1. The PL/pgSQL source is tokenized and parsed by a compiler (`plv8_plpgsql_handler`) written in JavaScript running inside V8.
2. Procedural control flow (`IF`, `CASE`, `LOOP`, `WHILE`, integer `FOR`, `FOREACH`, `EXIT`, `CONTINUE`), local variable assignments, array indexing/slicing, composite field access, and pure expressions are compiled directly into native JavaScript statements and expressions JIT-compiled by V8—eliminating SPI call overhead for compute-intensive logic.
3. Embedded static SQL (`SELECT ... INTO`, `INSERT`, `UPDATE`, `DELETE`, `PERFORM`, `FOR r IN SELECT ...`, `RETURN QUERY`), dynamic SQL (`EXECUTE ... INTO ... USING`), and cursors (`OPEN`, `FETCH`, `MOVE`, `CLOSE`) are rewritten into parameterized `plv8.execute()` / `plv8.prepare()` calls with automatic variable binding.
4. `BEGIN ... EXCEPTION WHEN ... END` blocks map directly onto `plv8.subtransaction()`, backed by full PostgreSQL `ErrorData` diagnostic propagation (`SQLSTATE`, `SQLERRM`, `DETAIL`, `HINT`, `CONTEXT`, `SCHEMA_NAME`, `TABLE_NAME`, `COLUMN_NAME`, `DATATYPE_NAME`, `CONSTRAINT_NAME`).

---

## 2. Goals & Non-Goals

### Goals
- **High Compatibility with PostgreSQL PL/pgSQL**: Support standard PL/pgSQL block structure, nested `DECLARE` scopes, `<<label>>` qualification, `%TYPE` / `%ROWTYPE` / `RECORD`, `ALIAS FOR`, `CONSTANT`, `NOT NULL`, `DEFAULT`, static and dynamic SQL, `SELECT INTO [STRICT]`, `PERFORM`, `IF`/`CASE`/`LOOP`/`WHILE`/`FOR`/`FOREACH`, `EXIT`/`CONTINUE` with labels and `WHEN`, `EXCEPTION` blocks with condition names and `SQLSTATE` codes, `RAISE` (including `USING` options and bare re-raise), `ASSERT`, `GET [CURRENT | STACKED] DIAGNOSTICS`, bound and unbound cursors, set-returning functions (`RETURN NEXT`, `RETURN QUERY`, `RETURNS TABLE`), procedures (`OUT`/`INOUT`, `COMMIT`/`ROLLBACK`), triggers (`NEW`, `OLD`, `TG_*`), and inline `DO` blocks.
- **V8 JIT Acceleration for Procedural & Expression Logic**: Compile scalar arithmetic, 64-bit `bigint` operations, string concatenation, comparisons, three-valued boolean logic, 1-based array indexing/slicing, and common SQL built-ins directly to JavaScript without round-tripping through SPI.
- **Seamless SQL Fallback**: Whenever an expression uses a SQL construct or SQL function not handled by the pure-JS fast path, automatically fall back to a parameterized `SELECT (<expr>) AS __val` via SPI with all referenced PL/pgSQL variables bound as `$1, $2, ...`.
- **Zero-Copy / Native Type Conversion**: Preserve `plv8`'s native JS-to-Postgres type conversions for composite types, arrays, JSON/JSONB, numerics, timestamps, and scalars.
- **Inspectability**: Provide `plv8.compile_plpgsql(src, meta)` so developers can inspect the exact JavaScript generated for any PL/pgSQL function body.

### Non-Goals
- **Replacing the PostgreSQL SQL Parser for Arbitrary DDL/DML**: `plpgsql_v8` does not re-implement the PostgreSQL SQL planner or executor. All SQL queries and DML/DDL statements are executed by PostgreSQL's native SPI engine; `plpgsql_v8` performs lexical token rewriting only to bind PL/pgSQL variables safely as `$1, $2, ...` parameters.

---

## 3. System Architecture

`plpgsql_v8` leverages `plv8`'s **Chained Language Handler** mechanism. In PostgreSQL, a procedural language is registered in `pg_catalog.pg_language` with a call handler function (`lanplcallfoid`), an optional inline handler (`laninline`), and an optional validator (`lanvalidator`).

For `plpgsql_v8`:
- `HANDLER` is `plv8_plpgsql_handler()` (whose own language in `pg_proc` is `plv8`).
- `INLINE` is `plv8_inline_handler` (a C++ function in `plv8.so`).
- `VALIDATOR` is `plv8_call_validator` (a C++ function in `plv8.so`).

```
+-----------------------------------------------------------------------------------+
| PostgreSQL Backend                                                                |
|                                                                                   |
|  CREATE FUNCTION foo(...) LANGUAGE plpgsql_v8                                     |
|  DO $$ ... $$ LANGUAGE plpgsql_v8                                                 |
|         |                                                                         |
|         v                                                                         |
|  +-----------------------------------------------------------------------------+  |
|  | plv8 C++ Engine (plv8.cc / plv8_func.cc)                                    |  |
|  |                                                                             |  |
|  |  1. plv8_call_validator / plv8_call_handler / plv8_inline_handler           |  |
|  |  2. plv8_transpile_src():                                                   |  |
|  |     - Walks pg_language -> lanplcallfoid -> pg_proc chain                   |  |
|  |     - Discovers plv8_plpgsql_handler() (written in LANGUAGE plv8)           |  |
|  |     - Records (fn_oid, xmin, tid) in plv8_proc_cache.handlers[]             |  |
|  |     - Invokes plv8_plpgsql_handler(raw_prosrc, meta) inside V8              |  |
|  +--------------------------------------+--------------------------------------+  |
|                                         |                                         |
|                                         v                                         |
|  +-----------------------------------------------------------------------------+  |
|  | V8 Isolate (per PostgreSQL user)                                            |  |
|  |                                                                             |  |
|  |  +-----------------------------------------------------------------------+  |  |
|  |  | plv8_plpgsql_handler (plv8.sql.common)                                |  |  |
|  |  |  - ensureRuntime(): installs globalThis.__plpgsql_v8_rt               |  |  |
|  |  |  - tokenize(src): lexical scanner                                     |  |  |
|  |  |  - compilePlpgsql(src, meta):                                         |  |  |
|  |  |      * Queries pg_proc / pg_type for signature & composite types      |  |  |
|  |  |      * Parses DECLARE, blocks, control flow, SQL, exceptions          |  |  |
|  |  |      * Compiles pure expressions to JS or parameterized evalSql       |  |  |
|  |  |      * Rewrites static SQL tokens with context-aware $N bindings      |  |  |
|  |  |      * Emits JS function body string                                  |  |  |
|  |  +-----------------------------------+-----------------------------------+  |  |
|  |                                      |                                      |  |
|  |                                      v                                      |  |
|  |  +-----------------------------------------------------------------------+  |  |
|  |  | Compiled JS Function (cached in plv8_proc_cache->function)            |  |  |
|  |  |  - Executes control flow & pure expressions natively in V8            |  |  |
|  |  |  - Calls __plpgsql_v8_rt helpers (3VL, BigInt, arrays, diagnostics)   |  |  |
|  |  |  - Calls plv8.execute / prepare / subtransaction / return_next        |  |  |
|  |  +-----------------------------------------------------------------------+  |  |
|  +-----------------------------------------------------------------------------+  |
+-----------------------------------------------------------------------------------+
```

---

## 4. End-to-End Compilation & Execution Pipeline

1. **Creation / Validation (`CREATE FUNCTION ... LANGUAGE plpgsql_v8`)**:
   - PostgreSQL invokes `plv8_call_validator(fn_oid)`.
   - `plv8_call_validator` looks up the function's `prolang` (`plpgsql_v8`), calls `plv8_get_proc` -> `plv8_transpile_src`, which executes `plv8_plpgsql_handler(prosrc, meta)`.
   - `plv8_plpgsql_handler` queries `pg_catalog.pg_proc` for `meta.fn_oid` to obtain parameter names, modes (`IN`, `OUT`, `INOUT`, `VARIADIC`, `TABLE`), types, return type, `proretset`, and `prokind`.
   - `compilePlpgsql` transpiles the PL/pgSQL source into a JavaScript function body and returns it to `plv8_transpile_src`.
   - `CompileFunction` wraps the returned body into `function(<args>) { <body> }` and compiles it via V8's `Script::Compile`. Syntax or compilation errors are reported immediately at `CREATE FUNCTION` time.
2. **First Call (`SELECT my_func(...)` or `CALL my_proc(...)`)**:
   - PostgreSQL sees `lanplcallfoid = plv8_plpgsql_handler`. Because `plv8_plpgsql_handler` itself has `prolang = plv8`, PostgreSQL's `fmgr_info` resolves its C entry point to `plv8_call_handler`.
   - `plv8_call_handler` compiles (if not already cached) and caches the resulting V8 `v8::Persistent<v8::Function>` in `plv8_proc_cache` keyed by `fn_oid` and the current `plv8_user` V8 isolate.
3. **Subsequent Calls**:
   - `plv8_call_handler` finds the compiled V8 function in `plv8_proc_cache`, verifies that neither the function's own `pg_proc` tuple nor any handler in `cache->handlers[]` has changed (`xmin`/`tid` check), marshals the PostgreSQL `FunctionCallInfo` arguments into V8 values, and invokes the compiled JS function directly with zero re-transpilation overhead.
4. **Inline `DO` Blocks (`DO $$ ... $$ LANGUAGE plpgsql_v8`)**:
   - PostgreSQL calls `plv8_inline_handler(InlineCodeBlock *codeblock)`.
   - `plv8_inline_handler` calls `plv8_transpile_src(codeblock->source_text, codeblock->langOid, NULL, NULL, NULL)` (passing `proc = NULL`, so `plv8_plpgsql_handler` receives `(raw_prosrc)` and defaults `meta = {}`), compiles the returned JS into an anonymous V8 function, and executes it immediately.

---

# Part II: Detailed Design

## 5. C++ `plv8` Engine Enhancements

Supporting full PL/pgSQL semantics on top of `plv8` required four foundational enhancements to the C++ `plv8` engine in `plv8.h`, `plv8.cc`, and `plv8_func.cc`.

### 5.1 Language Handler Chaining & Dependency Tracking

In `plv8.cc`, `plv8_transpile_src` supports arbitrary chains of language handlers (up to `PLV8_MAX_LANG_HANDLER_DEPTH = 32`, defined at `plv8.h:320`):

- Given a function with `prolang = lang_oid` (or an inline `DO` block with `codeblock->langOid`), `plv8_transpile_src` looks up the OID of the base `"plv8"` language (`plv8_lang_oid`) and walks `pg_language.lanplcallfoid -> pg_proc.prolang` while `cur_lang_oid != plv8_lang_oid`.
- Each intermediate JS handler function's `(fn_oid, fn_xmin, fn_tid)` is recorded in `deps[]` and copied into `plv8_proc_cache::handlers[]`.
- On every subsequent call (`plv8_call_handler`), `plv8_cache_handlers_valid()` verifies that every handler in the chain still exists in `pg_proc` with matching `xmin` and `tid`.
- Furthermore, whenever a function is validated by `plv8_call_validator`, `plv8_cache_function_remove(fn_oid)` scans the current user's `ProcCacheHash` and evicts both `fn_oid` and any cached downstream functions whose `handlers[]` array depends on `fn_oid`.

Before invoking the language's handler (`find_js_function(lang_handler_oid)`):
- For catalog functions (`proc != NULL && proc->cache != NULL`), `plv8_transpile_src` builds a `meta` JS object (`call_argc = 2`) containing:
  `fn_oid`, `proname`, `rettype_oid`, `rettype_category`, `rettype_len`, `argtype_oids`, `argtype_categories`, `argtype_lens`, and `retset`.
- For inline `DO` blocks (`proc == NULL`), `call_argc = 1` and `meta` is omitted (`plv8_plpgsql_handler` defaults `meta = {}`).

### 5.2 Opt-In Raw Byte Passing (`pass_user_types_as_bytes`)

Originally, `plv8` enabled `pass_user_types_as_bytes` unconditionally whenever `nhandlers > 0` (designed for `pl/v8-wasm` where user-defined composite types are marshaled as raw byte buffers). However, high-level transpiled languages like `plpgsql_v8` and `sqltsm_v8` expect composite types, domains, and user types to be converted using `plv8`'s standard JS object / scalar conversions.

To support both models cleanly:
- `plv8_transpile_src` initializes `pass_bytes = (strcmp(langname, "pl/v8-wasm") == 0)`.
- After the JS language handler runs `(src, meta)`, `plv8_transpile_src` checks whether the handler explicitly set `meta.pass_user_types_as_bytes` to a boolean (`true` or `false`), overriding the default.
- The resulting boolean is stored in `cache->pass_user_types_as_bytes` and scoped via `PassUserTypesScope` during both argument conversion and return-value marshaling in `plv8_call_handler`.

### 5.3 Rich PostgreSQL Error Diagnostics Across Subtransactions

PL/pgSQL requires full access to PostgreSQL error metadata in three places:
1. `EXCEPTION WHEN <condition> THEN` matching against five-character `SQLSTATE` codes or condition names.
2. `GET STACKED DIAGNOSTICS` inside an exception handler (`RETURNED_SQLSTATE`, `MESSAGE_TEXT`, `PG_EXCEPTION_DETAIL`, `PG_EXCEPTION_HINT`, `PG_EXCEPTION_CONTEXT`, `SCHEMA_NAME`, `TABLE_NAME`, `COLUMN_NAME`, `PG_DATATYPE_NAME`, `CONSTRAINT_NAME`).
3. Re-raising a caught exception (`RAISE;`) or throwing a custom exception (`RAISE EXCEPTION ... USING ERRCODE = ..., DETAIL = ..., HINT = ..., COLUMN = ..., CONSTRAINT = ..., DATATYPE = ..., TABLE = ..., SCHEMA = ...`) that preserves all diagnostic fields when escaping back to PostgreSQL or across nested `plv8.subtransaction()` calls.

To make this work end-to-end:
- **`plv8_FunctionInvoker` (`plv8_func.cc`)**: When a C++ `pg_error` is caught from SPI, `CopyErrorData()` extracts:
  - `edata->sqlerrcode` (integer `MAKE_SQLSTATE`) and `unpack_sql_state(edata->sqlerrcode)` (5-character string, e.g. `'23505'`).
  - `edata->message`, `edata->detail`, `edata->hint`, `edata->context`, `edata->schema_name`, `edata->table_name`, `edata->column_name`, `edata->datatype_name`, `edata->constraint_name`, `edata->internalquery`, `edata->internalpos`.
  - All of these are attached as properties (`sqlerrcode`, `code`, `detail`, `hint`, `context`, `schema_name`, `table_name`, `column_name`, `datatype_name`, `constraint_name`, `internalquery`, `internalpos`) on the V8 `Error` exception object thrown into JavaScript.
- **`js_error` (`plv8.h`, `plv8.cc`)**:
  - Extended with `m_code` (integer `sqlerrcode`) and string fields `m_detail`, `m_hint`, `m_context`, `m_schema_name`, `m_table_name`, `m_column_name`, `m_datatype_name`, `m_constraint_name`, `m_internalquery`, and `m_internalpos`.
  - `js_error::init()` parses `err.code` or `err.sqlerrcode` (accepting either a 5-character `SQLSTATE` string via `plv8_parse_sqlerrcode` or an integer `MAKE_SQLSTATE` value) and extracts all optional diagnostic string properties via `plv8_extract_err_string_field`.
  - `js_error::error_object()` reconstructs a V8 `Error` object with all diagnostic properties intact when a `js_error` caught inside `plv8_Subtransaction` is re-thrown as a JS exception to the caller of `plv8.subtransaction()`.
  - `js_error::rethrow()` and `js_error::log()` pass all populated fields back to PostgreSQL's `ereport()` using `errcode(m_code ? m_code : ERRCODE_EXTERNAL_ROUTINE_EXCEPTION)`, `errdetail`, `errhint`, `errcontext`, and `err_generic_string(PG_DIAG_*, ...)`.

### 5.4 Subtransaction Safety Across SPI Prepare, Plan, and Cursor Operations

Previously, only `plv8_Execute` wrapped its SPI execution in a `SubTranBlock`. If an error occurred during `plv8.prepare()`, `plan.execute()`, `plan.cursor()`, `cursor.fetch()`, `cursor.move()`, or `cursor.close()`, the PostgreSQL error jumped directly out of the transaction without rolling back a subtransaction, leaving SPI in an aborted state even if the JavaScript caller wrapped the call in a `try / catch` or `plv8.subtransaction()`.

In `plv8_func.cc`, `SubTranBlock` protection was added around:
- `plv8_Prepare` (`SPI_prepare_params` / `SPI_prepare` + `SPI_saveplan` + `SPI_freeplan`)
- `plv8_PlanCursor` (`SPI_cursor_open_with_paramlist` / `SPI_cursor_open`)
- `plv8_PlanExecute` (`SPI_execute_plan_with_paramlist` / `SPI_execute_plan`)
- `plv8_CursorFetch` (`SPI_cursor_fetch`)
- `plv8_CursorMove` (`SPI_cursor_move`)
- `plv8_CursorClose` (`SPI_cursor_close`)

This guarantees that any SQL error during plan preparation, execution, or cursor manipulation can be cleanly trapped by `BEGIN ... EXCEPTION WHEN ... END` in `plpgsql_v8`.

---

## 6. Lexical Analysis (`tokenize`)

`tokenize(src)` (`plv8.sql.common`, lines 1107–1327) is a single-pass lexical scanner that converts a raw PL/pgSQL source string into an array of token objects:

| Token `type` | Properties | Description & Examples |
| :--- | :--- | :--- |
| `'ident'` (`quoted: false`) | `value`, `upper`, `quoted: false`, `line` | Unquoted identifiers and keywords (`DECLARE`, `BEGIN`, `v_count`, `%TYPE`). `value` preserves original case; `upper` stores `value.toUpperCase()`. |
| `'ident'` (`quoted: true`) | `value`, `upper`, `quoted: true`, `line` | Double-quoted identifiers (`"My Column"`). `value` has inner `""` unescaped to `"`. |
| `'directive'` | `value`, `line` | Compiler directives (`#variable_conflict error \| use_variable \| use_column`), skipped by the token cursor (`peek` / `next`). |
| `'string'` | `value`, `strVal`, `line` | Single-quoted strings (`'hello'`), escape strings (`E'line1\nline2'`), and dollar-quoted strings (`$$body$$`, `$tag$...$tag$`). `value` is the raw literal; `strVal` is the decoded string value. |
| `'number'` | `value`, `isFloat`, `line` | Integer, decimal, and scientific-notation literals (`42`, `3.14`, `1e-5`). Note: `42..50` (FOR loop range) is tokenized as `'number' (42)`, `'op' (..)`, `'number' (50)` by looking ahead for `..`. |
| `'param'` | `value`, `index`, `line` | Positional parameter references (`$1`, `$2`, ...). |
| `'op'` | `value`, `line` | Multi-character (`:=`, `<<`, `>>`, `..`, `::`, `<=`, `>=`, `<>`, `!=`, `||`) and single-character (`+`, `-`, `*`, `/`, `%`, `^`, `=`, `<`, `>`) operators. |
| `'punct'` | `value`, `line` | Delimiters (`(`, `)`, `[`, `]`, `,`, `;`, `.`, `:`). |

Comments (`-- ...` single-line and nested `/* ... */` block comments) are skipped while maintaining accurate 1-based `line` numbers on every emitted token.

---

## 7. Catalog Introspection & Lexical Scope Architecture

### 7.1 Catalog Metadata Resolution

At the beginning of `compilePlpgsql(src, meta)` (`plv8.sql.common`, lines 1338–1461):
- If `meta.fn_oid` is provided, the compiler queries `pg_catalog.pg_proc` joined with `pg_catalog.pg_type` to retrieve:
  - `proname`, `proretset`, `prokind` (`'f'` function vs `'p'` procedure), `prorettype`, `rettypname`, `rettypcategory`, `rettyprelid`.
  - `proargtypes`, `proallargtypes`, `proargmodes` (`'i'`, `'o'`, `'b'`, `'v'`, `'t'`), `proargnames`.
- Helper functions query `pg_catalog.pg_attribute`, `pg_catalog.pg_class`, and `pg_catalog.pg_type` on demand during compilation:
  - `resolveRowFields(typeName)` (lines 1409–1445): Resolves `schema.table%ROWTYPE` or composite type names to their column names and SQL types (`{ name, type }`).
  - `resolvePercentType(typeSpec)` (lines 1447–1461): Resolves `var%TYPE` (from in-scope variables) or `table.col%TYPE` / `schema.table.col%TYPE` via `format_type(a.atttypid, a.atttypmod)`.

### 7.2 Scope Stack, Labels, and Variable Naming

PL/pgSQL allows nested blocks (`<<outer_lbl>> DECLARE ... BEGIN <<inner_lbl>> DECLARE ... END; END;`) where inner variables can shadow outer variables and outer variables remain accessible via `outer_lbl.var_name`.

The compiler maintains `scopeStack` (an array of scope frames `{ label, vars }`, lines 1463–1536):
- Each variable declared in a scope receives a unique collision-free JavaScript identifier via `freshVar(prefix)` (e.g., `__v_x_1`, `__v_x_2`).
- `lookupVar(name)` searches `scopeStack` from innermost to outermost. `lookupQualified(labelOrRec, field)` searches for a scope frame whose `label === labelOrRec` (or resolves `labelOrRec` as a composite/record variable in scope and `.field` as a field access).
- Root scope pre-registers:
  - `FOUND` (`__found`, boolean initialized to `false`)
  - `SQLSTATE` (`__sqlstate`, string initialized to `'00000'`)
  - `SQLERRM` (`__sqlerrm`, string initialized to `'successful completion'`)
  - Function parameters (`$1`, `$2`, ... and their named aliases), `OUT` / `INOUT` / `RETURNS TABLE` column variables, or trigger special variables (`NEW`, `OLD`, `TG_*`).

### 7.3 Composite, Rowtype, Record, and `%TYPE` Variables

Each entry in `scope.vars` (`declareVar`, lines 1473–1492) records:
```js
{
  name,         // lowercase PL/pgSQL identifier
  jsVar,        // allocated JS variable name (e.g. __v_rec_3)
  sqlType,      // normalized SQL type string (e.g. 'integer', 'record', 'text[]')
  isConstant,   // boolean (CONSTANT)
  notNull,      // boolean (NOT NULL)
  isRow,        // boolean (known composite type or %ROWTYPE)
  isRecord,     // boolean (untyped RECORD)
  isRefcursor,  // boolean (refcursor or bound CURSOR)
  cursorQuery,  // token slice for bound CURSOR query
  cursorArgs,   // formal parameter descriptors for bound CURSOR
  rowFields     // array of { name, type } for known rowtypes
}
```
- **Known composite / `%ROWTYPE` variables** (`isRow: true`) are initialized to a JavaScript object with all known attribute keys set to `null`: `{ id: null, name: null, ... }`.
- **`RECORD` variables** (`isRecord: true`) are initialized to `null` and dynamically populated as JS objects when assigned from `SELECT ... INTO`, `FOR v_rec IN SELECT ...`, `FETCH`, or another record.
- **`var%TYPE`** looks up `var` in `scopeStack` and resolves its `sqlType`.

---

## 8. Hybrid Expression Compilation & Runtime Semantics

One of the key architectural strengths of `plpgsql_v8` is its **hybrid expression compiler** (`compileExpr(tokSlice)` in `plv8.sql.common`, lines 1971–2499).

### 8.1 Fast-Path Pure-JavaScript Recursive-Descent Compiler

`compileExpr` first scans the token slice for constructs that require PostgreSQL's SQL engine:
- Top-level or nested SQL keywords: `SELECT`, `EXISTS`, `ANY`, `SOME`, `ALL`, `SIMILAR`, `OVER`, `FILTER`, `WITHIN`, `VARIADIC`, `COLLATE`, `AT`, `INTERVAL`, `EXTRACT`, `OVERLAY`, `POSITION`, `PLACING`, `SYMMETRIC`, `ASYMMETRIC`.

If none are present, `compileExpr` parses the expression with a recursive-descent parser matching PostgreSQL operator precedence (from lowest to highest), where each parse step returns a typed node `{ code, type }`:

1. `parseOr`: `a OR b` -> `__rt.or(a, b)`
2. `parseAnd`: `a AND b` -> `__rt.and(a, b)`
3. `parseNot`: `NOT a` -> `__rt.not(a)`
4. `parseComp`:
   - `=`, `<>` / `!=`, `<`, `<=`, `>`, `>=` -> `__rt.eq`, `__rt.ne`, `__rt.lt`, `__rt.le`, `__rt.gt`, `__rt.ge`
   - `IS [NOT] NULL` / `ISNULL` / `NOTNULL` -> `(x === null || x === undefined)`
   - `IS [NOT] TRUE` / `FALSE` / `UNKNOWN` -> strict 3VL truth-value checks
   - `IS [NOT] DISTINCT FROM` -> `[!]__rt.isDistinctFrom(a, b)`
   - `[NOT] BETWEEN lo AND hi` -> `__rt.between(x, lo, hi)`
   - `[NOT] IN (v1, v2, ...)` -> `__rt.inList(x, [v1, v2, ...])`
   - `[NOT] LIKE` / `ILIKE` (with optional `ESCAPE`) -> `__rt.like(x, pat, caseInsensitive, esc)`
5. `parseAdd`: `+`, `-`, `||` -> `__rt.add(a, b)`, `__rt.sub(a, b)`, `__rt.concat(a, b)`
6. `parseMul`: `*`, `/`, `%` -> `__rt.mul(a, b)`, `__rt.idiv(a, b)` or `__rt.div(a, b)`, `__rt.mod(a, b)`
7. `parseExp`: `^` -> `__rt.pow(a, b)`
8. `parseUnary`: unary `+`, `-` -> `__rt.uplus(a)`, `__rt.uminus(a)`
9. `parsePostfix`:
   - Array element indexing `arr[idx]` -> `__rt.getElem(arr, idx)`
   - Array slicing `arr[lo:hi]` -> `__rt.getSlice(arr, lo, hi)`
   - Type cast `expr::type` -> `__rt.coerce(expr, "type")` (when `type` is in `PURE_CAST_TYPES`; otherwise throws `new Error('fallback')`)
   - Field access `rec.field` -> `(rec != null ? rec["field"] : null)`
10. `parsePrimary`:
    - Literals (`NULL`, `TRUE`, `FALSE`, numbers, strings, `BigInt("...")` for integers outside safe `Number` range)
    - Parenthesized expressions `(expr)`
    - `CAST(expr AS type)` -> `__rt.coerce(expr, "type")` (for `PURE_CAST_TYPES`)
    - `ARRAY[...]` -> `[...]`
    - `CASE ... WHEN ... THEN ... ELSE ... END` (both searched and simple `CASE` expressions)
    - `COALESCE(...)`, `NULLIF(a, b)`, `GREATEST(...)`, `LEAST(...)`
    - 21 pure-JS built-in functions in `PURE_BUILTINS` / `__rt.callBuiltin` (`LOWER`, `UPPER`, `LENGTH`, `CHAR_LENGTH`, `CHARACTER_LENGTH`, `BTRIM`, `TRIM`, `LTRIM`, `RTRIM`, `ABS`, `CEIL`, `CEILING`, `FLOOR`, `SIGN`, `SQRT`, `ROUND`, `TRUNC`, `MOD`, `POWER`, `POW`, `ARRAY_LENGTH`, `CARDINALITY`).

### 8.2 Automatic Parameterized SQL Fallback

If `parseOr()` throws `new Error('fallback')` (for example, when encountering any other SQL function such as `substr(...)`, `replace(...)`, `to_char(...)`, `now()`, `regexp_replace(...)`, a temporal/custom type cast like `'2025-01-01'::date + 5`, or a subquery) or fails to consume all tokens:
- `compileExpr` catches the fallback signal and delegates to `rewriteSqlTokensWithParams(tokSlice)`.
- All PL/pgSQL variables, `label.var`, and `rec.field` references in the expression are replaced with `$1`, `$2`, ... (with `($N::type)` casts so PostgreSQL knows the exact parameter type even inside untyped contexts).
- The compiler emits:
  ```js
  __rt.evalSql("SELECT (" + sql + ") AS __val", [param1, param2, ...])
  ```
- At runtime, `__rt.evalSql` executes `plv8.execute(sql, params)` and returns the first column of the first row.

### 8.3 SQL Three-Valued Logic (3VL) and NULL Semantics

JavaScript's `&&`, `||`, `!`, `===`, and `<` operators do not follow SQL's three-valued logic (`TRUE`, `FALSE`, `NULL`). `__plpgsql_v8_rt` implements exact SQL semantics:
- `__rt.and(a, b)`:
  - If either operand is `false` -> `false` (even if the other is `null`!).
  - Else if either operand is `null` -> `null`.
  - Else -> `true`.
- `__rt.or(a, b)`:
  - If either operand is `true` -> `true` (even if the other is `null`!).
  - Else if either operand is `null` -> `null`.
  - Else -> `false`.
- `__rt.not(a)`:
  - If `a` is `null` -> `null`, else `!__rt.toBool(a)`.
- Comparisons (`eq`, `ne`, `lt`, `le`, `gt`, `ge`):
  - If either operand is `null` or `undefined`, returns `null`.
- String concatenation (`__rt.concat(a, b)` for `||`):
  - If either operand is `null`, returns `null` (unless both operands are `Array` instances, in which case `||` performs PostgreSQL array concatenation).

### 8.4 64-Bit `BigInt` Arithmetic & Static Integer vs Float Division

PostgreSQL `bigint` (`int8`) values exceed `Number.MAX_SAFE_INTEGER` ($2^{53} - 1$) and are represented in V8 as `BigInt` when outside safe integer bounds (or returned by `plv8` as `BigInt` / `Number`).
- `__rt.add`, `__rt.sub`, `__rt.mul`, `__rt.idiv`, and `__rt.mod` automatically promote operands to `BigInt` whenever either operand is a `BigInt` or when a safe-integer operation would overflow `Number.isSafeInteger(res)`.
- `__rt.normBigInt(v)` converts a `BigInt` back to a JS `Number` if it fits within `[-9007199254740991, 9007199254740991]` so standard JSON/SPI marshaling works seamlessly, while keeping larger 64-bit integers as `BigInt`.
- **Integer vs Float Division (`/` operator)**:
  - In SQL/PL/pgSQL, `10 / 3` is integer division (`3`) when both operands have integer types (`smallint`, `integer`, `bigint`), whereas `10.0 / 3` is floating-point division (`3.3333...`).
  - Because JS represents both `10` and `10.0` as `Number(10)` at runtime, `compileExpr` tracks static expression types (`{ code, type }`) and checks `isIntType(l.type) && isIntType(r.type)` (`plv8.sql.common`, lines 1555–1559, 2165).
  - When both the left and right operands of `/` are statically integer-typed, the compiler emits `__rt.idiv(l, r)` (`Math.trunc(na / nb)` or `BigInt` division); otherwise it emits `__rt.div(l, r)`.
  - Both `__rt.idiv` and `__rt.div` raise SQLSTATE `22012` (`division by zero`) if the divisor is `0`.

### 8.5 1-Based Array Indexing, Slicing, and Copy-on-Write Mutation

PostgreSQL arrays are 1-based (`arr[1]` is the first element) and support inclusive slicing (`arr[2:4]`).
- `__rt.getElem(arr, idx)`: Returns `null` if `arr == null` or `idx == null`. If `arr.__zeroIndexed` is true (used for `TG_ARGV`), returns `arr[i]`; otherwise returns `arr[i - 1]` (or `null` if out of bounds).
- `__rt.getSlice(arr, lo, hi)`: Returns `arr.slice(Math.max(0, lo - 1), Math.min(arr.length, hi))`.
- `__rt.setElem(arr, idx, val)`: Clones the array (or creates `[]` if `null`) and sets `copy[idx - 1] = val` (supports multi-dimensional index chains `[i][j]`).
- `__rt.setSlice(arr, lo, hi, val)`: Replaces the 1-based inclusive slice `[lo..hi]` with the elements of `val`.

---

## 9. Context-Aware SQL Token Rewriting

### 9.1 Parameterized Binding Model

When a PL/pgSQL statement executes static SQL (e.g., `INSERT INTO users (id, name) VALUES (v_id, v_name)` or `SELECT score INTO v_score FROM users WHERE id = v_id`), `rewriteSqlTokensWithParams(tokSlice, extraScopeMap)` (`plv8.sql.common`, lines 1738–1969) scans the token slice and replaces references to in-scope PL/pgSQL variables with `$1`, `$2`, ... placeholders while building a matching array of JS argument expressions.

To prevent PostgreSQL `indeterminate_datatype` errors when parameters appear in untyped positions (such as `SELECT $1`), scalar variables with known non-pseudo types are emitted as `($1::type)` (except when immediately followed by `::` in the user's SQL).

### 9.2 Disambiguating PL/pgSQL Variables from SQL Column Identifiers

A classic challenge in PL/pgSQL is when a PL/pgSQL variable or parameter has the **same name** as a table column:
```sql
CREATE FUNCTION update_user(id int, name text) RETURNS void AS $$
BEGIN
  INSERT INTO users (id, name) VALUES (id, name)
    ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;
  UPDATE users SET name = update_user.name WHERE users.id = update_user.id;
END;
$$ LANGUAGE plpgsql_v8;
```
If the rewriter blindly replaced every occurrence of `id` and `name` with `$1` and `$2`, it would produce invalid SQL like `INSERT INTO users ($1, $2) ...` or `UPDATE users SET $2 = ...`.

`rewriteSqlTokensWithParams` tracks SQL syntactic context across statement boundaries (`;`) and parenthesized groups (`parenDepth`):
1. **Member / Cast Suffixes**: An identifier immediately preceded by `.` (`users.id`, `EXCLUDED.name`) or `::` (`val::text`) is never a standalone PL/pgSQL variable.
2. **Function Calls**: An identifier immediately followed by `(` (`count(x)`, `coalesce(a, b)`) is a SQL function call, not a variable.
3. **`FROM` / `JOIN` / `UPDATE` / `INTO` Table Names**: An identifier immediately following `FROM`, `JOIN`, `UPDATE`, `INTO`, or `TABLE` is a relation name, not a variable.
4. **`INSERT INTO tbl (col1, col2, ...)` Target Columns**: After `INSERT INTO <table_ref>`, if the next token is `(`, that parenthesized list is marked `inInsertCols = true` until its matching `)`. Identifiers inside `inInsertCols` are column names and are never substituted.
5. **`ON CONFLICT (col1, col2, ...)` Conflict Target**: After `ON CONFLICT`, if the next token is `(`, that parenthesized list is marked `inConflictCols = true` until its matching `)`. Identifiers at the top of that list are index column names and are not substituted.
6. **`WITH cte (col1, col2, ...) AS (...)` Column Aliases**: Inside a `WITH` clause before `AS`, the optional `(col1, col2)` list after the CTE name is marked `inCteCols = true` and not substituted.
7. **`UPDATE tbl SET col = expr` and `SET (col1, col2) = ...` Target LHS**:
   - In an `UPDATE` statement, `inUpdateSet` is active between `SET` and `WHERE` / `FROM` / `RETURNING` / `;`.
   - At the start of `SET` or immediately after a top-level `,` inside `SET`:
     - Any identifier immediately followed by `=` (or `.subfield =` / `[idx] =`) is the target column on the left-hand side of `=` and is **not** substituted.
     - On the right-hand side of `=`, PL/pgSQL variables **are** substituted normally.
     - Multi-column `SET (col1, col2) = (expr1, expr2)` marks the left-hand parenthesized group as `inUpdateSetCols = true` so `col1, col2` are not substituted.
8. **Qualified `label.var` and `rec.field` Resolution**:
   - If `ident1.ident2` matches a block/function label (`scope.label === ident1`) and `ident2` is a variable in that scope, the entire `ident1.ident2` is replaced by `$N` (or `ident1.ident2.ident3` for `label.rec.field`).
   - If `ident1` is a `record` or `rowtype` variable in scope, `ident1.ident2` is replaced by `$N` bound to `(jsVar != null ? jsVar["ident2"] : null)`.

---

## 10. Subtransaction & Exception Architecture

### 10.1 Mapping `BEGIN ... EXCEPTION` to `plv8.subtransaction()`

In PostgreSQL, a `BEGIN ... EXCEPTION WHEN ... END` block starts an internal subtransaction before executing the `BEGIN` body. If an error occurs inside the `BEGIN` body:
1. Database changes made inside the `BEGIN` body are rolled back to the subtransaction savepoint.
2. PL/pgSQL local variables retain the values they had at the moment the error was raised!
3. If a `WHEN` clause matches the error's `SQLSTATE`, the handler statements execute in the restored outer transaction state, with `SQLSTATE` and `SQLERRM` bound to the caught error.

`plpgsql_v8` compiles `BEGIN ... EXCEPTION ... END` (`parseBlock` in `plv8.sql.common`, lines 2909–3036) directly to `plv8.subtransaction()`:
```js
let __caught_1 = null;
__pg.subtransaction(function() {
  try {
    // Compiled BEGIN statements (with subtranDepth incremented)
  } catch (__e_1) {
    __caught_1 = __e_1;
    throw __e_1;
  }
});
if (__ctrl) {
  // Unwind non-local RETURN / EXIT / CONTINUE after subtransaction committed!
}
if (__caught_1 !== null) {
  // Exception matching and WHEN handler execution
}
```
Because PL/pgSQL variables are JavaScript `let` variables declared in the enclosing JS block scope outside `__pg.subtransaction(function() { ... })`, mutations to local JS variables inside the callback naturally survive a subtransaction rollback while SPI database changes inside `__pg.subtransaction` are rolled back by PostgreSQL's `RollbackAndReleaseCurrentSubTransaction()`!

### 10.2 Non-Local Control Unwinding (`__ctrl`) Without Rolling Back

A subtle interaction arises when a `RETURN`, `EXIT`, or `CONTINUE` statement is executed **inside** the `BEGIN` section of a `BEGIN ... EXCEPTION ... END` block (or inside a loop that is inside a `BEGIN ... EXCEPTION` block, or jumping out of a loop that contains a `BEGIN ... EXCEPTION` block):
- If `RETURN expr` were compiled as a normal JS `return` inside `__pg.subtransaction(function() { ... })`, it would only return from the inner anonymous subtransaction callback, not from the outer PL/pgSQL function!
- Conversely, if `RETURN` or `EXIT` threw a JS exception to unwind out of `__pg.subtransaction`, `plv8_Subtransaction` would treat it as an error and **abort/rollback** the subtransaction, discarding valid `INSERT`/`UPDATE` statements that happened before the `RETURN` or `EXIT`!

To solve this cleanly:
- The compiler tracks `subtranDepth` (the current nesting depth inside `__pg.subtransaction` callbacks) and stamps every `loopStack` entry with its `subtranDepth` at loop entry.
- **For `RETURN` inside `subtranDepth > 0`** (`parseReturnStmt`, line 3654):
  - Instead of `return val`, the compiler emits:
    ```js
    { __ctrl = { type: "return", value: val }; return; }
    ```
  - This returns *normally* from the `__pg.subtransaction` callback, causing `plv8_Subtransaction` to **commit** (`ReleaseCurrentSubTransaction()`) the subtransaction's database changes!
  - Immediately after `__pg.subtransaction(...)` finishes, `emitCtrlUnwindCheck()` (lines 2873–2889) checks `if (__ctrl)`: if `subtranDepth > 0`, it returns from the outer subtransaction callback (`if (__ctrl.type === "return") return;`); at `subtranDepth === 0`, it executes `if (__ctrl.type === "return") return __ctrl.value;`.
- **For `EXIT` / `CONTINUE` across a subtransaction boundary** (`parseExitContinStmt`, line 3577):
  - When jumping out of a `__pg.subtransaction` callback (`target.subtranDepth < subtranDepth`), the compiler emits:
    ```js
    { __ctrl = { type: "exit", jsLabel: "__lbl_1" }; return; }
    ```
  - Each subtransaction boundary commits cleanly and `emitCtrlUnwindCheck()` propagates `__ctrl` until it reaches `target.subtranDepth`, where it clears `__ctrl = null` and executes `break __lbl_1;` or `continue __lbl_1;`!

### 10.3 Condition Matching (`COND_MAP`) and Lexical Stacked Diagnostics

When `__caught_1 !== null`:
1. `__rt.extractSqlState(__err_1)` extracts the 5-character `SQLSTATE` from `err.sqlerrcode` or `err.code` (falling back to `'XX000'` for generic JS errors).
2. `COND_MAP` (`plv8.sql.common`, lines 99–317) maps all standard PostgreSQL condition names (e.g. `unique_violation` -> `'23505'`, `division_by_zero` -> `'22012'`, `no_data_found` -> `'P0002'`, `too_many_rows` -> `'P0003'`, `raise_exception` -> `'P0001'`, `assert_failure` -> `'P0004'`) as well as 2-character class prefixes (e.g. `integrity_constraint_violation` -> `'23'`, `data_exception` -> `'22'`, `plpgsql_error` -> `'P0'`).
3. `__rt.matchException(err, condSpecs)` returns `true` if any condition in `WHEN cond1 OR cond2 THEN` is `'OTHERS'`, matches the 5-character `SQLSTATE` exactly, or is a 2-character class prefix of the error's `SQLSTATE` (with `query_canceled` (`57014`) and `assert_failure` (`P0004`) excluded from `OTHERS` unless explicitly named, matching PostgreSQL semantics).
4. Inside the exception block (`lines 2998–3035`):
   - Previous values of `__cur_err`, `__sqlstate`, `__sqlerrm`, `__err_detail`, `__err_hint`, `__err_context`, `__err_schema`, `__err_table`, `__err_column`, `__err_datatype`, and `__err_constraint` are saved in `__prev_*` variables and restored when the handler finishes.
   - `GET STACKED DIAGNOSTICS` (`lines 3924–3935`) reads directly from `__sqlstate`, `__sqlerrm`, `__err_detail`, `__err_hint`, `__err_context`, `__err_schema`, `__err_table`, `__err_column`, `__err_datatype`, and `__err_constraint`.
   - Bare `RAISE;` (`lines 3662–3665`) re-throws `__cur_err` directly (or raises `55000` if `__cur_err` is null), preserving all original diagnostic fields.

---

## 11. Cursors, Set-Returning Functions, Procedures, and Triggers

### 11.1 Bound and Unbound Cursors

PL/pgSQL supports two kinds of cursor variables:
1. **Unbound `refcursor`**: Declared as `cur refcursor;` and opened via:
   - `OPEN cur FOR SELECT ...` (static query)
   - `OPEN cur FOR EXECUTE dyn_sql [USING ...]` (dynamic query)
2. **Bound `CURSOR`**: Declared as `cur CURSOR [(p1 type1, p2 type2)] FOR SELECT ...;` where the query in `DECLARE` can reference both the cursor's formal parameters `(p1, p2)` and outer PL/pgSQL variables.

In `plpgsql_v8` (`lines 944–1027`, `3947–4122`):
- `__rt.openCursor(sql, params)` calls `plv8.prepare(sql)` and `plan.cursor(params)`, returning `{ plan, portal, sql }`.
- For a bound cursor (`v.cursorQuery`), `parseOpenStmt` (lines 3947–3993) and `parseForStmt` (lines 3399–3440) bind positional or named cursor arguments (`p := val` or `p => val`) into `extraMap` and rewrite `v.cursorQuery` via `rewriteSqlTokensWithParams(v.cursorQuery, extraMap)`.
- `__rt.fetchCursor(curObj, dir, count)` and `__rt.moveCursor(curObj, dir, count)` implement `NEXT`, `PRIOR`, `FIRST`, `LAST`, `ABSOLUTE n`, `RELATIVE n`, `FORWARD [n | ALL]`, `BACKWARD [n | ALL]`, and bare count `n`, updating `FOUND` (`__found`) and `ROW_COUNT` (`__row_count`).
- `__rt.closeCursor(curObj)` closes both `curObj.portal` and `curObj.plan`. Cursor `FOR` loops automatically close their cursor in a `finally` block.

### 11.2 Set-Returning Functions (`RETURN NEXT`, `RETURN QUERY`, `RETURNS TABLE`)

When `retset` is `true` (`parseReturnStmt`, lines 3587–3657):
- **`RETURN NEXT [expr]`**:
  - If the function uses `RETURNS TABLE(c1 t1, c2 t2)` or has `OUT` parameters and no expression is passed, `RETURN NEXT;` packages the current values of the output variables and passes them to `__pg.return_next(...)`.
  - If an expression is given (`RETURN NEXT expr;`), it coerces and passes that expression to `__pg.return_next(...)`.
- **`RETURN QUERY <static_sql>` and `RETURN QUERY EXECUTE <dyn_sql> [USING ...]`**:
  - Compiles to `__rt.returnQuery(sql, params, isScalarSrf, outColNames)` and updates `__last_row_count` (`GET DIAGNOSTICS ... = ROW_COUNT`) and `__found` (`FOUND`).
  - When `plv8.return_query(sql, params)` is available in C++, `__rt.returnQuery` executes the query via SPI and streams all result rows directly from `SPI_tuptable` into the function's active SRF `Tuplestorestate` (`tupstore`) in C++ with positional column matching and C-level type coercion—bypassing V8 JavaScript row materialization entirely.
  - Falls back to `__pg.execute(sql, params)` + `__rt.returnNext(...)` if `plv8.return_query` is not present.

### 11.3 Stored Procedures (`OUT`/`INOUT` and Transaction Control)

- **`OUT` and `INOUT` Parameters**:
  - `buildDefaultReturn()` (lines 1722–1736) constructs the return value needed by `plv8` when a function or procedure finishes:
    - Single `OUT` / `INOUT` parameter: returns the coerced variable value.
    - Multiple `OUT` / `INOUT` parameters: returns `{ out1: __rt.coerce(...), out2: __rt.coerce(...), ... }`.
- **`COMMIT` and `ROLLBACK`**:
  - Compiled to `__pg.execute("COMMIT")` and `__pg.execute("ROLLBACK")` (lines 3102–3111).

### 11.4 Trigger Functions (`NEW`, `OLD`, `TG_*`, 0-Indexed `TG_ARGV`)

When `isTrigger` is `true` (`rettype_oid === 2279`, lines 1581–1623):
- `compilePlpgsql` binds all standard PostgreSQL trigger variables in root scope:
  - `NEW` (`typeof NEW !== 'undefined' ? NEW : null`)
  - `OLD` (`typeof OLD !== 'undefined' ? OLD : null`)
  - `TG_NAME`, `TG_WHEN`, `TG_LEVEL`, `TG_OP`, `TG_RELID`, `TG_TABLE_NAME`, `TG_RELNAME`, `TG_TABLE_SCHEMA`, `TG_NARGS`, `TG_ARGV`.
- **0-Based `TG_ARGV` Indexing**:
  - In PostgreSQL PL/pgSQL, regular SQL arrays are 1-indexed, **except** `TG_ARGV`, which is 0-indexed (`TG_ARGV[0]` is the first trigger argument)!
  - At function startup (line 1598), `__tg_argv` is initialized with a non-enumerable property `__zeroIndexed: true`. In `__rt.getElem(arr, idx)` (line 740), `arr.__zeroIndexed ? arr[i] : arr[i - 1]` is returned, and in `rewriteSqlTokensWithParams` (lines 1932–1954), `TG_ARGV[idx]` inside embedded SQL is also bound using 0-based indexing.

---

## 12. Security & Isolation Model

`plpgsql_v8` is registered as a **`TRUSTED`** procedural language (`CREATE TRUSTED LANGUAGE plpgsql_v8`):
1. **Per-User V8 Isolates**: `plv8` maintains a separate V8 Isolate per PostgreSQL `user_id` (`GetUserId()`), ensuring complete memory and global-object isolation between database roles.
2. **Handler Execution Privileges**:
   - `REVOKE ALL ON FUNCTION plv8_plpgsql_handler() FROM PUBLIC;` and `REVOKE ALL ON FUNCTION plv8.compile_plpgsql(text, jsonb) FROM PUBLIC;` prevent untrusted users from calling the handler function directly via SQL.
   - When PostgreSQL invokes `plv8_plpgsql_handler` during function transpilation (`plv8_transpile_src`), C++ enters a `HandlerExecutionScope` (`plv8.h`, lines 334–370), which allows internal transpilation while keeping direct SQL invocation blocked.
3. **Standard SQL Permission Checks**: All SQL queries executed by a `plpgsql_v8` function run through PostgreSQL's SPI under the active user (or `SECURITY DEFINER` owner if the function is declared `SECURITY DEFINER`), enforcing all table, schema, and row-level security policies.

---

# Part III: Implementation Walk-Through

## 13. Source File Map

| File | Lines | Responsibility |
| :--- | :--- | :--- |
| `third_party/pgext/plv8/plv8.h` | 54–80, 320–391, 424 | `js_error` diagnostic fields (`m_code`, `m_detail`, `m_hint`, `m_context`, `m_schema_name`, `m_table_name`, `m_column_name`, `m_datatype_name`, `m_constraint_name`, `m_internalquery`, `m_internalpos`), `PLV8_MAX_LANG_HANDLER_DEPTH` (`32`), `plv8_handler_dep`, `HandlerExecutionScope`, `CurrentContextScope`, `plv8_pass_user_types_as_bytes`. |
| `third_party/pgext/plv8/plv8.cc` | 121–142, 898–994, 1207–1237, 1762–1838, 1983–2182, 3294–3568 | `plv8_proc_cache`, `PassUserTypesScope`, `plv8_call_handler`, `plv8_inline_handler` transpilation, `plv8_call_validator`, `plv8_transpile_src`, `js_error` SQLSTATE parsing and `ErrorData` round-tripping. |
| `third_party/pgext/plv8/plv8_func.cc` | 503–583, 858–1517 | `plv8_FunctionInvoker` diagnostic property population on JS `Error`, `SubTranBlock` wrapping for `Prepare`, `PlanCursor`, `PlanExecute`, `CursorFetch`, `CursorMove`, `CursorClose`, and `Subtransaction`. |
| `third_party/pgext/plv8/plv8.sql.common` | 94–4270 | Complete implementation of `plv8_plpgsql_handler()`, `COND_MAP`, `__plpgsql_v8_rt` runtime library, `tokenize()`, `compilePlpgsql()`, `plv8.compile_plpgsql()`, and `CREATE TRUSTED LANGUAGE plpgsql_v8`. |
| `third_party/pgext/plv8/generate_upgrade.sh` | 85–87 | Strips `CREATE TRUSTED LANGUAGE plpgsql_v8` from upgrade scripts and appends an idempotent `DO` block checking `pg_language`. |
| `third_party/pgext/plv8/BUILD` | 52–77, 205–260 | Preprocesses `plv8.sql.common` into versioned SQL files and registers `"plpgsql_v8"` in `REGRESS_TESTS`. |
| `third_party/pgext/plv8/sql/plpgsql_v8.sql` | 1–996 | Comprehensive regression test suite covering all `plpgsql_v8` features and edge cases. |
| `third_party/pgext/plv8/expected/plpgsql_v8.out` | 1–1183 | Expected regression test output. |

---

## 14. Walk-Through of C++ Engine Changes (`plv8.h`, `plv8.cc`, `plv8_func.cc`)

### 14.1 Inline `DO` Block Transpilation (`plv8.cc`, lines 1207–1237)
In `plv8_inline_handler(PG_FUNCTION_ARGS)`:
```cpp
InlineCodeBlock *codeblock = (InlineCodeBlock *) DatumGetPointer(PG_GETARG_DATUM(0));
...
char *source_text = plv8_transpile_src(codeblock->source_text,
                                       codeblock->langOid,
                                       NULL, NULL, NULL);
```
Previously, `plv8_inline_handler` passed `codeblock->source_text` directly to `CompileDoBlock`, which only worked if the `DO` block was written in raw JavaScript (`LANGUAGE plv8`). By calling `plv8_transpile_src` with `codeblock->langOid` and `proc = NULL`, `DO $$ ... $$ LANGUAGE plpgsql_v8` (and any other chained language) transpiles its source text through `plv8_plpgsql_handler` before compiling and running the V8 script.

### 14.2 `plv8_transpile_src` (`plv8.cc`, lines 1983–2182)
1. **Handler Chain Discovery (lines 1995–2066)**:
   Looks up `plv8_lang_oid` (`"plv8"`) and walks `pg_language` (`lanplcallfoid`) -> `pg_proc` (`prolang`) while `cur_lang_oid != plv8_lang_oid`. Saves the `depth == 0` handler OID as `lang_handler_oid` and populates `proc->cache->handlers[]` with `{ fn_oid, fn_xmin, fn_tid }` for cache invalidation.
2. **Metadata Construction (lines 2093–2136)**:
   When `proc != NULL && proc->cache != NULL`, constructs the V8 `meta` object (`fn_oid`, `proname`, `rettype_oid`, `rettype_category`, `rettype_len`, `argtype_oids`, `argtype_categories`, `argtype_lens`, `retset`) and sets `call_argc = 2`. When `proc == NULL` (inline `DO` block), `call_argc = 1`.
3. **Handler Execution (lines 2068–2177)**:
   Enters `HandlerExecutionScope`, resolves `find_js_function(lang_handler_oid)`, and invokes `DoCall(context, fn, recv, call_argc, args, false)`. After the call, checks `meta->Get(context, String::NewFromUtf8Literal(isolate, "pass_user_types_as_bytes"))` so the handler can opt in or out of raw byte marshaling.

### 14.3 Error Diagnostic Round-Tripping (`plv8.cc`, lines 3294–3568 & `plv8_func.cc`, lines 503–583)
1. **SPI -> JS (`plv8_FunctionInvoker` in `plv8_func.cc`, lines 518–577)**:
   When a PostgreSQL function call (`plv8.execute`, `plv8.prepare`, `plan.execute`, etc.) throws `pg_error`:
   ```cpp
   MemoryContextSwitchTo(ccxt);
   ErrorData *edata = CopyErrorData();
   FlushErrorState();
   ```
   Creates `v8::Exception::Error(ToString(edata->message))` and sets `sqlerrcode` (5-char string via `unpack_sql_state(edata->sqlerrcode)`), `code` (integer `edata->sqlerrcode`), `detail`, `hint`, `context`, `schema_name`, `table_name`, `column_name`, `datatype_name`, `constraint_name`, `internalquery`, and `internalpos`.
2. **JS -> C++ (`js_error::init` in `plv8.cc`, lines 3334–3452)**:
   Extracts `.message`, `.code` / `.sqlerrcode` (converting a 5-char string to integer `MAKE_SQLSTATE` via `plv8_parse_sqlerrcode`), and all optional diagnostic fields (`detail`, `hint`, `context`, `schema_name`, `table_name`, `column_name`, `datatype_name`, `constraint_name`, `internalquery`, `internalpos`) from the V8 `Error` object into `palloc`-allocated strings in `TopTransactionContext`.
3. **C++ -> JS across `plv8.subtransaction()` (`js_error::error_object` in `plv8.cc`, lines 3463–3512)**:
   When `plv8_Subtransaction` catches a `js_error` or `pg_error`, it aborts the subtransaction and calls `ThrowException(e.error_object())`, which restores `sqlerrcode`, `code`, `detail`, `hint`, `context`, `schema_name`, `table_name`, `column_name`, `datatype_name`, and `constraint_name` onto the thrown V8 `Error` so the outer `catch` block in `plpgsql_v8` receives every diagnostic field intact.
4. **C++ -> PostgreSQL (`js_error::rethrow` in `plv8.cc`, lines 3541–3568)**:
   When an unhandled exception escapes the top-level `plv8` function back to PostgreSQL, `js_error::rethrow()` invokes `ereport(ERROR, ...)` with `errcode(m_code)`, `errmsg("%s", m_msg)`, `errdetail`, `errhint`, `errcontext`, and `err_generic_string(PG_DIAG_*, ...)`.

---

## 15. Walk-Through of the `plpgsql_v8` Compiler & Runtime (`plv8.sql.common`)

All of `plpgsql_v8`'s compiler and runtime logic resides in `third_party/pgext/plv8/plv8.sql.common` (lines 94–4270):

1. **Lines 99–317 (`COND_MAP`)**:
   Dictionary mapping ~160 PostgreSQL condition names and 2-character SQLSTATE class names to SQLSTATE strings.
2. **Lines 319–1105 (`ensureRuntime` -> `globalThis.__plpgsql_v8_rt`)**:
   Installs the singleton runtime helper object on `globalThis.__plpgsql_v8_rt` once per V8 isolate:
   - **Lines 324–427**: Error construction and `RAISE` formatting (`resolveCode`, `makeError`, `formatRaise`, `doRaise`, `extractSqlState`, `matchException`). `formatRaise` implements PL/pgSQL's `%` placeholder substitution and `%%` escaping.
   - **Lines 429–588**: Type conversions, 3VL boolean logic (`toText`, `toBool`, `truthy`, `and`, `or`, `not`), 64-bit `BigInt` arithmetic (`normBigInt`, `tryBigInt`, `toNum`, `add`, `sub`, `mul`, `div`, `idiv`, `mod`, `pow`, `uplus`, `uminus`), and `concat`.
   - **Lines 590–724**: Comparisons (`cmpVal`, `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `isDistinctFrom`, `between`, `inList`), `LIKE` / `ILIKE` pattern compilation (`like` with custom `ESCAPE` character support), and `coalesce`, `nullif`, `greatest`, `least`.
   - **Lines 726–821**: 1-based array access (`getElem` with `__zeroIndexed` support for `TG_ARGV`, `getSlice`) and copy-on-write mutation (`setElem`, `setSlice`, `setField`, `flattenForeach`).
   - **Lines 823–912**: Pure in-JS runtime type coercion (`coerce(val, sqlType, notNull, varName)`) handling `NOT NULL` checks (`22004`), `boolean`, `smallint`/`integer` (with half-away-from-zero rounding and range checks raising `22003`), `bigint`, `real`/`double precision`/`numeric`, `text`/`varchar`, arrays, and `json`/`jsonb`.
   - **Lines 914–1027**: SPI helpers (`evalSql`, `returnNext`) and cursor lifecycle helpers (`openCursor`, `fetchCursor`, `moveCursor`, `closeCursor`).
   - **Lines 1028–1101**: Fast-path SQL built-in functions (`callBuiltin` supporting 21 string, math, and array functions).
3. **Lines 1107–1327 (`tokenize`)**:
   Lexical scanner producing the token stream.
4. **Lines 1329–1736 (`compilePlpgsql` Setup & Metadata)**:
   - Catalog lookup for `meta.fn_oid` and composite/column type resolution (lines 1338–1461).
   - Scope management helpers (`pushScope`, `popScope`, `declareVar`, `lookupVar`, `lookupQualified`, lines 1463–1536).
   - Pre-population of root scope with `FOUND`, `SQLSTATE`, `SQLERRM`, trigger variables, and function parameters (lines 1561–1720).
5. **Lines 1738–1969 (`rewriteSqlTokensWithParams`)**:
   Context-aware SQL token rewriter for static SQL statements and fallback expressions.
6. **Lines 1971–2499 (`compileExpr`)**:
   Recursive-descent pure-JS expression compiler with static integer division tracking (`isIntType`) and automatic parameterized SQL fallback (`__rt.evalSql`).
7. **Lines 2501–2636 (`findTopLevelKeyword`, `splitTopLevelComma`, `parseTargetLValue`, `emitRowToTargets`)**:
   L-value target parser and row-to-variable assignment generator for `INTO [STRICT]`, `FETCH`, and assignments (`:=` / `=`). Supports scalar variables, `rowtype`/`record` variables, `rec.field`, `arr[idx]`, and `arr[lo:hi]`, plus `NOT NULL` enforcement.
8. **Lines 2638–2871 (`parseDeclareSection`)**:
   Parses `DECLARE` sections: `ALIAS FOR`, bound `CURSOR [(params)] FOR query`, `REFCURSOR`, `CONSTANT`, `NOT NULL`, `COLLATE`, `DEFAULT` / `:=` / `=`, `%TYPE`, `%ROWTYPE`, `RECORD`, and composite types.
9. **Lines 2873–4215 (Statement Parsers & Code Generators)**:
   - `emitCtrlUnwindCheck` (lines 2873–2889), `parseStmtList` (lines 2891–2907), and `parseBlock` (lines 2909–3036): `BEGIN ... [EXCEPTION WHEN ...] END`, subtransaction wrapping, `__ctrl` unwinding, and stacked diagnostics.
   - `parseOneStmt` (lines 3038–3164): Statement dispatcher (`NULL;`, `<<label>>`, nested `DECLARE`/`BEGIN`, `IF`, `CASE`, `LOOP`, `WHILE`, `FOR`, `FOREACH`, `EXIT`, `CONTINUE`, `RETURN`, `RAISE`, `ASSERT`, `PERFORM`, `EXECUTE`, `GET DIAGNOSTICS`, `OPEN`, `FETCH`, `MOVE`, `CLOSE`, `COMMIT`, `ROLLBACK`, assignments, and static SQL).
   - `parseIfStmt` (lines 3166–3186) & `parseCaseStmt` (lines 3188–3229).
   - `parseLoopStmt` (lines 3231–3247), `parseWhileStmt` (lines 3249–3264), `parseForStmt` (lines 3266–3499: integer `FOR`, bound/unbound cursor `FOR`, dynamic `FOR ... IN EXECUTE`, static query `FOR ... IN SELECT`), and `parseForeachStmt` (lines 3501–3543).
   - `parseExitContinStmt` (lines 3545–3585).
   - `parseReturnStmt` (lines 3587–3657: `RETURN`, `RETURN NEXT`, `RETURN QUERY`, `RETURN QUERY EXECUTE`).
   - `parseRaiseStmt` (lines 3659–3767) & `parseAssertStmt` (lines 3769–3786).
   - `parsePerformStmt` (lines 3788–3797) & `parseExecuteStmt` (lines 3799–3885).
   - `parseGetDiagnosticsStmt` (lines 3887–3945).
   - `parseOpenStmt` (lines 3947–4026), `parseFetchStmt` (lines 4028–4086), `parseMoveStmt` (lines 4088–4113), `parseCloseStmt` (lines 4115–4122).
   - `compileStaticSqlStmt` (lines 4124–4215: top-level `SELECT ... INTO [STRICT] ...` clause extraction and general DML/DDL execution).
   - Function body assembly (lines 4217–4248).
10. **Lines 4253–4270 (SQL Registration)**:
    Defines `plv8.compile_plpgsql(src text, meta jsonb DEFAULT '{}'::jsonb)` and creates `TRUSTED LANGUAGE plpgsql_v8`.

---

## 16. End-to-End Transpilation Examples

You can inspect the generated JavaScript for any PL/pgSQL snippet at any time using `SELECT plv8.compile_plpgsql(...)`.

### Example 1: Pure Procedural Logic & Static Integer Division

**Input PL/pgSQL**:
```sql
SELECT plv8.compile_plpgsql($$
DECLARE
  total int := 0;
  i int;
BEGIN
  FOR i IN 1..10 BY 2 LOOP
    IF i % 3 = 0 THEN
      CONTINUE;
    END IF;
    total := total + (i / 2);
  END LOOP;
  RETURN total;
END;
$$);
```

**Generated JavaScript**:
```javascript
const __rt = globalThis.__plpgsql_v8_rt;
const __pg = plv8;
let __found = false;
let __row_count = 0;
let __sqlstate = '00000';
let __sqlerrm = 'successful completion';
let __err_detail = '';
let __err_hint = '';
let __err_context = '';
let __err_schema = '';
let __err_table = '';
let __err_column = '';
let __err_datatype = '';
let __err_constraint = '';
let __cur_err = null;
let __ctrl = null;
let __v_total_1 = __rt.coerce(0, "int", false, "total");
let __v_i_2 = null;
{
  const __bound_lo_1 = Number(__rt.coerce(1, 'integer'));
  const __bound_hi_1 = Number(__rt.coerce(10, 'integer'));
  const __step_1 = Number(__rt.coerce(2, 'integer'));
  if (__step_1 <= 0) __rt.doRaise('EXCEPTION', '22023', 'step size cannot equal or be less than zero', [], {});
  __found = false;
  __lbl_1: for (let __idx_1 = __bound_lo_1; __idx_1 <= __bound_hi_1; __idx_1 += __step_1) {
    __v_i_2 = __idx_1;
    __found = true;
    if (__rt.truthy(__rt.eq(__rt.mod(__v_i_2, 3), 0))) {
      continue __lbl_1;
    }
    __v_total_1 = __rt.coerce(__rt.add(__v_total_1, (__rt.idiv(__v_i_2, 2))), "int", false, "total");
  }
}
return __v_total_1;
return;
```
Notice:
- Zero SPI (`__pg.execute`) calls are emitted!
- `i / 2` was statically determined to have integer operands (`i` is `int`, `2` is an integer literal), so `__rt.idiv(__v_i_2, 2)` is emitted directly.

### Example 2: `BEGIN ... EXCEPTION` with Non-Local `RETURN` and Stacked Diagnostics

**Input PL/pgSQL**:
```sql
SELECT plv8.compile_plpgsql($$
DECLARE
  v_msg text;
  v_detail text;
BEGIN
  BEGIN
    INSERT INTO items(id) VALUES (1);
    RETURN 'ok';
  EXCEPTION
    WHEN unique_violation THEN
      GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
      RETURN v_msg || ': ' || COALESCE(v_detail, '');
  END;
END;
$$);
```

**Generated JavaScript**:
```javascript
const __rt = globalThis.__plpgsql_v8_rt;
const __pg = plv8;
let __found = false;
let __row_count = 0;
let __sqlstate = '00000';
let __sqlerrm = 'successful completion';
let __err_detail = '';
let __err_hint = '';
let __err_context = '';
let __err_schema = '';
let __err_table = '';
let __err_column = '';
let __err_datatype = '';
let __err_constraint = '';
let __cur_err = null;
let __ctrl = null;
let __v_v_msg_1 = null;
let __v_v_detail_2 = null;
{
  let __caught_1 = null;
  __pg.subtransaction(function() {
    try {
      {
        const __res_2 = __pg.execute("INSERT INTO items(id) VALUES (1)", []);
        __row_count = (typeof __res_2 === 'number') ? __res_2 : (Array.isArray(__res_2) ? __res_2.length : 0);
        __found = __row_count > 0;
      }
      { __ctrl = { type: "return", value: "ok" }; return; }
    } catch (__e_1) {
      __caught_1 = __e_1;
      throw __e_1;
    }
  });
  if (__ctrl) {
    if (__ctrl.type === "return") return __ctrl.value;
  }
  if (__caught_1 !== null) {
    const __err_1 = __caught_1;
    const __prev_err_1 = __cur_err;
    const __prev_state_1 = __sqlstate;
    const __prev_errm_1 = __sqlerrm;
    const __prev_detail_1 = __err_detail;
    const __prev_hint_1 = __err_hint;
    const __prev_ctx_1 = __err_context;
    const __prev_schema_1 = __err_schema;
    const __prev_table_1 = __err_table;
    const __prev_col_1 = __err_column;
    const __prev_dtype_1 = __err_datatype;
    const __prev_cons_1 = __err_constraint;
    __cur_err = __err_1;
    __sqlstate = __rt.extractSqlState(__err_1);
    __sqlerrm = (__err_1 && __err_1.message !== undefined) ? String(__err_1.message) : String(__err_1);
    __err_detail = (__err_1 && __err_1.detail) ? String(__err_1.detail) : '';
    __err_hint = (__err_1 && __err_1.hint) ? String(__err_1.hint) : '';
    __err_context = (__err_1 && __err_1.context) ? String(__err_1.context) : '';
    __err_schema = (__err_1 && __err_1.schema_name) ? String(__err_1.schema_name) : '';
    __err_table = (__err_1 && __err_1.table_name) ? String(__err_1.table_name) : '';
    __err_column = (__err_1 && __err_1.column_name) ? String(__err_1.column_name) : '';
    __err_datatype = (__err_1 && __err_1.datatype_name) ? String(__err_1.datatype_name) : '';
    __err_constraint = (__err_1 && __err_1.constraint_name) ? String(__err_1.constraint_name) : '';
    if (__rt.matchException(__err_1, ["unique_violation"])) {
      __v_v_msg_1 = __rt.coerce(__sqlerrm, "text", false, "v_msg");
      __v_v_detail_2 = __rt.coerce(__err_detail, "text", false, "v_detail");
      return __rt.concat(__rt.concat(__v_v_msg_1, ": "), __rt.coalesce([__v_v_detail_2, ""]));
    } else {
      __cur_err = __prev_err_1;
      __sqlstate = __prev_state_1;
      __sqlerrm = __prev_errm_1;
      __err_detail = __prev_detail_1;
      __err_hint = __prev_hint_1;
      __err_context = __prev_ctx_1;
      __err_schema = __prev_schema_1;
      __err_table = __prev_table_1;
      __err_column = __prev_col_1;
      __err_datatype = __prev_dtype_1;
      __err_constraint = __prev_cons_1;
      throw __err_1;
    }
    __cur_err = __prev_err_1;
    __sqlstate = __prev_state_1;
    __sqlerrm = __prev_errm_1;
    __err_detail = __prev_detail_1;
    __err_hint = __prev_hint_1;
    __err_context = __prev_ctx_1;
    __err_schema = __prev_schema_1;
    __err_table = __prev_table_1;
    __err_column = __prev_col_1;
    __err_datatype = __prev_dtype_1;
    __err_constraint = __prev_cons_1;
  }
}
return;
```

---

## 17. Regression Test Suite Walk-Through (`sql/plpgsql_v8.sql`)

The test suite in `third_party/pgext/plv8/sql/plpgsql_v8.sql` (`lines 1–996`, with expected output `expected/plpgsql_v8.out` `lines 1–1183`) is organized into 10 major numbered sections (with sub-sections `1a–1c` and `10a–10g`) covering 18 functional areas:

1. **Section 1 (`lines 12–165`): Scalar Functions, Declarations, Scoping, Shadowing, Labels, 3VL, and 64-Bit `bigint` Arithmetic**:
   - Inspection helper (`plv8.compile_plpgsql`), `CONSTANT`, `NOT NULL`, `DEFAULT`, `ALIAS FOR`, nested `<<outer_lbl>>` / `<<inner_lbl>>` qualification, three-valued boolean logic (`AND`/`OR`/`NOT` with `NULL`), `BigInt` promotion above $2^{53}-1$, and integer division truncation (`1a`, `1b`, `1c`).
2. **Section 2 (`lines 167–325`): Control Flow**:
   - `IF`/`ELSIF`/`ELSE`, simple and searched `CASE` statements (including `case_not_found` exception when no `WHEN` matches and `ELSE` is absent), `CASE` expressions, `LOOP`, `WHILE`, integer `FOR` (`..`, `REVERSE`, `BY`), labeled `EXIT` / `CONTINUE` with `WHEN`, and 1-based arrays with `FOREACH x IN ARRAY` and `FOREACH s SLICE 1 IN ARRAY`.
3. **Section 3 (`lines 327–405`): Static SQL, `SELECT INTO [STRICT]`, `PERFORM`, and `FOUND`**:
   - DML/DDL execution, `ROW_COUNT` diagnostics, `SELECT INTO` with 0, 1, and >1 rows, and `STRICT` raising `P0002` (`no_data_found`) and `P0003` (`too_many_rows`).
4. **Section 4 (`lines 407–481`): Composite Types, `%ROWTYPE`, `%TYPE`, and `RECORD`**:
   - Composite variable declarations, field mutation (`rec.field := ...`), `table%ROWTYPE`, `table.col%TYPE`, and `var%TYPE`.
5. **Section 5 (`lines 483–518`): Dynamic SQL (`EXECUTE ... INTO [STRICT] ... USING`)**:
   - Parameterized dynamic queries and `ROW_COUNT`.
6. **Section 6 (`lines 520–626`): Exception Handling, `RAISE`, `ASSERT`, and `GET STACKED DIAGNOSTICS`**:
   - `WHEN division_by_zero`, `WHEN unique_violation`, `WHEN SQLSTATE '...'`, `WHEN OTHERS`, `GET STACKED DIAGNOSTICS` (`RETURNED_SQLSTATE`, `MESSAGE_TEXT`, `PG_EXCEPTION_DETAIL`, `PG_EXCEPTION_HINT`, `TABLE_NAME`, `CONSTRAINT_NAME`), bare `RAISE;` re-throw, and `ASSERT`.
7. **Section 7 (`lines 628–711`): Cursors**:
   - Unbound `refcursor`, bound `CURSOR (params) FOR ...`, `OPEN`, `FETCH` (`NEXT`, `PRIOR`, `FIRST`, `LAST`, `ABSOLUTE`, `RELATIVE`), `MOVE`, `CLOSE`, and cursor `FOR` loops.
8. **Section 8 (`lines 713–795`): Set-Returning Functions & `OUT` / `INOUT` Parameters**:
   - `RETURNS SETOF int` with `RETURN NEXT`, `RETURN QUERY`, `RETURN QUERY EXECUTE ... USING`, `RETURNS TABLE(...)`, single `OUT`, multiple `OUT`/`INOUT`, and `CREATE PROCEDURE` with `INOUT` via `CALL`.
9. **Section 9 (`lines 797–853`): Triggers**:
   - `BEFORE INSERT OR UPDATE` and `AFTER DELETE` triggers using `NEW`, `OLD`, `TG_OP`, `TG_NAME`, `TG_WHEN`, `TG_LEVEL`, `TG_TABLE_NAME`, `TG_NARGS`, and 0-based `TG_ARGV[0]`.
10. **Section 10 (`lines 855–996`): Inline `DO` Blocks, Interop, Security, Fallback Expressions, Subtransaction Unwinding, and SQL Identifier Disambiguation**:
    - Inline `DO $$ ... $$ LANGUAGE plpgsql_v8` (`10`), recursion & cross-language interop (`10a`, `10b`), security & `REVOKE` permissions (`10c`), SQL fallback expressions & operators (`10d`), `RETURN`/`EXIT` inside `BEGIN ... EXCEPTION` committing subtransaction writes (`10e`), nested `EXCEPTION` blocks restoring outer `SQLSTATE`/`SQLERRM` (`10f`), and column-name vs variable-name disambiguation in `INSERT ... ON CONFLICT DO UPDATE` and `UPDATE ... SET` (`10g`).
