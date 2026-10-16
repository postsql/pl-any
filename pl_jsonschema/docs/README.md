# pl-jsonschema (`pl_jsonschema`)

`pl_jsonschema` (also installable as `"pl-jsonschema"`) is a PostgreSQL extension that provides the **`"pl/jsonschema"`** trusted procedural language for validating JSON documents against [JSON Schema](https://json-schema.org/) definitions using [Ajv](https://github.com/ajv-validator/ajv).

It is implemented in JavaScript using the procedural language handler capabilities of either **`plv8`** (V8 engine) or **`pljs`** (QuickJS engine), and works seamlessly on **either `plv8` or `pljs`**.

---

## Prerequisites

- **PostgreSQL** (tested on PostgreSQL 19) with standard PGXS build tools (`pg_config`).
- Either **`plv8`** or **`pljs`** installed with JavaScript language handler support (where a JS function returning `language_handler` receives the target function's `prosrc` as `arguments[0]` and returns the transpiled JS function body).

---

## Building and Installing

Build and install the extension using PGXS:

```bash
make
make install
```

If `pg_config` is not on your default `PATH`, pass `PG_CONFIG`:

```bash
make PG_CONFIG=/path/to/pg_config
make PG_CONFIG=/path/to/pg_config install
```

### Enabling the Extension in PostgreSQL

First, enable either `plv8` or `pljs` in your target database, then create the `pl_jsonschema` extension:

```sql
-- Option A: Run on plv8
CREATE EXTENSION IF NOT EXISTS plv8;
CREATE EXTENSION pl_jsonschema;

-- Option B: Run on pljs
CREATE EXTENSION IF NOT EXISTS pljs;
CREATE EXTENSION pl_jsonschema;
```

*(You can also install the extension using the hyphenated alias `CREATE EXTENSION "pl-jsonschema";`.)*

### Selecting the JavaScript Engine Explicitly

During `CREATE EXTENSION pl_jsonschema`, the installation script determines which JavaScript procedural language (`plv8` or `pljs`) to bind its handlers to:

1. **Automatic detection (default)**: Checks `pg_catalog.pg_language` for an installed JS language (`plv8` first, then `pljs`).
2. **Explicit override via GUC**: If both `plv8` and `pljs` are installed in the same database, you can explicitly choose which engine `pl_jsonschema` binds to by setting `pl_jsonschema.engine` prior to `CREATE EXTENSION`:

```sql
SET pl_jsonschema.engine = 'pljs'; -- or 'plv8'
CREATE EXTENSION pl_jsonschema;
```

---

## Usage

### 1. Defining a JSON Schema Validation Function

Every `"pl/jsonschema"` function must:
- Be a normal function (`CREATE FUNCTION`, not `CREATE PROCEDURE`)
- Accept **exactly one `IN` argument of type `json`**
- Return **`boolean`** (scalar, not `SETOF boolean`)
- Have a valid JSON Schema (object or boolean schema) as its function body (`AS $$ ... $$`)

```sql
CREATE OR REPLACE FUNCTION validate_person(person json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "type": "object",
  "properties": {
    "name": { "type": "string", "minLength": 1 },
    "age":  { "type": "integer", "minimum": 0 },
    "tags": {
      "type": "array",
      "items": { "type": "string" },
      "uniqueItems": true
    }
  },
  "required": ["name", "age"],
  "additionalProperties": false
}
$$;

SELECT validate_person('{"name": "Alice", "age": 30, "tags": ["admin"]}');
--  validate_person
-- -----------------
--  t

SELECT validate_person('{"name": "Bob", "age": -5}');
--  validate_person
-- -----------------
--  f
```

### 2. Using `"pl/jsonschema"` in Table `CHECK` Constraints

Because `"pl/jsonschema"` validation functions are deterministic, you can mark them `IMMUTABLE STRICT` and use them directly in `CHECK` constraints:

```sql
CREATE TABLE people (
  id serial PRIMARY KEY,
  profile json NOT NULL CHECK (validate_person(profile))
);

INSERT INTO people (profile)
VALUES ('{"name": "Alice", "age": 30}'); -- succeeds

INSERT INTO people (profile)
VALUES ('{"name": "Alice"}');
-- ERROR:  new row for relation "people" violates check constraint "people_profile_check"
```

### 3. Referencing Other Schemas (`$id` and `$ref`)

Schemas with an `"$id"` property are registered in the session's `Ajv` instance and can be referenced from other `"pl/jsonschema"` functions via `"$ref"`. If a referenced schema function is not yet compiled in the current session, `"pl/jsonschema"` automatically discovers it in `pg_proc` and compiles it on demand:

```sql
CREATE OR REPLACE FUNCTION validate_address(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/address.json",
  "type": "object",
  "properties": {
    "street": { "type": "string" },
    "city":   { "type": "string" }
  },
  "required": ["street", "city"]
}
$$;

CREATE OR REPLACE FUNCTION validate_customer(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/customer.json",
  "type": "object",
  "properties": {
    "name":    { "type": "string" },
    "address": { "$ref": "https://example.com/schemas/address.json" }
  },
  "required": ["name", "address"]
}
$$;

SELECT validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": "NYC"}}');
--  validate_customer
-- -------------------
--  t
```

Updating a schema with `CREATE OR REPLACE FUNCTION` automatically evicts any prior schema with the same `$id` from `Ajv` and recompiles the validator.

---

## Running the Regression Tests

Run the PGXS regression test suite against a running PostgreSQL server:

```bash
# Run with default/auto-detected engine
make installcheck

# Explicitly test against plv8
make installcheck-plv8

# Explicitly test against pljs
make installcheck-pljs
```

The test suite (`sql/pl_jsonschema.sql`) covers:
- Negative installation tests (missing engine, invalid `pl_jsonschema.engine` GUC, simultaneous alias installation guard)
- Validator signature enforcement (rejects wrong argument count, non-`json` parameter, non-`boolean` return type, `SETOF`, `OUT`/`INOUT`/`VARIADIC` modes, and `PROCEDURE`s)
- Validator schema syntax & semantic validation (invalid JSON, non-schema JSON primitives, unknown keywords in Ajv strict mode, invalid regex patterns, wrong keyword types)
- Positive validation across object, array, string, numeric, enum, combinator (`allOf`/`anyOf`/`oneOf`/`not`), and boolean (`true`/`false`) schemas
- Parameter name isolation (parameters named `validator`, `pl`, `v`, or unnamed arguments do not collide with transpiled variables)
- `STRICT` vs non-`STRICT` `NULL` argument handling vs JSON `'null'::json`
- Function replacement (`CREATE OR REPLACE FUNCTION`) and `$id` re-registration
- Cross-function `$ref` and chained `$ref` resolution (including lazy loading of uncompiled `$id` schemas from `pg_proc` and automatic cache invalidation when referenced `$id` schemas are updated)
- Deferred compilation when functions are created with `SET check_function_bodies = off`
- Extension relocation (`ALTER EXTENSION pl_jsonschema SET SCHEMA ...`) and resilience to `search_path` changes
- Privilege and security checks (`REVOKE ALL ... FROM PUBLIC` on internal functions, unprivileged role execution and function creation)
- Draft-07 `"format"` annotations (`date-time`) and union types (`["null", "object"]` with nested `properties`)

---

## Comparative Benchmarks (`pl/v8` & `pl/js` vs. `supabase/pg_jsonschema`)

Across **251,755** GitHub Archive JSON records (`1.04 GB` raw JSON, `391.8 MB` LZ4-compressed in PostgreSQL 18.6) validated against 15 event-specific Draft-07 JSON Schemas (`1.75 KB` to `55.4 KB`):

| Engine / Mode | End-to-End Total (`ms`) | Net Validation Above LZ4 (`ms`) | Net Validation (`µs/row`) | Speedup vs. `pg_jsonschema` Uncompiled (End-to-End / Net) |
| :--- | ---: | ---: | ---: | ---: |
| **Baseline Index Scan + LZ4 Decompression** | **`3,428.52 ms`** | `0.00 ms` | `—` | `—` |
| **1. `pl/jsonschema` on `pl/v8` (V8 TurboFan JIT)** | **`4,870.00 ms`** | **`1,441.48 ms`** | **`5.73 µs/row`** | **`9.14x` / `28.49x` faster** |
| **2. `supabase/pg_jsonschema` Compiled (`json_matches_compiled_schema`)** | **`5,497.83 ms`** | **`2,069.31 ms`** | **`8.22 µs/row`** | **`8.09x` / `19.84x` faster** |
| **3. `pl/jsonschema` on `pl/js` (QuickJS Bytecode)** | **`9,237.10 ms`** | **`5,808.58 ms`** | **`23.07 µs/row`** | **`4.82x` / `7.07x` faster** |
| **4. `supabase/pg_jsonschema` Uncompiled (`json_matches_schema`)** | **`44,493.29 ms`** | **`41,064.77 ms`** | **`163.11 µs/row`** | `1.00x` / `1.00x` (baseline) |

See:
- [Full Comparative Benchmark Report (`docs/BENCHMARK_REPORT.md`)](BENCHMARK_REPORT.md)
- [Benchmark Execution Walkthrough (`docs/BENCHMARK_WALKTHROUGH.md`)](BENCHMARK_WALKTHROUGH.md)
- [Raw 15-Event Benchmark Dataset (`benchmarks/dev02_results.json`)](../benchmarks/dev02_results.json)

---

## Internal Architecture

1. **`ajv() RETURNS void`**: Evaluates the bundled Ajv library (`ajv_bundle.sql.gz`), exposing `globalThis.ajv_class()` along with the internal helper `globalThis.__pljsonschema_compile(...)` in the current session's JS context.
2. **`pljsonschema_call_handler() RETURNS language_handler`**: Invoked by `plv8` or `pljs` with the target `"pl/jsonschema"` function's source (`prosrc`) as `arguments[0]`. Parses and validates the JSON Schema, compiles it via `pl.ajv.compile(schema)` (automatically loading any referenced `$id` schemas from `pg_catalog.pg_proc` when external `$ref`s are present), caches the compiled validator in `pl.validator`, and returns a block-scoped JavaScript function body that validates `arguments[0]` and returns a `boolean`.
3. **`pljsonschema_call_validator(func_oid oid) RETURNS void`**: Invoked at `CREATE FUNCTION` time. Verifies the function signature (`(json) -> boolean`) and permissions in `pg_catalog.pg_proc`, and when `check_function_bodies = on`, triggers compilation via `pl.find_function(String(func_oid))` (with direct Ajv compilation fallback on `postsql/plv8` `v4.0`) so invalid JSON or invalid JSON Schema definitions are rejected immediately at `CREATE FUNCTION` time.
