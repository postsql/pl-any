--
-- 01_create_property_graph.sql
-- Tests LANGUAGE "CREATE PROPERTY GRAPH" (and aliases), PK/FK auto-discovery,
-- label/property clauses, WebAssembly lexer activation, and all PG 19
-- create_property_graph.sql semantic validation checks.
--

CREATE EXTENSION IF NOT EXISTS plv8;
CREATE EXTENSION IF NOT EXISTS pl_pgq;

-- Verify WebAssembly character classifier module is active inside V8
SELECT (
  SELECT p.prosrc FROM pg_catalog.pg_proc p WHERE p.proname = 'pgq_compiler_bundle'
) IS NOT NULL AS bundle_installed;

SELECT pgq_wasm_active() AS wasm_active;

CREATE SCHEMA pgq_ddl_test;
SET search_path = pgq_ddl_test, public;

-- Basic tables
CREATE TABLE t1 (a int PRIMARY KEY, b text, c numeric);
CREATE TABLE t2 (i int PRIMARY KEY, j int REFERENCES t1(a), k text);
CREATE TABLE t3 (x int, y int, z text, PRIMARY KEY (x, y));
CREATE TABLE t4 (
  id int PRIMARY KEY,
  t1_a int REFERENCES t1(a),
  t3_x int,
  t3_y int,
  w int,
  FOREIGN KEY (t3_x, t3_y) REFERENCES t3(x, y)
);

-- 1. Minimal property graph using PK/FK auto-discovery and default labels/properties
CREATE FUNCTION g_minimal() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (t1, t3)
  EDGE TABLES (
    t4 SOURCE t1 DESTINATION t3
  )
$$;

SELECT (g_minimal())::jsonb - 'vertices' - 'edges' - 'property_types';
SELECT jsonb_array_length((g_minimal())::jsonb -> 'vertices') AS num_vertices,
       jsonb_array_length((g_minimal())::jsonb -> 'edges') AS num_edges;

-- 2. Language aliases ("create property graph", property_graph, sqlpgq_v8)
CREATE FUNCTION g_alias_lower() RETURNS property_graph
LANGUAGE "create property graph" AS $$
  NODE TABLES (t1)
$$;

CREATE FUNCTION g_alias_ident() RETURNS property_graph
LANGUAGE property_graph AS $$
  VERTEX TABLES (t1)
$$;

CREATE FUNCTION g_alias_v8() RETURNS "PROPERTY GRAPH"
LANGUAGE sqlpgq_v8 AS $$
  CREATE PROPERTY GRAPH g_explicit_hdr
  VERTEX TABLES (t1)
$$;

SELECT (g_alias_lower())::jsonb ->> 'graph_name' AS g1_name,
       (g_alias_ident())::jsonb ->> 'graph_name' AS g2_name,
       (g_alias_v8())::jsonb ->> 'graph_name' AS g3_name;

-- 3. Explicit KEY, SOURCE KEY / DESTINATION KEY, DEFAULT LABEL, multiple LABELs,
--    PROPERTIES ALL COLUMNS EXCEPT, custom PROPERTIES expressions, NO PROPERTIES
CREATE FUNCTION g_rich() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 KEY (a)
      DEFAULT LABEL
      LABEL l_basic PROPERTIES (a, upper(b) AS b_up)
      LABEL l_extra PROPERTIES (c AS score),
    t2 AS v_t2 KEY (i)
      PROPERTIES ALL COLUMNS EXCEPT (j),
    t3 KEY (x, y)
      NO PROPERTIES
  )
  RELATIONSHIP TABLES (
    t2 AS e_t2 KEY (i)
      SOURCE KEY (i) REFERENCES t2 (i)
      DESTINATION KEY (j) REFERENCES t1 (a)
      LABEL links_to NO PROPERTIES
  )
$$;

SELECT jsonb_pretty((g_rich())::jsonb -> 'property_types');

-- 4. Temporary table in property graph marks graph as temporary
CREATE TEMP TABLE tmp_v (id int PRIMARY KEY, val text);
CREATE FUNCTION g_temp() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (tmp_v)
$$;
SELECT (g_temp())::jsonb ->> 'is_temporary' AS is_temp;

-- 5. Negative tests matching PG 19 create_property_graph.sql

-- 5a. Syntax error: empty graph (no VERTEX TABLES or EDGE TABLES)
CREATE FUNCTION g_err_empty() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  CREATE PROPERTY GRAPH g_err_empty
$$;

-- 5b. Unlogged table in persistent property graph
CREATE UNLOGGED TABLE unlogged_v (id int PRIMARY KEY);
CREATE FUNCTION g_err_unlogged() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (unlogged_v)
$$;

-- Allowed when CREATE TEMPORARY PROPERTY GRAPH is specified
CREATE FUNCTION g_ok_temp_unlogged() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  CREATE TEMP PROPERTY GRAPH g_ok_temp_unlogged
  VERTEX TABLES (unlogged_v)
$$;
SELECT (g_ok_temp_unlogged())::jsonb ->> 'is_temporary' AS is_temp_unlogged;

-- 5c. Missing primary key without KEY clause
CREATE TABLE no_pk_v (a int, b text);
CREATE FUNCTION g_err_no_pk() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (no_pk_v)
$$;

-- 5d. Duplicate element table alias
CREATE FUNCTION g_err_dup_alias() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (t1, t2 AS t1)
$$;

-- 5e. Duplicate label on same element table
CREATE FUNCTION g_err_dup_label() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 LABEL l1 PROPERTIES (a) LABEL l1 PROPERTIES (a)
  )
$$;

-- 5f. Non-existent EXCEPT column
CREATE FUNCTION g_err_bad_except() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 PROPERTIES ALL COLUMNS EXCEPT (nonexistent_col)
  )
$$;

-- 5g. Duplicate property name within same label
CREATE FUNCTION g_err_dup_prop() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 LABEL l1 PROPERTIES (a, b AS a)
  )
$$;

-- 5h. Complex property expression without AS alias
CREATE FUNCTION g_err_no_alias() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 LABEL l1 PROPERTIES (a + 1)
  )
$$;

-- 5i. Same label on same element table (via DEFAULT LABEL + explicit LABEL) with different property counts
CREATE FUNCTION g_err_same_lbl_count() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 DEFAULT LABEL PROPERTIES (a) LABEL t1 PROPERTIES (a, b)
  )
$$;

-- 5j. Same element table defines same property with different expressions across two labels
CREATE FUNCTION g_err_diff_expr() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 LABEL l1 PROPERTIES (a AS p1) LABEL l2 PROPERTIES (a + 1 AS p1)
  )
$$;

-- 5k. Property data type mismatch across labels in graph
CREATE FUNCTION g_err_prop_type() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 LABEL l1 PROPERTIES (a AS common_prop),
    t2 LABEL l2 PROPERTIES (k AS common_prop)
  )
$$;

-- 5l. Property typmod mismatch across labels in graph
CREATE TABLE tv_char1 (id int PRIMARY KEY, code varchar(5));
CREATE TABLE tv_char2 (id int PRIMARY KEY, code varchar(10));
CREATE FUNCTION g_err_prop_typmod() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (tv_char1, tv_char2)
$$;

-- 5m. Property collation mismatch across labels in graph
CREATE TABLE tv_coll1 (id int PRIMARY KEY, name text COLLATE "C");
CREATE TABLE tv_coll2 (id int PRIMARY KEY, name text COLLATE "POSIX");
CREATE FUNCTION g_err_prop_coll() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (tv_coll1, tv_coll2)
$$;

-- 5n. Missing foreign key between edge and vertex table
CREATE FUNCTION g_err_no_fk() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (t1, t3)
  EDGE TABLES (t2 SOURCE t1 DESTINATION t3)
$$;

-- 5o. Ambiguous multiple foreign keys between edge and vertex table
CREATE TABLE multi_fk_e (
  id int PRIMARY KEY,
  s1 int REFERENCES t1(a),
  s2 int REFERENCES t1(a)
);
CREATE FUNCTION g_err_multi_fk() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (t1)
  EDGE TABLES (multi_fk_e SOURCE t1 DESTINATION t1)
$$;

-- 5p. Key column count mismatch in REFERENCES
CREATE FUNCTION g_err_fk_count() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (t1, t3)
  EDGE TABLES (
    t4 SOURCE KEY (t1_a) REFERENCES t3 (x, y)
       DESTINATION KEY (t1_a) REFERENCES t1 (a)
  )
$$;

-- 5q. Key column type mismatch in REFERENCES
CREATE FUNCTION g_err_fk_type() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (t1, t2)
  EDGE TABLES (
    t2 AS e_t2 SOURCE KEY (k) REFERENCES t1 (a)
       DESTINATION KEY (i) REFERENCES t2 (i)
  )
$$;

-- 5r. Aggregate function in property expression
CREATE FUNCTION g_err_agg_prop() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    t1 PROPERTIES (count(a) AS cnt)
  )
$$;

DROP SCHEMA pgq_ddl_test CASCADE;
