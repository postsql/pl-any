--
-- Regression tests for pl_jsonschema ("pl/jsonschema" procedural language)
-- Compatible with both plv8 and pljs engines.
--

\set VERBOSITY terse
SET client_min_messages = warning;

DROP EXTENSION IF EXISTS pl_jsonschema CASCADE;
DROP EXTENSION IF EXISTS "pl-jsonschema" CASCADE;
DROP EXTENSION IF EXISTS plv8 CASCADE;
DROP EXTENSION IF EXISTS pljs CASCADE;

-- ============================================================================
-- 1. Negative installation tests
-- ============================================================================

DO $$
BEGIN
  PERFORM pg_catalog.set_config(
    'pl_jsonschema.saved_engine',
    COALESCE(pg_catalog.current_setting('pl_jsonschema.engine', true), ''),
    false
  );
  PERFORM pg_catalog.set_config('pl_jsonschema.engine', '', false);
END;
$$;

-- Installing pl_jsonschema without plv8 or pljs present in the database fails
CREATE EXTENSION pl_jsonschema;

-- Invalid pl_jsonschema.engine setting fails
SET pl_jsonschema.engine = 'invalid_engine';
CREATE EXTENSION pl_jsonschema;

DO $$
BEGIN
  PERFORM pg_catalog.set_config(
    'pl_jsonschema.engine',
    COALESCE(pg_catalog.current_setting('pl_jsonschema.saved_engine', true), ''),
    false
  );
END;
$$;

-- ============================================================================
-- 2. Load JS engine (plv8 or pljs) and install pl_jsonschema
-- ============================================================================

DO $$
DECLARE
  v_engine text;
BEGIN
  v_engine := NULLIF(pg_catalog.current_setting('pl_jsonschema.engine', true), '');
  IF v_engine IS NULL THEN
    SELECT name INTO v_engine
      FROM pg_catalog.pg_available_extensions
     WHERE name IN ('plv8', 'pljs')
     ORDER BY CASE name WHEN 'plv8' THEN 1 WHEN 'pljs' THEN 2 END
     LIMIT 1;
  END IF;

  IF v_engine IS NULL THEN
    RAISE EXCEPTION 'Neither plv8 nor pljs is available for regression testing';
  END IF;

  EXECUTE pg_catalog.format('CREATE EXTENSION %I', v_engine);
END;
$$;

-- Requesting the other (uninstalled) engine via GUC fails cleanly
DO $$
DECLARE
  v_missing text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_language WHERE lanname = 'plv8') THEN
    v_missing := 'pljs';
  ELSE
    v_missing := 'plv8';
  END IF;
  PERFORM pg_catalog.set_config('pl_jsonschema.engine', v_missing, true);
  BEGIN
    CREATE EXTENSION pl_jsonschema;
    RAISE EXCEPTION 'unexpected success';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'pl/jsonschema: requested language % is not installed in this database' THEN
      RAISE;
    END IF;
  END;
  -- Clear pl_jsonschema.engine so the initial CREATE EXTENSION tests auto-detection
  PERFORM pg_catalog.set_config('pl_jsonschema.engine', '', false);
END;
$$;

CREATE EXTENSION pl_jsonschema;

-- Simultaneous installation of both alias names is rejected cleanly
CREATE EXTENSION "pl-jsonschema";

-- Verify language catalog entry and underlying engine binding
SELECT lanname, lanispl, lanpltrusted
  FROM pg_catalog.pg_language
 WHERE lanname = 'pl/jsonschema';

DO $$
DECLARE
  v_expected text;
  v_actual text;
BEGIN
  v_expected := NULLIF(pg_catalog.current_setting('pl_jsonschema.saved_engine', true), '');
  SELECT l.lanname INTO v_actual
    FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_language l ON l.oid = p.prolang
   WHERE p.proname = 'pljsonschema_call_handler';

  IF v_actual NOT IN ('plv8', 'pljs') THEN
    RAISE EXCEPTION 'unexpected handler language: %', v_actual;
  END IF;

  IF v_expected IS NOT NULL AND v_actual <> v_expected THEN
    RAISE EXCEPTION 'expected handler language %, got %', v_expected, v_actual;
  END IF;

  -- Restore explicit pl_jsonschema.engine (if any) for subsequent extension creation tests
  PERFORM pg_catalog.set_config('pl_jsonschema.engine', COALESCE(v_expected, ''), false);
END;
$$;

-- ============================================================================
-- 3. Validator negative tests: function signature enforcement
-- ============================================================================

-- 0 arguments
CREATE FUNCTION bad_sig_noargs() RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

-- 2 arguments
CREATE FUNCTION bad_sig_twoargs(a json, b json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

-- Non-json argument types (jsonb, text, int)
CREATE FUNCTION bad_sig_jsonb(a jsonb) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

CREATE FUNCTION bad_sig_text(a text) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

CREATE FUNCTION bad_sig_int(a int) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "integer"}
$$;

-- Non-boolean return types (text, json, int, void)
CREATE FUNCTION bad_ret_text(a json) RETURNS text
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

CREATE FUNCTION bad_ret_json(a json) RETURNS json
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

CREATE FUNCTION bad_ret_int(a json) RETURNS int
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

CREATE FUNCTION bad_ret_void(a json) RETURNS void
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

-- Set-returning function (SETOF boolean)
CREATE FUNCTION bad_ret_setof(a json) RETURNS SETOF boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

-- OUT and VARIADIC parameters
CREATE FUNCTION bad_out_param(IN a json, OUT b boolean)
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

CREATE FUNCTION bad_variadic_param(VARIADIC a json[]) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "array"}
$$;

-- Procedure in pl/jsonschema
CREATE PROCEDURE bad_proc(a json)
LANGUAGE "pl/jsonschema" AS $$
{"type": "object"}
$$;

-- Inline DO block is not supported
DO $$
{"type": "object"}
$$ LANGUAGE "pl/jsonschema";

-- ============================================================================
-- 4. Validator negative tests: invalid JSON and invalid JSON Schemas
-- ============================================================================

-- Empty body
CREATE FUNCTION bad_schema_empty(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$$$;

-- Whitespace-only body
CREATE FUNCTION bad_schema_whitespace(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$   $$;

-- Malformed JSON syntax
CREATE FUNCTION bad_schema_syntax(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object",}
$$;

-- Non-object, non-boolean JSON values (null, array, number, string)
CREATE FUNCTION bad_schema_null(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
null
$$;

CREATE FUNCTION bad_schema_array(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
[{"type": "string"}]
$$;

CREATE FUNCTION bad_schema_number(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
42
$$;

CREATE FUNCTION bad_schema_string(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
"object"
$$;

-- Invalid JSON Schema keywords/types rejected by AJV compilation
CREATE FUNCTION bad_schema_unknown_type(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "not_a_valid_json_schema_type"}
$$;

CREATE FUNCTION bad_schema_bad_minimum(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "number", "minimum": "not_a_number"}
$$;

CREATE FUNCTION bad_schema_bad_required(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "object", "required": "not_an_array"}
$$;

-- ============================================================================
-- 5. Core JSON Schema validation (Slides 33-35 & Draft-07 features)
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_test_schema_a(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS
$$
{
  "type": "object",
  "properties": {
    "a": {"type": "number"},
    "b": {"type": "string"}
  }
}
$$;

-- Direct function calls
SELECT validate_test_schema_a('{"a": 4, "b": "7"}');
SELECT validate_test_schema_a('{"a": -1.5, "b": ""}');
SELECT validate_test_schema_a('{}');
SELECT validate_test_schema_a('{"a": "4", "b": "7"}');
SELECT validate_test_schema_a('{"a": 4, "b": 7}');
SELECT validate_test_schema_a('[]');
SELECT validate_test_schema_a('42');
SELECT validate_test_schema_a('"hello"');
SELECT validate_test_schema_a('true');
SELECT validate_test_schema_a('null'::json);
SELECT validate_test_schema_a(NULL);

-- Table CHECK constraint (Slide 34)
CREATE TABLE bench_test_pg_jsonschema_a (
    meta json,
    CHECK (validate_test_schema_a(meta))
);

INSERT INTO bench_test_pg_jsonschema_a(meta) VALUES ('{"a": 4, "b": "7"}');
INSERT INTO bench_test_pg_jsonschema_a(meta) VALUES (NULL);
-- Violates check constraint:
INSERT INTO bench_test_pg_jsonschema_a(meta) VALUES ('{"a": "4", "b": "7"}');

-- Bulk insert (Slide 35)
INSERT INTO bench_test_pg_jsonschema_a(meta)
SELECT
    json_build_object(
        'a', i,
        'b', i::text
    )
FROM
    generate_series(1, 500) t(i);

SELECT count(*) FROM bench_test_pg_jsonschema_a;
DROP TABLE bench_test_pg_jsonschema_a;

-- ============================================================================
-- 6. Unnamed arguments, boolean schemas, complex schemas, $ref, and $id
-- ============================================================================

-- Unnamed argument
CREATE FUNCTION validate_unnamed_arg(json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "integer", "minimum": 0, "maximum": 100}
$$;

SELECT validate_unnamed_arg('0'),
       validate_unnamed_arg('100'),
       validate_unnamed_arg('-1'),
       validate_unnamed_arg('101'),
       validate_unnamed_arg('3.14');

-- Parameter names matching internal transpiled identifiers (validator, pl, v) must not collide
CREATE FUNCTION validate_param_validator(validator json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "string", "minLength": 1}
$$;

CREATE FUNCTION validate_param_pl(pl json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "integer"}
$$;

CREATE FUNCTION validate_param_v(v json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "boolean"}
$$;

SELECT validate_param_validator('"ok"'),
       validate_param_validator('""'),
       validate_param_pl('42'),
       validate_param_pl('"no"'),
       validate_param_v('true'),
       validate_param_v('0');

DROP FUNCTION validate_param_validator(json);
DROP FUNCTION validate_param_pl(json);
DROP FUNCTION validate_param_v(json);

-- Boolean schemas (Draft-07: true accepts everything, false rejects everything)
CREATE FUNCTION validate_always_true(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
true
$$;

CREATE FUNCTION validate_always_false(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
false
$$;

SELECT validate_always_true('{}'),
       validate_always_true('123'),
       validate_always_true('null'::json),
       validate_always_false('{}'),
       validate_always_false('123'),
       validate_always_false('null'::json);

-- Null type schema with STRICT vs non-STRICT
CREATE FUNCTION validate_null_strict(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "null"}
$$;

CREATE FUNCTION validate_null_nonstrict(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE AS $$
{"type": "null"}
$$;

SELECT validate_null_strict('null'::json) AS json_null_strict,
       validate_null_strict(NULL::json) AS sql_null_strict,
       validate_null_nonstrict('null'::json) AS json_null_nonstrict,
       validate_null_nonstrict(NULL::json) AS sql_null_nonstrict,
       validate_null_nonstrict('0'::json) AS zero_nonstrict;

-- Complex schema with definitions, $ref, pattern, enum, array uniqueItems, and $id
CREATE OR REPLACE FUNCTION validate_order(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/order.json",
  "type": "object",
  "definitions": {
    "sku": {
      "type": "string",
      "pattern": "^[A-Z]{3}-[0-9]{4}$"
    },
    "item": {
      "type": "object",
      "properties": {
        "sku": { "$ref": "#/definitions/sku" },
        "qty": { "type": "integer", "minimum": 1 }
      },
      "required": ["sku", "qty"],
      "additionalProperties": false
    }
  },
  "properties": {
    "order_id": { "type": "integer", "minimum": 1 },
    "status": { "enum": ["pending", "paid", "shipped"] },
    "tags": {
      "type": "array",
      "items": { "type": "string" },
      "uniqueItems": true
    },
    "items": {
      "type": "array",
      "minItems": 1,
      "items": { "$ref": "#/definitions/item" }
    }
  },
  "required": ["order_id", "status", "items"],
  "additionalProperties": false
}
$$;

-- Valid order
SELECT validate_order('{
  "order_id": 101,
  "status": "paid",
  "tags": ["priority", "gift"],
  "items": [{"sku": "ABC-1234", "qty": 2}]
}');

-- Invalid SKU pattern
SELECT validate_order('{
  "order_id": 101,
  "status": "paid",
  "items": [{"sku": "bad-sku", "qty": 2}]
}');

-- Duplicate tags (violates uniqueItems)
SELECT validate_order('{
  "order_id": 101,
  "status": "paid",
  "tags": ["dup", "dup"],
  "items": [{"sku": "ABC-1234", "qty": 2}]
}');

-- Empty items array (violates minItems: 1)
SELECT validate_order('{
  "order_id": 101,
  "status": "paid",
  "items": []
}');

-- ============================================================================
-- 7. CREATE OR REPLACE FUNCTION cache invalidation (including same $id)
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_order(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/order.json",
  "type": "object",
  "properties": {
    "order_id": { "type": "string" }
  },
  "required": ["order_id"],
  "additionalProperties": false
}
$$;

-- Previously valid integer order_id is now rejected; string order_id is accepted
SELECT validate_order('{"order_id": 101}') AS int_id_after_replace,
       validate_order('{"order_id": "ORD-101"}') AS str_id_after_replace;

-- Cross-function $id / $ref and chained $ref resolution
-- Create validate_country with check_function_bodies = off so it is NOT yet in pl.ajv
SET check_function_bodies = off;
CREATE OR REPLACE FUNCTION validate_country(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/country.json",
  "type": "string",
  "pattern": "^[A-Z]{2}$"
}
$$;
RESET check_function_bodies;

-- validate_address references country.json (which must be lazily discovered from pg_proc)
CREATE OR REPLACE FUNCTION validate_address(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/address.json",
  "type": "object",
  "properties": {
    "street":  { "type": "string" },
    "city":    { "type": "string" },
    "country": { "$ref": "https://example.com/schemas/country.json" }
  },
  "required": ["street", "city"],
  "additionalProperties": false
}
$$;

-- validate_customer references address.json (chained $ref: customer -> address -> country)
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
  "required": ["name", "address"],
  "additionalProperties": false
}
$$;

-- Unresolvable external $ref is rejected at CREATE FUNCTION time
CREATE FUNCTION bad_unresolved_ref(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{
  "type": "object",
  "properties": {
    "missing": { "$ref": "https://example.com/schemas/nonexistent.json" }
  }
}
$$;

SELECT validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": "NYC", "country": "US"}}') AS valid_customer,
       validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": "NYC", "country": "usa"}}') AS bad_country_customer,
       validate_customer('{"name": "Alice", "address": {"street": "1 Main St"}}') AS missing_city_customer;

-- Calling validate_customer in a brand-new JS context (via a separate role where neither
-- validate_country nor validate_address has ever been called) lazily loads both from pg_proc
CREATE ROLE regress_pljsonschema_ref_user;
SET ROLE regress_pljsonschema_ref_user;
SELECT validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": "NYC", "country": "US"}}') AS fresh_ctx_valid_customer,
       validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": 123}}') AS fresh_ctx_invalid_customer;
RESET ROLE;

-- Updating a referenced $id schema (validate_address) automatically invalidates
-- dependent $ref validators (validate_customer) in both superuser and unprivileged contexts
CREATE OR REPLACE FUNCTION validate_address(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$id": "https://example.com/schemas/address.json",
  "type": "object",
  "properties": {
    "street":  { "type": "string" },
    "city":    { "type": "integer" },
    "country": { "$ref": "https://example.com/schemas/country.json" }
  },
  "required": ["street", "city"],
  "additionalProperties": false
}
$$;

SELECT validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": "NYC"}}') AS str_city_after_ref_update,
       validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": 10001}}') AS int_city_after_ref_update;

SET ROLE regress_pljsonschema_ref_user;
SELECT validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": "NYC"}}') AS role_str_city_after_ref_update,
       validate_customer('{"name": "Alice", "address": {"street": "1 Main St", "city": 10001}}') AS role_int_city_after_ref_update;
RESET ROLE;

DROP ROLE regress_pljsonschema_ref_user;
DROP FUNCTION validate_customer(json);
DROP FUNCTION validate_address(json);
DROP FUNCTION validate_country(json);

-- ============================================================================
-- 8. check_function_bodies = off behavior
-- ============================================================================

SET check_function_bodies = off;

-- Signature errors are still caught even when check_function_bodies = off
CREATE FUNCTION bad_sig_body_off(data int) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "integer"}
$$;

-- Invalid JSON body is deferred until call time when check_function_bodies = off
CREATE FUNCTION deferred_bad_schema(data json) RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{invalid json
$$;

-- Replacing an existing function while check_function_bodies = off still invalidates cache
CREATE OR REPLACE FUNCTION validate_order(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "type": "object",
  "properties": {
    "order_id": { "type": "boolean" }
  },
  "required": ["order_id"],
  "additionalProperties": false
}
$$;

RESET check_function_bodies;

SELECT validate_order('{"order_id": "ORD-101"}') AS str_after_off_replace,
       validate_order('{"order_id": true}') AS bool_after_off_replace;

-- Calling deferred_bad_schema fails at execution time
SELECT deferred_bad_schema('{}');
DROP FUNCTION deferred_bad_schema(json);

-- ============================================================================
-- 9. Custom schema, search_path resilience, and extension relocation
-- ============================================================================

CREATE SCHEMA app_schemas;
CREATE FUNCTION app_schemas.validate_tag(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "string", "minLength": 2}
$$;

SET search_path = pg_catalog;
SELECT app_schemas.validate_tag('"ok"'::pg_catalog.json) AS valid_with_empty_search_path,
       app_schemas.validate_tag('"x"'::pg_catalog.json) AS invalid_with_empty_search_path;
RESET search_path;

-- Relocate extension to another schema and back
CREATE SCHEMA ext_reloc_schema;
ALTER EXTENSION pl_jsonschema SET SCHEMA ext_reloc_schema;
SELECT app_schemas.validate_tag('"still_works"');
ALTER EXTENSION pl_jsonschema SET SCHEMA public;
DROP SCHEMA ext_reloc_schema;

-- ============================================================================
-- 10. Security, privilege, and direct validator/handler negative tests
-- ============================================================================

-- Direct validator calls by superuser on invalid OIDs or wrong languages
SELECT pljsonschema_call_validator(0);
SELECT pljsonschema_call_validator('pg_catalog.now'::regproc);
SELECT pljsonschema_call_validator(NULL);

-- Unprivileged role testing
CREATE ROLE regress_pljsonschema_user;
GRANT USAGE, CREATE ON SCHEMA app_schemas TO regress_pljsonschema_user;

SET ROLE regress_pljsonschema_user;

-- Unprivileged user cannot directly invoke internal functions
SELECT ajv();
SELECT pljsonschema_call_handler();
SELECT pljsonschema_call_validator('app_schemas.validate_tag'::regproc);

-- Unprivileged user CAN execute existing pl/jsonschema functions (initializes user's JS context)
SELECT app_schemas.validate_tag('"hello"'),
       app_schemas.validate_tag('"a"');

-- Unprivileged user CAN create pl/jsonschema functions when USAGE on language is granted
CREATE FUNCTION app_schemas.user_validator(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "boolean"}
$$;

SELECT app_schemas.user_validator('true'),
       app_schemas.user_validator('123');

RESET ROLE;

-- Revoking USAGE on language "pl/jsonschema" blocks unprivileged function creation
REVOKE USAGE ON LANGUAGE "pl/jsonschema" FROM PUBLIC;

SET ROLE regress_pljsonschema_user;
CREATE FUNCTION app_schemas.user_validator_blocked(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" AS $$
{"type": "boolean"}
$$;
RESET ROLE;

GRANT USAGE ON LANGUAGE "pl/jsonschema" TO PUBLIC;

-- Cleanup test role and objects
DROP SCHEMA app_schemas CASCADE;
DROP ROLE regress_pljsonschema_user;
DROP FUNCTION validate_test_schema_a(json);
DROP FUNCTION validate_unnamed_arg(json);
DROP FUNCTION validate_always_true(json);
DROP FUNCTION validate_always_false(json);
DROP FUNCTION validate_null_strict(json);
DROP FUNCTION validate_null_nonstrict(json);
DROP FUNCTION validate_order(json);

-- ============================================================================
-- 11. Verify hyphenated extension alias ("pl-jsonschema")
-- ============================================================================

DROP EXTENSION pl_jsonschema;
CREATE EXTENSION "pl-jsonschema";

CREATE FUNCTION validate_hyphen_ext(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{"type": "string"}
$$;

SELECT validate_hyphen_ext('"ok"'),
       validate_hyphen_ext('123');

DROP FUNCTION validate_hyphen_ext(json);
DROP EXTENSION "pl-jsonschema";
CREATE EXTENSION pl_jsonschema;

-- ============================================================================
-- 12. Draft-07 format annotations and union types with object properties
-- ============================================================================

CREATE FUNCTION validate_event_format(data json)
RETURNS boolean
LANGUAGE "pl/jsonschema" IMMUTABLE STRICT AS $$
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["created_at", "app"],
  "properties": {
    "created_at": {
      "type": ["null", "string"],
      "format": "date-time"
    },
    "app": {
      "type": ["null", "object"],
      "properties": {
        "id": { "type": "integer" }
      },
      "required": ["id"]
    }
  }
}
$$;

SELECT validate_event_format('{"created_at": "2025-01-15T14:00:00Z", "app": null}') AS valid_null_app,
       validate_event_format('{"created_at": null, "app": {"id": 42}}') AS valid_obj_app,
       validate_event_format('{"created_at": "2025-01-15T14:00:00Z", "app": {"id": "bad"}}') AS invalid_app_id;

DROP FUNCTION validate_event_format(json);

\set VERBOSITY default
