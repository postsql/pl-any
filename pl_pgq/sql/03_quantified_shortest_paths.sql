--
-- 03_quantified_shortest_paths.sql
-- Tests quantified path patterns (+, *, ?, {m,n}) and ANY/ALL SHORTEST & CHEAPEST
-- compiled to WITH RECURSIVE ... UNION DISTINCT ON (...) on cyclic graphs.
--

CREATE SCHEMA pgq_path_test;
SET search_path = pgq_path_test, public;

CREATE TABLE cities (
  id int PRIMARY KEY,
  name text
);

CREATE TABLE routes (
  id int PRIMARY KEY,
  src int REFERENCES cities(id),
  dst int REFERENCES cities(id),
  cost numeric
);

-- Cyclic graph:
--   1 (NYC) -> 2 (BOS) [cost 2.0]
--   2 (BOS) -> 3 (MTL) [cost 3.0]
--   3 (MTL) -> 4 (TOR) [cost 1.5]
--   1 (NYC) -> 3 (MTL) [cost 10.0]  -- 1-hop direct, but higher cost than 1->2->3 (5.0)
--   2 (BOS) -> 4 (TOR) [cost 4.5]   -- 2-hop 1->2->4 ties hop-count with 1->3->4 (both 2 hops)
--   4 (TOR) -> 1 (NYC) [cost 2.0]   -- cycle back to NYC
INSERT INTO cities VALUES
  (1, 'NYC'),
  (2, 'BOS'),
  (3, 'MTL'),
  (4, 'TOR');

INSERT INTO routes VALUES
  (101, 1, 2, 2.0),
  (102, 2, 3, 3.0),
  (103, 3, 4, 1.5),
  (104, 1, 3, 10.0),
  (105, 2, 4, 4.5),
  (106, 4, 1, 2.0);

CREATE FUNCTION transit_graph() RETURNS "PROPERTY GRAPH"
LANGUAGE "CREATE PROPERTY GRAPH" AS $$
  VERTEX TABLES (
    cities LABEL city PROPERTIES ALL COLUMNS
  )
  EDGE TABLES (
    routes
      SOURCE KEY (src) REFERENCES cities
      DESTINATION KEY (dst) REFERENCES cities
      LABEL route PROPERTIES ALL COLUMNS
  )
$$;

-- 1. Bounded quantifier {1,2} from NYC
SELECT origin, dest, hops, cost
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH (a IS city)-[r IS route]->{1,2}(b IS city) WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, count(r) AS hops, path_cost() AS cost)'
  )
 ORDER BY hops, dest, cost;

-- 2. Optional 0-or-1 hop quantifier `?` from NYC
SELECT origin, dest, hops
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH (a IS city)-[r IS route]->?(b IS city) WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, path_length() AS hops)'
  )
 ORDER BY hops, dest;

-- 3. Unbounded `+` reachability on cyclic graph (deduplicated via UNION DISTINCT ON)
SELECT origin, dest, hops
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH (a IS city)-[r IS route]->+(b IS city) WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, count(r) AS hops)'
  )
 ORDER BY dest;

-- 4. ANY SHORTEST from NYC (compiled to WITH RECURSIVE ... UNION DISTINCT ON (__src_key, __dst_key))
SELECT origin, dest, hops
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH ANY SHORTEST (a IS city)-[r IS route]->+(b IS city) WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, count(r) AS hops)'
  )
 ORDER BY dest;

-- 5. ALL SHORTEST from NYC (returns both 2-hop shortest paths to TOR: NYC->BOS->TOR and NYC->MTL->TOR)
SELECT origin, dest, hops, cost
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH ALL SHORTEST (a IS city)-[r IS route]->+(b IS city) WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, count(r) AS hops, path_cost() AS cost)'
  )
 ORDER BY dest, cost;

-- 6. ANY CHEAPEST from NYC (chooses 2-hop NYC->BOS->MTL cost 5.0 over 1-hop NYC->MTL cost 10.0)
SELECT origin, dest, hops, total_cost
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH ANY CHEAPEST (a IS city)-[r IS route]->+(b IS city) WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, count(r) AS hops, path_weight() AS total_cost)'
  )
 ORDER BY dest;

-- 7. Parenthesized quantified sub-path ((a)-[r]->(b)){1,2}
SELECT origin, dest, hops
  FROM GRAPH_TABLE(
    transit_graph(),
    'MATCH ((a IS city)-[r IS route]->(b IS city)){1,2} WHERE a.name = ''NYC'' COLUMNS (a.name AS origin, b.name AS dest, count(r) AS hops)'
  )
 ORDER BY hops, dest;

DROP SCHEMA pgq_path_test CASCADE;
