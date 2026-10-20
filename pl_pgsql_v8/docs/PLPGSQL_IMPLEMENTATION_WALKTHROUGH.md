<!-- disableFinding(LINE_OVER_80) -->
<!-- disableFinding(HEADING_FUNCTION) -->

# PL/pgSQL+V8 (`plpgsql_v8`) Implementation Walk-Through

This document provides a file-by-file, function-by-function implementation walk-through of `plpgsql_v8`, tracing how a PL/pgSQL routine is validated, transpiled to JavaScript, compiled in V8, and executed against PostgreSQL's Server Programming Interface (SPI).

---

## 1. Source File Inventory

| File | Line Range | Role in `plpgsql_v8` |
| :--- | :--- | :--- |
| `plv8.h` | `54–80`, `320–391`, `424` | Declares `js_error` with full PostgreSQL `ErrorData` fields (`m_code`, `m_detail`, `m_hint`, `m_context`, `m_schema_name`, `m_table_name`, `m_column_name`, `m_datatype_name`, `m_constraint_name`, `m_internalquery`, `m_internalpos`), `PLV8_MAX_LANG_HANDLER_DEPTH` (`32`), `plv8_handler_dep`, `HandlerExecutionScope`, `CurrentContextScope`, and `plv8_pass_user_types_as_bytes`. |
| `plv8.cc` | `121–142`, `898–994`, `1207–1237`, `1762–1838`, `1983–2182`, `3294–3568` | Implements `plv8_proc_cache`, `PassUserTypesScope`, `plv8_call_handler`, `plv8_inline_handler`, `plv8_call_validator`, `plv8_transpile_src`, and `js_error` diagnostic round-tripping. |
| `plv8_func.cc` | `503–583`, `858–1517` | Populates `ErrorData` diagnostic properties on JS `Error` exceptions in `plv8_FunctionInvoker` and wraps `Prepare`, `PlanCursor`, `PlanExecute`, `CursorFetch`, `CursorMove`, `CursorClose`, and `Subtransaction` in `SubTranBlock`. |
| `plv8.sql.common` | `94–4270` | Implements `plv8_plpgsql_handler()`, `COND_MAP`, `globalThis.__plpgsql_v8_rt`, `tokenize()`, `compilePlpgsql()`, `plv8.compile_plpgsql()`, and `CREATE TRUSTED LANGUAGE plpgsql_v8`. |
| `generate_upgrade.sh` | `85–87` | Strips `CREATE TRUSTED LANGUAGE plpgsql_v8` from upgrade scripts and replaces it with an idempotent `DO` block checking `pg_language` (`lanname = 'plpgsql_v8'`). |
| `sql/plpgsql_v8.sql` | `1–996` | End-to-end SQL regression test suite (Sections 1–10, including sub-sections `1a–1c` and `10a–10g`). |
| `expected/plpgsql_v8.out` | `1–1183` | Expected regression test output. |

---

## 2. Step-by-Step C++ Engine Walk-Through

### Step 1: Chained Language Registration (`plv8.sql.common:4253-4270`)
When `CREATE EXTENSION plv8` executes:
```sql
CREATE OR REPLACE FUNCTION plv8.compile_plpgsql(src text, meta jsonb DEFAULT '{}'::jsonb)
RETURNS text AS $$
  return plv8.find_function("plv8_plpgsql_handler")(src, meta || {});
$$ LANGUAGE plv8 VOLATILE;

CREATE TRUSTED LANGUAGE plpgsql_v8
  HANDLER plv8_plpgsql_handler
  INLINE plv8_inline_handler
  VALIDATOR plv8_call_validator;

REVOKE ALL ON FUNCTION plv8_plpgsql_handler() FROM PUBLIC;
REVOKE ALL ON FUNCTION plv8.compile_plpgsql(text, jsonb) FROM PUBLIC;
```
- `plv8_plpgsql_handler()` is a SQL function with `RETURNS language_handler` and `LANGUAGE plv8`.
- Because `plv8_plpgsql_handler` itself is written in `LANGUAGE plv8`, PostgreSQL's function manager (`fmgr_info`) resolves its C entry point to `plv8_call_handler`.

### Step 2: Function Validation & Cache Invalidation (`plv8.cc:1762-1838`)
When a user runs `CREATE OR REPLACE FUNCTION my_fn(...) LANGUAGE plpgsql_v8`:
1. PostgreSQL calls `plv8_call_validator(fn_oid)`.
2. `plv8_call_validator` checks `CheckFunctionValidatorAccess` (if `check_function_bodies` is enabled).
3. It fetches the function's `pg_proc` tuple and verifies that if `rettype` is a pseudotype, it is one of `TRIGGEROID`, `VOIDOID`, `RECORDOID`, `LANGUAGE_HANDLEROID`, or a polymorphic type (`plv8.cc:1792-1804`).
4. It unconditionally calls `plv8_cache_function_remove(fn_oid)` (`plv8.cc:1813`), which removes `fn_oid` from the current user's `ProcCacheHash` and also evicts any cached downstream functions whose `cache->handlers[]` dependency list contains `fn_oid` (`plv8.cc:1762-1780`).
5. Finally, it calls `Compile(fn_oid, NULL, true, is_trigger)` (`plv8.cc:1827`), which transpiles and V8-compiles the function body immediately.

### Step 3: Walking the Handler Chain & Transpiling Source (`plv8.cc:1983-2182`)
Inside `Compile()` (or `plv8_inline_handler` for `DO` blocks), `plv8_transpile_src` is called:
1. **Walk `pg_language` -> `pg_proc` (`plv8.cc:1995-2066`)**:
   - Looks up the OID of the base `"plv8"` language in `LANNAME` (`plv8_lang_oid`).
   - While `cur_lang_oid != plv8_lang_oid` (up to `PLV8_MAX_LANG_HANDLER_DEPTH = 32` hops):
     - Looks up `cur_lang_oid` in `LANGOID` (`pg_language`), checking `pg_language_aclcheck(cur_lang_oid, GetUserId(), ACL_USAGE)` at `depth == 0`.
     - Reads `lanForm->lanplcallfoid` (at `depth == 0`, this is saved as `lang_handler_oid`, i.e., `plv8_plpgsql_handler`).
     - Looks up `handler_oid` in `PROCOID` (`pg_proc`), records `(fn_oid, fn_xmin, fn_tid)` in `deps[depth]`, and advances `cur_lang_oid = procForm->prolang`.
   - Copies `deps[]` into `proc->cache->handlers[]` (`nhandlers`).
2. **Resolve Handler & Construct `meta` Object (`plv8.cc:2068-2136`)**:
   - Enters `HandlerExecutionScope` and resolves `lang_handler_oid` via `find_js_function(lang_handler_oid)` (which recursively compiles any intermediate handler if needed).
   - For a catalog function/procedure (`proc != NULL && proc->cache != NULL`), builds a second argument `meta` (`call_argc = 2`) with:
     - `fn_oid` (`uint32`), `proname` (`string`), `rettype_oid` (`uint32`), `rettype_category` (`string`), `rettype_len` (`int32`), `argtype_oids` (`Array`), `argtype_categories` (`Array`), `argtype_lens` (`Array`), and `retset` (`boolean`).
   - For an inline `DO` block (`proc == NULL`, called from `plv8_inline_handler` at `plv8.cc:1222-1224`), `call_argc = 1` (`meta` is omitted, and `plv8_plpgsql_handler` defaults `meta = {}`).
3. **Invoke `plv8_plpgsql_handler(raw_prosrc, meta)` (`plv8.cc:2138-2177`)**:
   - Calls `DoCall(context, fn, recv, call_argc, args, false)`.
   - Checks if `meta.pass_user_types_as_bytes` was set by the handler (defaulting to `false` for `plpgsql_v8`, whereas `"pl/v8-wasm"` defaults to `true`).
   - Converts the returned JS string into a `palloc`'d C string containing the transpiled JavaScript body.

### Step 4: Error & Subtransaction Plumbing (`plv8.h:54-80`, `plv8.cc:3294-3568`, `plv8_func.cc:503-583`)
1. **Subtransaction Safety on All SPI Entry Points (`plv8_func.cc:858-1517`)**:
   - `plv8_Execute` (`858–883`), `plv8_Prepare` (`889–975`, wrapping `SPI_prepare_params`/`SPI_prepare` + `SPI_saveplan` + `SPI_freeplan`), `plv8_PlanCursor` (`981–1111`, wrapping `SPI_cursor_open_with_paramlist`/`SPI_cursor_open`), `plv8_PlanExecute` (`1117–1242`, wrapping `SPI_execute_plan_with_paramlist`/`SPI_execute_plan`), `plv8_CursorFetch` (`1291–1363`, wrapping `SPI_cursor_fetch`), `plv8_CursorMove` (`1369–1414`, wrapping `SPI_cursor_move`), and `plv8_CursorClose` (`1420–1450`, wrapping `SPI_cursor_close`) all execute inside a `SubTranBlock` (`PG_TRY` / `BeginInternalSubTransaction` -> `ReleaseCurrentSubTransaction` / `RollbackAndReleaseCurrentSubTransaction`).
2. **Capturing PostgreSQL `ErrorData` into V8 (`plv8_func.cc:518-577`)**:
   - When `SubTranBlock` rolls back and throws `pg_error`, `plv8_FunctionInvoker` calls `CopyErrorData()` and populates `sqlerrcode` (5-character string from `unpack_sql_state(edata->sqlerrcode)`), `code` (integer `MAKE_SQLSTATE`), `detail`, `hint`, `context`, `schema_name`, `table_name`, `column_name`, `datatype_name`, `constraint_name`, `internalquery`, and `internalpos` on the V8 `Error` object.
3. **Preserving Diagnostics Across `plv8.subtransaction()` and `ereport()` (`plv8.cc:3294-3568`)**:
   - `js_error::init` reads `err.code` / `err.sqlerrcode` (parsing 5-char `SQLSTATE` strings via `plv8_parse_sqlerrcode`) and all optional diagnostic string properties via `plv8_extract_err_string_field`.
   - `js_error::error_object()` reconstructs a V8 `Error` with all those properties when `plv8_Subtransaction` re-throws an error into the outer JS `catch` block.
   - `js_error::rethrow()` passes `errcode(m_code)`, `errdetail`, `errhint`, `errcontext`, and `err_generic_string(PG_DIAG_*, ...)` to PostgreSQL's `ereport(ERROR, ...)`.

---

## 3. Step-by-Step JS Compiler & Runtime Walk-Through (`plv8.sql.common`)

### 3.0 Sub-Module Map in `plv8.sql.common` (`lines 94–4270`)

| Line Range | Function / Object | Purpose |
| :--- | :--- | :--- |
| `99–317` | `COND_MAP` | Maps ~160 PostgreSQL condition names and 2-char class names to SQLSTATE strings. |
| `319–1105` | `ensureRuntime()` (`globalThis.__plpgsql_v8_rt`) | Installs singleton runtime helper library on `globalThis.__plpgsql_v8_rt`. |
| `1107–1327` | `tokenize(src)` | Single-pass lexical scanner for PL/pgSQL source text. |
| `1329–1736` | `compilePlpgsql(src, meta)` (Catalog & Scope Setup) | Queries `pg_proc`/`pg_type`/`pg_attribute`, manages `scopeStack`, and binds parameters/trigger variables. |
| `1738–1969` | `rewriteSqlTokensWithParams(tokSlice, extraScopeMap)` | Context-aware SQL token rewriter binding PL/pgSQL variables as `$1, $2, ...`. |
| `1971–2499` | `compileExpr(tokSlice)` | Hybrid recursive-descent pure-JS expression compiler with automatic `__rt.evalSql` fallback. |
| `2501–2636` | `parseTargetLValue`, `emitRowToTargets` | L-value parser and row-to-target assignment emitter (`:=`, `INTO [STRICT]`, `FETCH`). |
| `2638–2871` | `parseDeclareSection()` | Parses `DECLARE` variables, `ALIAS FOR`, `%TYPE`, `%ROWTYPE`, `RECORD`, `REFCURSOR`, and bound `CURSOR`s. |
| `2873–2889` | `emitCtrlUnwindCheck()` | Emits non-local `RETURN` / `EXIT` / `CONTINUE` unwinding checks across subtransaction boundaries. |
| `2891–3036` | `parseStmtList()`, `parseBlock(optLabel)` | Parses `BEGIN ... [EXCEPTION WHEN ...] END` blocks and subtransaction wrappers. |
| `3038–3164` | `parseOneStmt()` | Main statement dispatcher (labels, blocks, control flow, cursors, SQL, assignments). |
| `3166–3229` | `parseIfStmt()`, `parseCaseStmt()` | `IF / ELSIF / ELSE / END IF` and simple/searched `CASE` statements. |
| `3231–3585` | `parseLoopStmt`, `parseWhileStmt`, `parseForStmt`, `parseForeachStmt`, `parseExitContinStmt` | All loop constructs and labeled/conditional `EXIT` / `CONTINUE`. |
| `3587–3797` | `parseReturnStmt`, `parseRaiseStmt`, `parseAssertStmt`, `parsePerformStmt` | `RETURN [NEXT | QUERY]`, `RAISE`, `ASSERT`, and `PERFORM`. |
| `3799–3945` | `parseExecuteStmt`, `parseGetDiagnosticsStmt` | Dynamic `EXECUTE ... INTO [STRICT] ... USING` and `GET [CURRENT | STACKED] DIAGNOSTICS`. |
| `3947–4122` | `parseOpenStmt`, `parseFetchStmt`, `parseMoveStmt`, `parseCloseStmt` | Bound and unbound cursor lifecycle statements. |
| `4124–4215` | `compileStaticSqlStmt()` | Static `SELECT ... INTO [STRICT]` extraction and DML/DDL execution. |
| `4217–4248` | Function body assembly | Emits preamble, root block, default `return`, and returns generated JS source. |
| `4253–4270` | `plv8.compile_plpgsql` & `CREATE TRUSTED LANGUAGE plpgsql_v8` | Registers inspection helper, language, and `REVOKE ALL ... FROM PUBLIC` guards. |

### 3.1 Condition Map (`COND_MAP`, `plv8.sql.common:99-317`)
Maps ~160 standard PostgreSQL condition names (`division_by_zero`, `unique_violation`, `no_data_found`, `too_many_rows`, `raise_exception`, `assert_failure`, `case_not_found`, etc.) to their 5-character `SQLSTATE` codes, and class names (`data_exception`, `integrity_constraint_violation`, `plpgsql_error`, etc.) to their 2-character class prefixes.

### 3.2 Singleton Runtime (`ensureRuntime`, `plv8.sql.common:319-1105`)
Installed once per V8 isolate at `globalThis.__plpgsql_v8_rt`:
- **Error & `RAISE` Helpers (`lines 324-427`)**:
  - `formatRaise(fmt, args)`: Replaces single `%` placeholders sequentially with `toText(args[i])` and unescapes `%%` to `%`.
  - `doRaise(level, codeOrCond, fmt, args, opts)`: Logs via `plv8.elog(level, msg)` for `DEBUG`/`LOG`/`INFO`/`NOTICE`/`WARNING`, or constructs and throws a rich `Error` via `makeError` for `EXCEPTION`.
  - `matchException(err, condSpecs)`: Compares `extractSqlState(err)` against each condition in a `WHEN` clause (supporting `'OTHERS'`, 5-char `SQLSTATE`, and 2-char class prefixes).
- **3VL & 64-Bit `BigInt` Math (`lines 429-588`)**:
  - `and(a, b)`, `or(a, b)`, `not(a)`: Exact SQL three-valued truth tables.
  - `add`, `sub`, `mul`, `idiv`, `div`, `mod`, `pow`, `uplus`, `uminus`: Propagate `null` if either operand is `null`/`undefined`, promote to `BigInt` when outside `Number.isSafeInteger`, normalize safe `BigInt` results back to `Number` via `normBigInt`, and throw SQLSTATE `22012` on division/modulo by zero.
- **Comparisons, `LIKE`/`ILIKE`, and 1-Based Arrays (`lines 590-821`)**:
  - `cmpVal`, `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `isDistinctFrom`, `between`, `inList`, `like`, `coalesce`, `nullif`, `greatest`, `least`.
  - `getElem`, `getSlice`, `setElem`, `setSlice`, `setField`, `flattenForeach`. Note that `getElem(arr, idx)` checks `arr.__zeroIndexed ? arr[i] : arr[i - 1]` so `TG_ARGV` is 0-indexed while all SQL arrays are 1-indexed.
- **Type Coercion & SPI / Cursor / Built-In Helpers (`lines 823-1101`)**:
  - `coerce(val, sqlType, notNull, varName)`: Pure in-JS type coercion and `NOT NULL` enforcement (`22004`) for `boolean`, `int2`/`int4`/`int8` (with half-away-from-zero rounding and range checks raising `22003`), `float4`/`float8`/`numeric`, `text`/`varchar`, arrays (`type[]`), and `json`/`jsonb`. (Explicit SQL `CAST(x AS t)` / `x::t` to non-`PURE_CAST_TYPES` throws `new Error('fallback')` in `compileExpr` so `compileExpr` delegates the expression to `__rt.evalSql`.)
  - `evalSql`, `returnNext`, `returnQuery` (delegating to `plv8.return_query` for direct C++ SPI-to-tuplestore streaming when available, with fallback to `plv8.execute` + `returnNext`), `openCursor` (returning `{ plan, portal, sql }`), `fetchCursor`, `moveCursor`, `closeCursor`.
  - `callBuiltin(fname, args)` (`lines 1028-1101`): Evaluates 21 pure-JS built-ins (`lower`, `upper`, `length`, `char_length`, `character_length`, `btrim`, `trim`, `ltrim`, `rtrim`, `abs`, `ceil`, `ceiling`, `floor`, `sign`, `sqrt`, `round`, `trunc`, `mod`, `power`, `pow`, `array_length`, `cardinality`).

### 3.3 Lexical Scanner (`tokenize`, `plv8.sql.common:1107-1327`)
Scans the PL/pgSQL source string in a single pass, tracking 1-based line numbers (`line`) and emitting tokens:
- Single-line (`--`) and nested block (`/* ... */`) comments (skipped)
- `#variable_conflict` directives (`type: 'directive'`, skipped by the parser)
- Positional parameters (`$1`, `$2`, ..., `type: 'param'`)
- Dollar-quoted strings (`$$...$$`, `$tag$...$tag$`), `E'...'` escape strings, and `'...'` strings (`type: 'string'`, with decoded `strVal`)
- Double-quoted identifiers (`"..."`, `type: 'ident', quoted: true`) and unquoted identifiers/keywords (`type: 'ident', quoted: false`)
- Numbers (`type: 'number', isFloat`, stopping before `..` range operators so `1..10` lexes as `1`, `..`, `10`)
- 2-char/1-char operators (`type: 'op'`) and punctuation (`type: 'punct'`).

### 3.4 Catalog Introspection & Scope Initialization (`plv8.sql.common:1329-1736`)
1. Queries `pg_proc` and `pg_type` for `meta.fn_oid` to determine argument modes (`IN`, `OUT`, `INOUT`, `VARIADIC`, `TABLE`), argument names/types, return type, `proretset`, and `prokind`.
2. Pre-populates the root scope with `FOUND` (`__found`), `SQLSTATE` (`__sqlstate`), `SQLERRM` (`__sqlerrm`), trigger variables (`NEW`, `OLD`, `TG_*` when `isTrigger`, wrapping `TG_ARGV` into `__tg_argv` with non-enumerable `__zeroIndexed: true`), and function parameters (`$1..$N` plus named parameter aliases).
3. Parses optional top-level `<<label>>` and `DECLARE` sections before the root `BEGIN ... END` block.

### 3.5 Context-Aware SQL Rewriter (`rewriteSqlTokensWithParams`, `plv8.sql.common:1738-1969`)
Rewrites token slices of static SQL statements or fallback SQL expressions:
- Tracks SQL syntactic context (`stmtType`, `inInsertCols`, `inConflictCols`, `inCteCols`, `inUpdateSet`, `inUpdateSetCols`, `afterSetComma`, `parenDepth`) so target column names in `INSERT INTO tbl (col1, col2)`, `ON CONFLICT (col1)`, `WITH cte (col1) AS (...)`, and `UPDATE tbl SET col1 = ...` are preserved as SQL identifiers while right-hand side and `WHERE`/`VALUES` references to PL/pgSQL variables are replaced by `$1`, `$2`, ... (with `($N::type)` casts for scalar types).

### 3.6 Hybrid Expression Compiler (`compileExpr`, `plv8.sql.common:1971-2499`)
1. Checks for SQL-only keywords (`SELECT`, `EXISTS`, `ANY`, `SOME`, `ALL`, `OVER`, `INTERVAL`, etc.) and throws `new Error('fallback')` if present.
2. Runs recursive-descent parsing (`parseOr` -> `parseAnd` -> `parseNot` -> `parseComp` -> `parseAdd` -> `parseMul` -> `parseExp` -> `parseUnary` -> `parsePostfix` -> `parsePrimary`), returning typed AST nodes `{ code, type }`.
3. Uses `isIntType(l.type) && isIntType(r.type)` (`line 2165`) to emit `__rt.idiv(l, r)` when both operands of `/` are statically integer-typed and `__rt.div(l, r)` otherwise.
4. On `catch (e)` (when `new Error('fallback')` is thrown or tokens remain unconsumed), delegates to `rewriteSqlTokensWithParams` and emits `__rt.evalSql("SELECT (" + sql + ") AS __val", [...])`.

### 3.7 Statement Parsers & Subtransaction Unwinding (`plv8.sql.common:2873-4248`)
- **`parseBlock` & `emitCtrlUnwindCheck` (`lines 2873-3036`)**:
  - When `EXCEPTION` handlers are present, increments `subtranDepth`, wraps the `BEGIN` body in `__pg.subtransaction(function() { ... })`, and emits `emitCtrlUnwindCheck()` after the subtransaction commits to unwind non-local `__ctrl = { type: "return", value: ... }` or `{ type: "exit" | "continue", jsLabel: ... }`.
  - In the `catch (__err_N)` handler, saves previous diagnostic variables (`__cur_err`, `__sqlstate`, `__sqlerrm`, `__err_detail`, `__err_hint`, `__err_context`, `__err_schema`, `__err_table`, `__err_column`, `__err_datatype`, `__err_constraint`) and restores them after the handler finishes.
- **Control Flow, Cursors, SRFs, and SQL Statements (`lines 3038-4244`)**:
  - Compiles `IF`, `CASE`, `LOOP`, `WHILE`, `FOR` (integer, bound/unbound cursor, dynamic `EXECUTE`, static `SELECT`), `FOREACH`, `EXIT`, `CONTINUE`, `RETURN` / `RETURN NEXT` / `RETURN QUERY`, `RAISE`, `ASSERT`, `PERFORM`, `EXECUTE`, `GET [CURRENT | STACKED] DIAGNOSTICS`, `OPEN` / `FETCH` / `MOVE` / `CLOSE`, `COMMIT` / `ROLLBACK`, assignments, and static `SELECT ... INTO [STRICT]` / DML.

---

## 4. Concrete PL/pgSQL-to-V8-JS Compilation Walkthroughs

You can inspect the exact JavaScript generated by `plv8_plpgsql_handler` for any function body using `SELECT plv8.compile_plpgsql($$ ... $$)`.

### Walkthrough A: Pure-JS Loop, `IF`/`CONTINUE`, and Static Integer Division

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

**Actual Transpiled JavaScript Output**:
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

### Walkthrough B: Subtransaction Exception Block, Non-Local `RETURN`, and `GET STACKED DIAGNOSTICS`

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

**Actual Transpiled JavaScript Output**:
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

## 5. Related Documentation

- **High-Level Design**: [PLPGSQL_HIGH_LEVEL_DESIGN.md](PLPGSQL_HIGH_LEVEL_DESIGN.md)
- **Detailed Design Document**: [PLPGSQL_V8_DESIGN.md](PLPGSQL_V8_DESIGN.md)
- **User Guide & Language Reference**: [PLPGSQL_V8.md](PLPGSQL_V8.md)
