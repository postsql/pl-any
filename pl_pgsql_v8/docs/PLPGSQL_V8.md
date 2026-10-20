# `plpgsql_v8` User Guide: PL/pgSQL on the V8 & QuickJS JavaScript Engines

`plpgsql_v8` is a PostgreSQL procedural language extension (`pl_pgsql_v8`) that compiles standard **PL/pgSQL** functions, procedures, triggers, and `DO` blocks into native **JavaScript** running on either **V8** (`plv8`) or **QuickJS** (`pljs`).

By compiling PL/pgSQL control flow (`IF`, `CASE`, `LOOP`, `WHILE`, `FOR`, `FOREACH`), variable assignments, array indexing, composite field manipulation, and scalar expressions directly to JavaScript bytecode/machine code—and by inlining eligible `RETURN QUERY` set-returning functions directly into the caller's outer PostgreSQL query plan via `SupportRequestSimplify` (`prosupport`)—`plpgsql_v8` eliminates PostgreSQL Server Programming Interface (SPI) overhead on procedural and compute-heavy workloads while preserving full access to PostgreSQL SQL, subtransactions (`EXCEPTION` blocks), cursors, and triggers.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Block Structure, Declarations & Scoping](#2-block-structure-declarations--scoping)
   - [2.1 Block Syntax & Labels](#21-block-syntax--labels)
   - [2.2 Variable Declarations (`DEFAULT`, `CONSTANT`, `NOT NULL`)](#22-variable-declarations-default-constant-not-null)
   - [2.3 Parameter Aliases (`ALIAS FOR`)](#23-parameter-aliases-alias-for)
   - [2.4 Copying Types (`%TYPE`) and Row Types (`%ROWTYPE`, `RECORD`)](#24-copying-types-type-and-row-types-rowtype-record)
3. [Expressions, Operators & Fast-Path Built-ins](#3-expressions-operators--fast-path-built-ins)
   - [3.1 Three-Valued Boolean Logic (`AND`, `OR`, `NOT`, `IS`)](#31-three-valued-boolean-logic-and-or-not-is)
   - [3.2 64-Bit `bigint` & Exact Arbitrary-Precision `numeric` Arithmetic](#32-64-bit-bigint--exact-arbitrary-precision-numeric-arithmetic)
   - [3.3 1-Based Array Indexing & Slicing](#33-1-based-array-indexing--slicing)
   - [3.4 Fast-Path SQL Built-ins vs Automatic SQL Fallback](#34-fast-path-sql-built-ins-vs-automatic-sql-fallback)
4. [Control Flow Statements](#4-control-flow-statements)
   - [4.1 Conditional Statements (`IF` and `CASE`)](#41-conditional-statements-if-and-case)
   - [4.2 Unconditional `LOOP`, `WHILE`, `EXIT`, and `CONTINUE`](#42-unconditional-loop-while-exit-and-continue)
   - [4.3 Integer `FOR` Loops](#43-integer-for-loops)
   - [4.4 Query `FOR` Loops (Static and Dynamic)](#44-query-for-loops-static-and-dynamic)
   - [4.5 Array `FOREACH` Loops (Including `SLICE`)](#45-array-foreach-loops-including-slice)
5. [Executing SQL Commands & Statement Plan Caching](#5-executing-sql-commands--statement-plan-caching)
   - [5.1 `SELECT ... INTO [STRICT]` and `FOUND`](#51-select--into-strict-and-found)
   - [5.2 `PERFORM`](#52-perform)
   - [5.3 Static DML (`INSERT`, `UPDATE`, `DELETE`) & Column Disambiguation](#53-static-dml-insert-update-delete--column-disambiguation)
   - [5.4 Dynamic SQL (`EXECUTE ... INTO [STRICT] ... USING`)](#54-dynamic-sql-execute--into-strict--using)
   - [5.5 Automatic SPI Statement Plan Caching (`rt._planCache`)](#55-automatic-spi-statement-plan-caching-rt_plancache)
6. [Error Trapping, `RAISE`, `ASSERT` & Diagnostics](#6-error-trapping-raise-assert--diagnostics)
   - [6.1 `BEGIN ... EXCEPTION WHEN ... END`](#61-begin--exception-when--end)
   - [6.2 `RAISE` and Re-Raising (`RAISE;`)](#62-raise-and-re-raising-raise)
   - [6.3 `ASSERT`](#63-assert)
   - [6.4 `GET CURRENT DIAGNOSTICS` and `GET STACKED DIAGNOSTICS`](#64-get-current-diagnostics-and-get-stacked-diagnostics)
7. [Cursors](#7-cursors)
   - [7.1 Unbound `refcursor` Variables](#71-unbound-refcursor-variables)
   - [7.2 Bound `CURSOR` Declarations with Parameters](#72-bound-cursor-declarations-with-parameters)
   - [7.3 `FETCH`, `MOVE`, `CLOSE`, and Cursor `FOR` Loops](#73-fetch-move-close-and-cursor-for-loops)
8. [Functions, Set-Returning Functions & Stored Procedures](#8-functions-set-returning-functions--stored-procedures)
   - [8.1 `OUT` and `INOUT` Parameters](#81-out-and-inout-parameters)
   - [8.2 Set-Returning Functions (`RETURN NEXT`, `RETURN QUERY`, `RETURNS TABLE`)](#82-set-returning-functions-return-next-return-query-returns-table)
   - [8.3 Planner-Level Outer-Plan `RETURN QUERY` Inlining (`prosupport`)](#83-planner-level-outer-plan-return-query-inlining-prosupport)
   - [8.4 Direct C/C++ SPI-to-Tuplestore Streaming (`plan.return_query`)](#84-direct-cc-spi-to-tuplestore-streaming-planreturn_query)
   - [8.5 Stored Procedures (`CREATE PROCEDURE`, `CALL`, `COMMIT`, `ROLLBACK`)](#85-stored-procedures-create-procedure-call-commit-rollback)
9. [Trigger Functions & Inline `DO` Blocks](#9-trigger-functions--inline-do-blocks)
   - [9.1 Row and Statement Triggers (`NEW`, `OLD`, `TG_*`, `TG_ARGV`)](#91-row-and-statement-triggers-new-old-tg_-tg_argv)
   - [9.2 Anonymous `DO` Blocks](#92-anonymous-do-blocks)
10. [Inspecting Generated JavaScript & Debugging](#10-inspecting-generated-javascript--debugging)
11. [Security, Permissions & Interoperability](#11-security-permissions--interoperability)

---

## 1. Getting Started

`plpgsql_v8` runs on top of either `plv8` (V8 engine) or `pljs` (QuickJS engine):

```sql
-- Using V8 (plv8):
CREATE EXTENSION IF NOT EXISTS plv8;
CREATE EXTENSION pl_pgsql_v8;

-- Or using QuickJS (pljs):
CREATE EXTENSION IF NOT EXISTS pljs;
CREATE EXTENSION pl_pgsql_v8;
```

To write a function in `plpgsql_v8`, use standard PL/pgSQL syntax and specify `LANGUAGE plpgsql_v8`:

```sql
CREATE FUNCTION fib(n integer) RETURNS integer AS $$
DECLARE
  a integer := 0;
  b integer := 1;
  tmp integer;
BEGIN
  IF n <= 0 THEN
    RETURN 0;
  END IF;
  FOR i IN 2..n LOOP
    tmp := a + b;
    a := b;
    b := tmp;
  END LOOP;
  RETURN b;
END;
$$ LANGUAGE plpgsql_v8 IMMUTABLE STRICT;

SELECT fib(10);
--  fib
-- -----
--   55
```

---

## 2. Block Structure, Declarations & Scoping

### 2.1 Block Syntax & Labels

A `plpgsql_v8` body consists of one or more nested blocks:

```sql
[ <<label>> ]
[ DECLARE
    declarations ]
BEGIN
    statements
[ EXCEPTION
    WHEN condition [ OR condition ... ] THEN
        handler_statements ]
END [ label ];
```

Nested blocks can shadow outer variables while still accessing outer variables through their block or function label (`outer_label.var_name`):

```sql
CREATE FUNCTION scope_demo(x int) RETURNS int AS $$
<<fn>>
DECLARE
  res int := 10;
BEGIN
  <<inner_blk>>
  DECLARE
    res int := 100;
  BEGIN
    -- Modify outer 'res' via label qualification while reading inner 'res':
    fn.res := fn.res + inner_blk.res + x;
  END inner_blk;

  RETURN res;
END fn;
$$ LANGUAGE plpgsql_v8;

SELECT scope_demo(5); -- Returns 115
```

### 2.2 Variable Declarations (`DEFAULT`, `CONSTANT`, `NOT NULL`)

Variables are declared in the `DECLARE` section before `BEGIN`:

```sql
DECLARE
  counter   integer := 0;
  greeting  text DEFAULT 'Hello';
  tax_rate  CONSTANT numeric := 0.0825;
  required  integer NOT NULL := 1;
```

- **`CONSTANT`**: Prevents reassigning the variable inside the block body (checked at compile time).
- **`NOT NULL`**: Enforces that the initial value and every subsequent assignment are non-null, raising SQLSTATE `22004` (`null_value_not_allowed`) if a `NULL` is assigned.
- **`COLLATE`**: Accepted in declarations (`name text COLLATE "C"`).

### 2.3 Parameter Aliases (`ALIAS FOR`)

You can declare an alias for any positional parameter (`$1`, `$2`, ...) or named variable:

```sql
CREATE FUNCTION add_alias(int, int) RETURNS int AS $$
DECLARE
  lhs ALIAS FOR $1;
  rhs ALIAS FOR $2;
BEGIN
  RETURN lhs + rhs;
END;
$$ LANGUAGE plpgsql_v8;
```

### 2.4 Copying Types (`%TYPE`) and Row Types (`%ROWTYPE`, `RECORD`)

`plpgsql_v8` supports all PostgreSQL dynamic and catalog-backed type declarations:

- **`variable%TYPE` and `table.column%TYPE`**: Copies the type of an existing PL/pgSQL variable or table column.
- **`table%ROWTYPE` and Composite Types**: Declares a composite row object pre-initialized with `{ col1: null, col2: null, ... }`.
- **`RECORD`**: Declares an untyped row variable whose structure is determined at runtime when assigned from `SELECT ... INTO`, `FOR r IN SELECT ...`, or `FETCH`.

```sql
CREATE TABLE employees (id int PRIMARY KEY, name text, salary int);
INSERT INTO employees VALUES (1, 'Alice', 120000);

CREATE FUNCTION get_employee_summary(p_id employees.id%TYPE) RETURNS text AS $$
DECLARE
  v_emp   employees%ROWTYPE;
  v_bonus v_emp.salary%TYPE := 15000;
BEGIN
  SELECT * INTO STRICT v_emp FROM employees WHERE id = p_id;
  v_emp.salary := v_emp.salary + v_bonus;
  RETURN v_emp.name || ' earns ' || v_emp.salary;
END;
$$ LANGUAGE plpgsql_v8;

SELECT get_employee_summary(1); -- 'Alice earns 135000'
```

---

## 3. Expressions, Operators & Fast-Path Built-ins

### 3.1 Three-Valued Boolean Logic (`AND`, `OR`, `NOT`, `IS`)

Unlike raw JavaScript, `plpgsql_v8` implements strict SQL three-valued logic (`TRUE`, `FALSE`, `NULL`):

- `FALSE AND NULL` evaluates to `FALSE`
- `TRUE AND NULL` evaluates to `NULL`
- `TRUE OR NULL` evaluates to `TRUE`
- `FALSE OR NULL` evaluates to `NULL`
- `NOT NULL` evaluates to `NULL`
- `IS [NOT] NULL`, `IS [NOT] TRUE`, `IS [NOT] FALSE`, `IS [NOT] UNKNOWN`, and `IS [NOT] DISTINCT FROM` behave identically to PostgreSQL SQL.

### 3.2 64-Bit `bigint` & Exact Arbitrary-Precision `numeric` Arithmetic

- **64-bit `bigint` (`int8`)**: Values above JavaScript's `Number.MAX_SAFE_INTEGER` ($2^{53} - 1 = 9,007,199,254,740,991$) are automatically promoted to JavaScript `BigInt` so 64-bit integer arithmetic never loses precision.
- **Exact Arbitrary-Precision `numeric` (`decimal`)**: `plpgsql_v8` enables `meta.preserve_numeric_precision = true` on `plv8` / `pljs`. Any `NUMERIC` value with more than 15 significant digits (or outside safe IEEE-754 `double` bounds) is marshaled between PostgreSQL and JavaScript as its exact decimal string representation, and `__plpgsql_v8_rt`'s arithmetic and comparison helpers (`add`, `sub`, `mul`, `cmpVal`, `uminus`, `coerce`) perform exact `BigInt`-scaled decimal arithmetic with zero precision loss across 38+ decimal digits.
- **Integer vs Float Division (`/`)**: When both operands of `/` are integer-typed (`smallint`, `integer`, `bigint`, or integer literals), `/` performs truncating integer division (`10 / 3 = 3`), matching SQL/PL/pgSQL. When either operand is floating-point or `numeric` (`10.0 / 3`), `/` performs floating-point division. Dividing by zero raises SQLSTATE `22012` (`division_by_zero`).

### 3.3 1-Based Array Indexing & Slicing

All PL/pgSQL array operations use PostgreSQL's **1-based** indexing and **inclusive** slice bounds (`lo:hi`):

```sql
CREATE FUNCTION array_ops() RETURNS int[] AS $$
DECLARE
  arr int[] := ARRAY[10, 20, 30, 40, 50];
  sub int[];
BEGIN
  arr[2] := 200;        -- Sets 2nd element -> {10, 200, 30, 40, 50}
  arr[4:5] := ARRAY[400, 500];
  sub := arr[2:4];      -- Extracts {200, 30, 400}
  RETURN sub;
END;
$$ LANGUAGE plpgsql_v8;
```

### 3.4 Fast-Path SQL Built-ins vs Automatic SQL Fallback

Common scalar and array functions are evaluated directly in V8 without SPI overhead:
- **String (`callBuiltin`)**: `LOWER`, `UPPER`, `LENGTH`, `CHAR_LENGTH`, `CHARACTER_LENGTH`, `BTRIM`, `TRIM`, `LTRIM`, `RTRIM`
- **Math (`callBuiltin`)**: `ABS`, `CEIL`, `CEILING`, `FLOOR`, `SIGN`, `SQRT`, `ROUND`, `TRUNC`, `MOD`, `POWER`, `POW`
- **Conditionals & Comparisons (`compileExpr`)**: `COALESCE`, `NULLIF`, `GREATEST`, `LEAST`, `CASE ... WHEN ... THEN ... ELSE ... END`, `CAST(expr AS type)`, `ARRAY[...]`, `BETWEEN`, `IN (...)`, `LIKE`, `ILIKE`, `IS [NOT] DISTINCT FROM`
- **Arrays (`callBuiltin`)**: `ARRAY_LENGTH`, `CARDINALITY`

Any expression that invokes another PostgreSQL catalog function (e.g. `substr(...)`, `replace(...)`, `md5(...)`, `now()`, `to_char(...)`, `regexp_replace(...)`, date/interval arithmetic, or subqueries) is **automatically** rewritten into a parameterized `SELECT (<expr>) AS __val` via SPI with all local PL/pgSQL variables safely bound as `$1, $2, ...`.

---

## 4. Control Flow Statements

### 4.1 Conditional Statements (`IF` and `CASE`)

Both `IF ... THEN ... ELSIF ... THEN ... ELSE ... END IF` and simple/searched `CASE` statements are supported:

```sql
CREATE FUNCTION classify_score(score int) RETURNS text AS $$
BEGIN
  CASE
    WHEN score >= 90 THEN RETURN 'A';
    WHEN score >= 80 THEN RETURN 'B';
    WHEN score >= 70 THEN RETURN 'C';
    ELSE RETURN 'F';
  END CASE;
END;
$$ LANGUAGE plpgsql_v8;
```

> **Note**: Just like native `plpgsql`, if a `CASE` *statement* has no matching `WHEN` branch and no `ELSE` clause, it raises SQLSTATE `20000` (`case_not_found`). (A `CASE` *expression* without an `ELSE` evaluates to `NULL`.)

### 4.2 Unconditional `LOOP`, `WHILE`, `EXIT`, and `CONTINUE`

Loops can be labeled (`<<outer_loop>>`) and exited or continued using `EXIT [label] [WHEN cond]` and `CONTINUE [label] [WHEN cond]`:

```sql
CREATE FUNCTION nested_loops() RETURNS int AS $$
DECLARE
  total int := 0;
  i int := 0;
  j int;
BEGIN
  <<outer_loop>>
  LOOP
    i := i + 1;
    EXIT outer_loop WHEN i > 5;
    j := 0;
    WHILE j < 5 LOOP
      j := j + 1;
      CONTINUE outer_loop WHEN i + j = 6;
      total := total + 1;
    END LOOP;
  END LOOP outer_loop;
  RETURN total;
END;
$$ LANGUAGE plpgsql_v8;
```

### 4.3 Integer `FOR` Loops

Integer `FOR` loops automatically declare their loop variable as `integer` within the loop scope if not already declared, and support `REVERSE` and `BY step`:

```sql
FOR i IN 1..10 LOOP ... END LOOP;
FOR i IN REVERSE 10..1 BY 2 LOOP ... END LOOP;
```

Note that in `REVERSE lo..hi`, the starting value is the first expression (`10`) and the lower bound is the second expression (`1`). Step sizes $\le 0$ raise SQLSTATE `22023` (`invalid_parameter_value`).

### 4.4 Query `FOR` Loops (Static and Dynamic)

Iterate over the result rows of a static `SELECT` or dynamic `EXECUTE` query:

```sql
-- Static query FOR loop
FOR rec IN SELECT id, name FROM employees ORDER BY id LOOP
  RAISE NOTICE 'Employee %: %', rec.id, rec.name;
END LOOP;

-- Dynamic query FOR loop with USING parameters
FOR rec IN EXECUTE 'SELECT id, name FROM employees WHERE salary >= $1' USING min_sal LOOP
  ...
END LOOP;
```

After the loop finishes, `FOUND` is set to `true` if at least one row was iterated, or `false` if the query returned zero rows.

### 4.5 Array `FOREACH` Loops (Including `SLICE`)

Iterate through the elements or lower-dimensional slices of an array:

```sql
DECLARE
  x int;
  slice_arr int[];
  matrix int[] := ARRAY[ARRAY[1, 2], ARRAY[3, 4]];
BEGIN
  -- Element-by-element (SLICE 0 / default):
  FOREACH x IN ARRAY matrix LOOP
    -- Visits 1, 2, 3, 4
  END LOOP;

  -- Slice-by-slice (SLICE 1):
  FOREACH slice_arr SLICE 1 IN ARRAY matrix LOOP
    -- Visits {1, 2}, then {3, 4}
  END LOOP;
END;
```

---

## 5. Executing SQL Commands & Statement Plan Caching

### 5.1 `SELECT ... INTO [STRICT]` and `FOUND`

Use `SELECT ... INTO [STRICT] target1, target2, ...` (or a single `RECORD` / `%ROWTYPE` target) to capture query results:

```sql
SELECT name, salary INTO v_name, v_salary
FROM employees
WHERE id = p_id;

IF NOT FOUND THEN
  RETURN 'Not found';
END IF;
```

- Without `STRICT`:
  - If 0 rows are returned, target variables are set to `NULL` and `FOUND` is `false`.
  - If 1 or more rows are returned, the first row is assigned to the targets and `FOUND` is `true`.
- With `STRICT`:
  - If 0 rows are returned, raises `no_data_found` (`P0002`).
  - If more than 1 row is returned, raises `too_many_rows` (`P0003`).

### 5.2 `PERFORM`

Execute a SQL query and discard the result (while still updating `FOUND`):

```sql
PERFORM 1 FROM employees WHERE id = p_id;
IF FOUND THEN
  -- Employee exists
END IF;
```

### 5.3 Static DML (`INSERT`, `UPDATE`, `DELETE`) & Column Disambiguation

You can run any `INSERT`, `UPDATE`, `DELETE`, or DDL statement directly. `plpgsql_v8`'s context-aware SQL rewriter automatically distinguishes target column names in `INSERT INTO tbl (col1, col2)`, `ON CONFLICT (col1)`, `UPDATE tbl SET col1 = ...`, and `WITH cte (col1) AS (...)` from PL/pgSQL variables of the same name:

```sql
CREATE FUNCTION upsert_employee(id int, name text, salary int) RETURNS void AS $$
BEGIN
  INSERT INTO employees (id, name, salary)
  VALUES (id, name, salary)
  ON CONFLICT (id) DO UPDATE
    SET name = EXCLUDED.name,
        salary = upsert_employee.salary;
END;
$$ LANGUAGE plpgsql_v8;
```

### 5.4 Dynamic SQL (`EXECUTE ... INTO [STRICT] ... USING`)

Build SQL strings dynamically and pass parameters safely via `USING`:

```sql
EXECUTE 'UPDATE ' || quote_ident(tbl_name) || ' SET salary = salary + $1 WHERE id = $2 RETURNING salary'
  INTO STRICT v_new_salary
  USING p_raise, p_id;
```

### 5.5 Automatic SPI Statement Plan Caching (`rt._planCache`)

All static `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `PERFORM`, `FOR ... IN SELECT`, `RETURN QUERY`, and fallback `evalSql` statements are automatically prepared and cached in `__plpgsql_v8_rt._planCache` via `plv8.prepare(sql)` / `pljs.prepare(sql)` and re-executed with `plan.execute(params)` or `plan.return_query(params, strict)`:
- **Zero Re-Planning Overhead**: Repeated calls to a `plpgsql_v8` function (or repeated iterations inside a loop) reuse the saved PostgreSQL `SPIPlanPtr`.
- **Automatic Cache Invalidation**: `rt._planCache` tracks `pg.proc_cache_key('*')` (`pg_proc` catalog invalidation counter) and automatically frees and clears cached plans whenever catalog changes occur or if a statement encounters a `cached plan must not change result type` (`0A000`) error after DDL such as `DROP TABLE` / `CREATE TABLE` or `ALTER TABLE`.
- **DDL Bypass**: Non-preparable utility/DDL statements (`CREATE`, `DROP`, `ALTER`, `TRUNCATE`, `SET`, `VACUUM`, etc.) automatically bypass `prepare()` and execute directly via `pg.execute()`.

---

## 6. Error Trapping, `RAISE`, `ASSERT` & Diagnostics

### 6.1 `BEGIN ... EXCEPTION WHEN ... END`

Any block can include an `EXCEPTION` section. If an error occurs inside the `BEGIN` statements, all database modifications made inside that `BEGIN` block are rolled back via a PostgreSQL subtransaction savepoint, while local PL/pgSQL variables retain the values they had when the error occurred:

```sql
CREATE FUNCTION safe_insert(p_id int, p_name text, p_salary int) RETURNS text AS $$
BEGIN
  INSERT INTO employees VALUES (p_id, p_name, p_salary);
  RETURN 'Inserted';
EXCEPTION
  WHEN unique_violation THEN
    RETURN 'Duplicate ID: ' || p_id;
  WHEN check_violation OR not_null_violation THEN
    RETURN 'Invalid data (' || SQLSTATE || '): ' || SQLERRM;
  WHEN SQLSTATE '22012' THEN
    RETURN 'Division by zero';
  WHEN OTHERS THEN
    RETURN 'Unexpected error [' || SQLSTATE || ']: ' || SQLERRM;
END;
$$ LANGUAGE plpgsql_v8;
```

### 6.2 `RAISE` and Re-Raising (`RAISE;`)

`RAISE` supports levels `DEBUG`, `LOG`, `INFO`, `NOTICE`, `WARNING`, and `EXCEPTION` (default), format strings with `%` placeholders (`%%` for a literal `%`), condition names, `SQLSTATE` codes, `USING` options, and bare `RAISE;` to re-throw the active exception inside an `EXCEPTION` handler:

```sql
-- Custom exception with USING options:
RAISE EXCEPTION 'Invalid salary % for employee %', p_salary, p_name
  USING ERRCODE = 'check_violation',
        DETAIL  = 'Salary must be positive.',
        HINT    = 'Provide a salary > 0.',
        TABLE   = 'employees',
        COLUMN  = 'salary';

-- Raise by condition name or SQLSTATE:
RAISE division_by_zero USING MESSAGE = 'Custom div by zero';
RAISE SQLSTATE 'P0099' USING MESSAGE = 'Application error';

-- Re-raise current exception inside a WHEN handler:
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Logging error % before re-raising', SQLERRM;
    RAISE;
```

### 6.3 `ASSERT`

Check invariants and raise `assert_failure` (`P0004`) if the condition is not true:

```sql
ASSERT v_balance >= 0, 'Account balance cannot be negative';
```

### 6.4 `GET CURRENT DIAGNOSTICS` and `GET STACKED DIAGNOSTICS`

- **`GET [CURRENT] DIAGNOSTICS`**: Retrieves execution state such as `ROW_COUNT` from the most recent SQL command:
  ```sql
  UPDATE employees SET salary = salary + 1000;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  ```
- **`GET STACKED DIAGNOSTICS`**: Inside an `EXCEPTION` handler, retrieves detailed metadata from the caught error:
  ```sql
  DECLARE
    v_state      text;
    v_msg        text;
    v_detail     text;
    v_hint       text;
    v_table      text;
    v_constraint text;
  BEGIN
    ...
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS
      v_state      = RETURNED_SQLSTATE,
      v_msg        = MESSAGE_TEXT,
      v_detail     = PG_EXCEPTION_DETAIL,
      v_hint       = PG_EXCEPTION_HINT,
      v_table      = TABLE_NAME,
      v_constraint = CONSTRAINT_NAME;
  END;
  ```

Supported stacked diagnostic items:
- `RETURNED_SQLSTATE`
- `MESSAGE_TEXT`
- `PG_EXCEPTION_DETAIL`
- `PG_EXCEPTION_HINT`
- `PG_EXCEPTION_CONTEXT`
- `SCHEMA_NAME`
- `TABLE_NAME`
- `COLUMN_NAME`
- `PG_DATATYPE_NAME`
- `CONSTRAINT_NAME`

---

## 7. Cursors

### 7.1 Unbound `refcursor` Variables

```sql
CREATE FUNCTION refcursor_example(min_sal int) RETURNS int AS $$
DECLARE
  cur refcursor;
  v_sal int;
  total int := 0;
BEGIN
  OPEN cur FOR SELECT salary FROM employees WHERE salary >= min_sal ORDER BY id;
  LOOP
    FETCH cur INTO v_sal;
    EXIT WHEN NOT FOUND;
    total := total + v_sal;
  END LOOP;
  CLOSE cur;
  RETURN total;
END;
$$ LANGUAGE plpgsql_v8;
```

You can also open a `refcursor` with a dynamic query:
```sql
OPEN cur FOR EXECUTE 'SELECT salary FROM employees WHERE salary >= $1' USING min_sal;
```

### 7.2 Bound `CURSOR` Declarations with Parameters

```sql
DECLARE
  emp_cur CURSOR (min_s int, max_s int) FOR
    SELECT id, name, salary FROM employees WHERE salary BETWEEN min_s AND max_s ORDER BY id;
BEGIN
  OPEN emp_cur(50000, 150000);
  ...
  CLOSE emp_cur;
END;
```

### 7.3 `FETCH`, `MOVE`, `CLOSE`, and Cursor `FOR` Loops

- **`FETCH [ direction ] cur INTO target ...`**: Supports `NEXT`, `PRIOR`, `FORWARD [n | ALL]`, `BACKWARD [n | ALL]`, and `RELATIVE n` (with `FROM` / `IN` keywords optional before the cursor name).
- **`MOVE [ direction ] cur`**: Repositions the cursor (`NEXT`, `PRIOR`, `FORWARD [n]`, `BACKWARD [n]`, `RELATIVE n`) without retrieving rows and updates `FOUND`.
- **`FOR rec IN bound_cur(arg1, arg2) LOOP ... END LOOP`**: Automatically opens the bound cursor on loop entry, fetches each row into `rec`, and closes the cursor in a `finally` block when the loop exits.

---

## 8. Functions, Set-Returning Functions & Stored Procedures

### 8.1 `OUT` and `INOUT` Parameters

Functions with `OUT` or `INOUT` parameters do not require an argument to `RETURN`:

```sql
CREATE FUNCTION min_max_sum(a int, b int, OUT lo int, OUT hi int, INOUT acc int) AS $$
BEGIN
  lo := LEAST(a, b);
  hi := GREATEST(a, b);
  acc := acc + a + b;
END;
$$ LANGUAGE plpgsql_v8;

SELECT * FROM min_max_sum(10, 4, 100);
--  lo | hi | acc
-- ----+----+-----
--   4 | 10 | 114
```

### 8.2 Set-Returning Functions (`RETURN NEXT`, `RETURN QUERY`, `RETURNS TABLE`)

`plpgsql_v8` supports `RETURNS SETOF <type>` and `RETURNS TABLE(col1 type1, ...)`:

```sql
CREATE FUNCTION filter_employees(min_sal int)
RETURNS TABLE(emp_id int, emp_name text) AS $$
BEGIN
  -- Yield rows from a static or dynamic query:
  RETURN QUERY
    SELECT id, name FROM employees WHERE salary >= min_sal ORDER BY id;

  -- Or populate output columns and call RETURN NEXT:
  emp_id := 999;
  emp_name := 'Synthetic Row';
  RETURN NEXT;
END;
$$ LANGUAGE plpgsql_v8;
```

Dynamic set-returning queries are also supported via `RETURN QUERY EXECUTE sql_string [USING arg1, ...]`.

### 8.3 Planner-Level Outer-Plan `RETURN QUERY` Inlining (`prosupport`)

When a set-returning `plpgsql_v8` function consists purely of `RETURN QUERY` statements (or conditional `IF ... ELSIF ... ELSE` / `CASE` branches containing `RETURN QUERY` and/or empty `RETURN;`), `plpgsql_v8` automatically registers `plv8_call_support` (`plv8`) or `pljs_call_support` (`pljs`) as the function's `pg_proc.prosupport` planner hook (`meta.support_func`).

When PostgreSQL plans an outer query that calls the function in a `FROM` clause (`FuncExpr` or `RangeTblFunction`), `SupportRequestSimplify` / `SupportRequestInlineInFrom` replaces the `FunctionScan` node with the underlying SQL query AST directly in the outer execution plan:
- **Zero JS & Zero SPI Execution Overhead**: The inlined query participates directly in outer-query join reordering, index scans, predicate pushdown, `LIMIT` early termination, and parallel query execution.
- **Supported `RETURN QUERY` Shapes**:
  - Single `RETURN QUERY SELECT ...` or `RETURN QUERY WITH ... SELECT ...`
  - Multiple sequential `RETURN QUERY` statements (combined via `UNION ALL`)
  - `IF ... THEN ... ELSIF ... THEN ... ELSE ... END IF` and `CASE ... WHEN ... END CASE` branches containing `RETURN QUERY` and/or `RETURN;`:
    - When all arguments in a branch condition are compile-time constants (`Const`), the planner folds the condition at plan time and emits **only** the matching branch's query without `Result` / `One-Time Filter` wrappers.
    - When conditions depend on runtime parameters or `LATERAL` columns, each branch is guarded by a `WHERE (<cond>)` `One-Time Filter` inside a `UNION ALL` (or `WHERE` clause for single-branch `IF`).
  - All return types: `RETURNS TABLE(...)`, `RETURNS SETOF <composite_type>`, `RETURNS SETOF <scalar_type>`, and `RETURNS SETOF record` (with caller `AS (col1 type1, ...)` column definition lists).
- **Controlling Volatile SRF Inlining (`plpgsql_v8.inline_volatile_srf`)**:
  - By default (`plpgsql_v8.inline_volatile_srf = 'on'`), both `VOLATILE` (PostgreSQL's default volatility when `IMMUTABLE`/`STABLE` is omitted) and `STABLE`/`IMMUTABLE` `RETURN QUERY` SRFs are inlined.
  - Set `SET plpgsql_v8.inline_volatile_srf = 'off';` to restrict planner inlining to functions explicitly declared `STABLE` or `IMMUTABLE` (read via the zero-SPI C++ fast path `pg.current_setting('plpgsql_v8.inline_volatile_srf', true)`).

### 8.4 Direct C/C++ SPI-to-Tuplestore Streaming (`plan.return_query`)

When a set-returning `plpgsql_v8` function is not inlined into the outer plan (for example, when it mixes `RETURN QUERY` with procedural loops, local variable mutations, `RETURN NEXT`, or `RETURN QUERY EXECUTE`), `RETURN QUERY` and `RETURN QUERY EXECUTE` execute entirely in C/C++ via `plan.return_query(params, true)` and `plv8.return_query(sql, params, true)`:
- **Zero JS Row Materialization**: Rows returned by `SPI_execute_plan` / `SPI_execute` are written directly from `SPI_tuptable` into the SRF's `ReturnSetInfo` `Tuplestorestate` (`tupstore`) in C/C++ without creating JavaScript objects or V8/QuickJS values per row, returning only the integer row count (`SPI_processed`) to JavaScript to update `FOUND` and `ROW_COUNT`.
- **Whole-Tuple Fast Path**: When the query's `SPI_tuptable->tupdesc` column types match the function's output `tupdesc`, tuples are copied directly via `tuplestore_puttuple` without per-column `heap_getattr` / `tuplestore_putvalues` overhead.
- **Strict PL/pgSQL Column Structure Verification (`42804`)**: Passing `strict = true` enforces native PL/pgSQL `ERRCODE_DATATYPE_MISMATCH` (`42804`: `"structure of query does not match function result type"`) whenever the number of result columns or any column's type OID differs from the declared SRF output descriptor (while allowing binary-coercible types via `IsBinaryCoercible`).

### 8.5 Stored Procedures (`CREATE PROCEDURE`, `CALL`, `COMMIT`, `ROLLBACK`)

Stored procedures created with `CREATE PROCEDURE ... LANGUAGE plpgsql_v8` can use `INOUT` / `OUT` parameters and transaction control statements (`COMMIT` and `ROLLBACK`):

```sql
CREATE PROCEDURE give_raise(p_id int, INOUT p_amount int) AS $$
BEGIN
  UPDATE employees SET salary = salary + p_amount WHERE id = p_id RETURNING salary INTO p_amount;
END;
$$ LANGUAGE plpgsql_v8;

CALL give_raise(1, 5000);
```

---

## 9. Trigger Functions & Inline `DO` Blocks

### 9.1 Row and Statement Triggers (`NEW`, `OLD`, `TG_*`, `TG_ARGV`)

Trigger functions (`RETURNS trigger`) have full access to:
- `NEW` and `OLD` row records (mutable in `BEFORE` row-level triggers)
- `TG_NAME`, `TG_WHEN` (`'BEFORE'`, `'AFTER'`, `'INSTEAD OF'`), `TG_LEVEL` (`'ROW'`, `'STATEMENT'`), `TG_OP` (`'INSERT'`, `'UPDATE'`, `'DELETE'`, `'TRUNCATE'`), `TG_RELID`, `TG_TABLE_NAME`, `TG_RELNAME`, `TG_TABLE_SCHEMA`, `TG_NARGS`
- `TG_ARGV`: **0-indexed** array of trigger string arguments (`TG_ARGV[0]` is the first argument, matching PostgreSQL PL/pgSQL).

```sql
CREATE FUNCTION emp_audit_trig() RETURNS trigger AS $$
DECLARE
  default_prefix text := COALESCE(TG_ARGV[0], 'EMP: ');
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.name := default_prefix || NEW.name;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.salary < 0 THEN
      RAISE EXCEPTION 'Salary cannot be negative';
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql_v8;
```

### 9.2 Anonymous `DO` Blocks

Execute ad-hoc procedural blocks without creating a persistent function:

```sql
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id, name FROM employees ORDER BY id LOOP
    RAISE NOTICE 'Employee #% is %', r.id, r.name;
  END LOOP;
END;
$$ LANGUAGE plpgsql_v8;
```

---

## 10. Inspecting Generated JavaScript & Debugging

To inspect the exact JavaScript code produced by the `plpgsql_v8` compiler for any PL/pgSQL snippet, call `plv8.compile_plpgsql(src text, meta jsonb DEFAULT NULL)` (available to superusers or roles granted `EXECUTE` on `plv8.compile_plpgsql`):

```sql
SELECT plv8.compile_plpgsql($$
DECLARE
  x int := 10;
BEGIN
  RETURN x * 2;
END;
$$);
```

Output:
```javascript
const __pg = (typeof plv8 !== "undefined") ? plv8 : pljs;
const __rt = globalThis.__plpgsql_v8_rt;
let __found = false;
let __last_row_count = 0;
let __ctrl = null;
let __cur_err = null;
let __sqlstate = "00000";
let __sqlerrm = "";
let __err_detail = "";
let __err_hint = "";
let __err_context = "";
let __err_schema = "";
let __err_table = "";
let __err_column = "";
let __err_datatype = "";
let __err_constraint = "";
__blk_2: {
let __v1_x = __rt.coerce(10, "int", false, "x");
return __rt.mul(__v1_x, 2);
}
return;
```

---

## 11. Security, Permissions & Interoperability

- **Trusted Language**: `plpgsql_v8` is registered as a `TRUSTED` language (`CREATE TRUSTED LANGUAGE plpgsql_v8`). By default, database users can create `plpgsql_v8` functions unless `REVOKE USAGE ON LANGUAGE plpgsql_v8 FROM PUBLIC` is executed by an administrator.
- **Role Isolation**: Each PostgreSQL user executes inside a dedicated V8 Isolate, preventing cross-role memory or global state access.
- **Handler Protection**: Direct SQL execution of `plv8_plpgsql_handler()` and `plv8.compile_plpgsql(text, jsonb)` is revoked from `PUBLIC`.
- **Seamless Interop**: `plpgsql_v8` functions, native `plpgsql` functions, `sqltsm_v8` functions, and `plv8` JavaScript functions can call one another freely within the same query or transaction.

For architectural details and a code walk-through of the compiler and runtime, see [`PLPGSQL_HIGH_LEVEL_DESIGN.md`](./PLPGSQL_HIGH_LEVEL_DESIGN.md), [`PLPGSQL_V8_DESIGN.md`](./PLPGSQL_V8_DESIGN.md), and [`PLPGSQL_IMPLEMENTATION_WALKTHROUGH.md`](./PLPGSQL_IMPLEMENTATION_WALKTHROUGH.md).
