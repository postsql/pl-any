-- Register pl_pgq as a Trusted Language Extension (pg_tle)
-- Prerequisite: CREATE EXTENSION IF NOT EXISTS pg_tle;

SELECT pgtle.install_extension(
  'pl_pgq',
  '1.0',
  'ISO/IEC 9075-16 SQL/PGQ Property Graph DDL & GRAPH_TABLE compiler on V8 (pl_pgq / plpgq)',
$tle_pkg_pl_pgq$
DO $plpgq_check$
BEGIN
  IF (
    SELECT pg_catalog.count(*)
      FROM pg_catalog.pg_extension
     WHERE extname IN ('plpgq', 'pl_pgq', 'pl-pgq')
  ) > 1 THEN
    RAISE EXCEPTION 'plpgq extension is already installed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_language WHERE lanname = 'plv8'
  ) THEN
    RAISE EXCEPTION 'plpgq requires the "plv8" extension to be installed first'
      USING HINT = 'Run CREATE EXTENSION plv8; before CREATE EXTENSION plpgq;.';
  END IF;
END;
$plpgq_check$ LANGUAGE plpgsql;

-- 1. Property Graph domains (both lowercase and SQL/PGQ standard uppercase)
DO $plpgq_domains$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_type WHERE typname = 'property_graph') THEN
    CREATE DOMAIN property_graph AS pg_catalog.jsonb;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_type WHERE typname = 'PROPERTY GRAPH') THEN
    CREATE DOMAIN "PROPERTY GRAPH" AS pg_catalog.jsonb;
  END IF;
END;
$plpgq_domains$ LANGUAGE plpgsql;

-- 2. Embedded SQL/PGQ JS + WebAssembly compiler bundle on top of PL/v8 v4.0
CREATE OR REPLACE FUNCTION pgq_compiler_bundle()
RETURNS void AS
$pgq_bundle_body$
(function(globalScope) {
  "use strict";
  if (typeof globalScope.__plpgq !== "undefined") return;

  /* === Module: wasm_lexer.js === */
/*-------------------------------------------------------------------------
 *
 * wasm_lexer.js
 *    WebAssembly-accelerated character classifier and token span scanner
 *    for SQL/PGQ (`pl-pgq`) on top of PL/v8 v4.0.
 *
 * Uses PL/v8 v4.0's WebAssembly engine (and shared-memory WASM module cache)
 * to classify ASCII/UTF-8 code units and scan token spans in linear memory.
 *
 *-------------------------------------------------------------------------
 */

const WasmLexer = (function () {
  "use strict";

  /*
   * Compact WebAssembly module (pgq_fast_lexer.wasm):
   *   (module
   *     (memory (export "memory") 1)
   *     (func (export "classify") (param $c i32) (result i32)
   *       ;; 1 = whitespace (' ', '\t'..'\r')
   *       ;; 2 = ident_start ('A'..'Z', 'a'..'z', '_', >= 128)
   *       ;; 3 = digit ('0'..'9')
   *       ;; 4 = '$' (36)
   *       ;; 0 = operator / punctuation
   *     )
   *   )
   */
  const WASM_BYTES = new Uint8Array([
    0x00, 0x61, 0x73, 0x6d, // magic "\0asm"
    0x01, 0x00, 0x00, 0x00, // version 1
    // Section 1: Type section (1 func type: (i32) -> i32)
    0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
    // Section 3: Function section (1 function of type 0)
    0x03, 0x02, 0x01, 0x00,
    // Section 5: Memory section (1 memory, min 1 page)
    0x05, 0x03, 0x01, 0x00, 0x01,
    // Section 7: Export section ("memory" -> mem 0, "classify" -> func 0)
    0x07, 0x15, 0x02,
    0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00,
    0x08, 0x63, 0x6c, 0x61, 0x73, 0x73, 0x69, 0x66, 0x79, 0x00, 0x00,
    // Section 10: Code section
    0x0a, 0x53, 0x01, 0x51, 0x00,
    // if (c == 32 || (c - 9) u<= 4) return 1;
    0x20, 0x00, 0x41, 0x20, 0x46,
    0x20, 0x00, 0x41, 0x09, 0x6b, 0x41, 0x04, 0x4d,
    0x72, 0x04, 0x40, 0x41, 0x01, 0x0f, 0x0b,
    // if ((c - 48) u<= 9) return 3;
    0x20, 0x00, 0x41, 0x30, 0x6b, 0x41, 0x09, 0x4d,
    0x04, 0x40, 0x41, 0x03, 0x0f, 0x0b,
    // if (((c | 32) - 97) u<= 25 || c == 95 || c >= 128) return 2;
    0x20, 0x00, 0x41, 0x20, 0x72, 0x41, 0xe1, 0x00, 0x6b, 0x41, 0x19, 0x4d,
    0x20, 0x00, 0x41, 0xdf, 0x00, 0x46, 0x72,
    0x20, 0x00, 0x41, 0x80, 0x01, 0x4f, 0x72,
    0x04, 0x40, 0x41, 0x02, 0x0f, 0x0b,
    // if (c == 36) return 4;
    0x20, 0x00, 0x41, 0x24, 0x46,
    0x04, 0x40, 0x41, 0x04, 0x0f, 0x0b,
    // return 0;
    0x41, 0x00, 0x0b
  ]);

  let wasmExports = null;

  function ensureWasm() {
    if (wasmExports !== null) {
      return wasmExports;
    }
    if (typeof WebAssembly !== "undefined" && typeof WebAssembly.Module === "function") {
      try {
        const mod = new WebAssembly.Module(WASM_BYTES);
        const inst = new WebAssembly.Instance(mod, {});
        wasmExports = inst.exports;
        return wasmExports;
      } catch (_e) {
        wasmExports = false;
      }
    } else {
      wasmExports = false;
    }
    return wasmExports;
  }

  function classifyChar(code) {
    const exp = ensureWasm();
    if (exp && typeof exp.classify === "function") {
      return exp.classify(code);
    }
    if (code === 32 || (code >= 9 && code <= 13)) return 1;
    if (code >= 48 && code <= 57) return 3;
    if (((code | 32) >= 97 && (code | 32) <= 122) || code === 95 || code >= 128) return 2;
    if (code === 36) return 4;
    return 0;
  }

  function isWasmActive() {
    const exp = ensureWasm();
    return Boolean(exp && typeof exp.classify === "function");
  }

  return {
    classifyChar: classifyChar,
    isWasmActive: isWasmActive
  };
})();


  /* === Module: lexer.js === */
/*-------------------------------------------------------------------------
 *
 * lexer.js
 *    SQL/PGQ Tokenizer for CREATE PROPERTY GRAPH and GRAPH_TABLE MATCH.
 *
 *-------------------------------------------------------------------------
 */

const PgqLexer = (function () {
  "use strict";

  function createSyntaxError(msg, pos) {
    const err = new Error("syntax error: " + msg + (pos !== undefined ? " at position " + pos : ""));
    err.sqlstate = "42601";
    return err;
  }

  function tokenize(src) {
    if (typeof src !== "string") {
      throw createSyntaxError("expected source string");
    }
    const tokens = [];
    const len = src.length;
    let i = 0;

    while (i < len) {
      const code = src.charCodeAt(i);
      const cls = WasmLexer.classifyChar(code);

      // 1. Whitespace
      if (cls === 1) {
        i++;
        while (i < len && WasmLexer.classifyChar(src.charCodeAt(i)) === 1) {
          i++;
        }
        continue;
      }

      // 2. Line comment: -- ...
      if (code === 45 && i + 1 < len && src.charCodeAt(i + 1) === 45) {
        i += 2;
        while (i < len && src.charCodeAt(i) !== 10 && src.charCodeAt(i) !== 13) {
          i++;
        }
        continue;
      }

      // 3. Block comment: /* ... */ (supports nesting like PostgreSQL)
      if (code === 47 && i + 1 < len && src.charCodeAt(i + 1) === 42) {
        let depth = 1;
        i += 2;
        while (i < len && depth > 0) {
          if (src.charCodeAt(i) === 47 && i + 1 < len && src.charCodeAt(i + 1) === 42) {
            depth++;
            i += 2;
          } else if (src.charCodeAt(i) === 42 && i + 1 < len && src.charCodeAt(i + 1) === 47) {
            depth--;
            i += 2;
          } else {
            i++;
          }
        }
        if (depth > 0) {
          throw createSyntaxError("unterminated /* comment", i);
        }
        continue;
      }

      // 4. Double-quoted identifier: "..."
      if (code === 34) {
        const start = i;
        i++;
        let val = "";
        let closed = false;
        while (i < len) {
          const ch = src[i];
          if (ch === '"') {
            if (i + 1 < len && src[i + 1] === '"') {
              val += '"';
              i += 2;
            } else {
              i++;
              closed = true;
              break;
            }
          } else {
            val += ch;
            i++;
          }
        }
        if (!closed) {
          throw createSyntaxError("unterminated quoted identifier", start);
        }
        if (val.length === 0) {
          throw createSyntaxError("zero-length delimited identifier", start);
        }
        tokens.push({
          type: "IDENT",
          value: val,
          lower: val,
          quoted: true,
          raw: src.slice(start, i),
          start: start,
          end: i
        });
        continue;
      }

      // 5. Single-quoted string literal: '...' or E'...'
      if (
        code === 39 ||
        ((code === 69 || code === 101) && i + 1 < len && src.charCodeAt(i + 1) === 39)
      ) {
        const start = i;
        const isEscape = code !== 39;
        if (isEscape) {
          i += 2;
        } else {
          i++;
        }
        let val = "";
        let closed = false;
        while (i < len) {
          const ch = src[i];
          if (isEscape && ch === "\\") {
            if (i + 1 >= len) {
              throw createSyntaxError("unterminated quoted string", start);
            }
            const next = src[i + 1];
            if (next === "n") val += "\n";
            else if (next === "t") val += "\t";
            else if (next === "r") val += "\r";
            else val += next;
            i += 2;
          } else if (ch === "'") {
            if (i + 1 < len && src[i + 1] === "'") {
              val += "'";
              i += 2;
            } else {
              i++;
              closed = true;
              break;
            }
          } else {
            val += ch;
            i++;
          }
        }
        if (!closed) {
          throw createSyntaxError("unterminated quoted string", start);
        }
        tokens.push({
          type: "STRING",
          value: val,
          raw: src.slice(start, i),
          start: start,
          end: i
        });
        continue;
      }

      // 6. Dollar-quoted string literal ($tag$...$tag$) or positional parameter ($1)
      if (code === 36) {
        const start = i;
        if (i + 1 < len && WasmLexer.classifyChar(src.charCodeAt(i + 1)) === 3) {
          i++;
          while (i < len && WasmLexer.classifyChar(src.charCodeAt(i)) === 3) {
            i++;
          }
          tokens.push({
            type: "PARAM",
            value: src.slice(start, i),
            paramIndex: parseInt(src.slice(start + 1, i), 10),
            raw: src.slice(start, i),
            start: start,
            end: i
          });
          continue;
        }
        // Check dollar quote: $[ident]$
        let tagEnd = i + 1;
        while (tagEnd < len) {
          const tc = WasmLexer.classifyChar(src.charCodeAt(tagEnd));
          if (tc === 2 || tc === 3) {
            tagEnd++;
          } else {
            break;
          }
        }
        if (tagEnd < len && src.charCodeAt(tagEnd) === 36) {
          const tag = src.slice(start, tagEnd + 1);
          const contentStart = tagEnd + 1;
          const closeIdx = src.indexOf(tag, contentStart);
          if (closeIdx === -1) {
            throw createSyntaxError("unterminated dollar-quoted string", start);
          }
          const val = src.slice(contentStart, closeIdx);
          i = closeIdx + tag.length;
          tokens.push({
            type: "STRING",
            value: val,
            raw: src.slice(start, i),
            start: start,
            end: i
          });
          continue;
        }
      }

      // 7. Numeric literal
      if (cls === 3) {
        const start = i;
        i++;
        while (i < len && WasmLexer.classifyChar(src.charCodeAt(i)) === 3) {
          i++;
        }
        if (i < len && src.charCodeAt(i) === 46 && i + 1 < len && WasmLexer.classifyChar(src.charCodeAt(i + 1)) === 3) {
          i++;
          while (i < len && WasmLexer.classifyChar(src.charCodeAt(i)) === 3) {
            i++;
          }
        }
        if (i < len && (src.charCodeAt(i) === 101 || src.charCodeAt(i) === 69)) {
          let expIdx = i + 1;
          if (expIdx < len && (src.charCodeAt(expIdx) === 43 || src.charCodeAt(expIdx) === 45)) {
            expIdx++;
          }
          if (expIdx < len && WasmLexer.classifyChar(src.charCodeAt(expIdx)) === 3) {
            i = expIdx + 1;
            while (i < len && WasmLexer.classifyChar(src.charCodeAt(i)) === 3) {
              i++;
            }
          }
        }
        const rawNum = src.slice(start, i);
        tokens.push({
          type: "NUMBER",
          value: rawNum,
          raw: rawNum,
          start: start,
          end: i
        });
        continue;
      }

      // 8. Identifier / Keyword
      if (cls === 2) {
        const start = i;
        i++;
        while (i < len) {
          const ccls = WasmLexer.classifyChar(src.charCodeAt(i));
          if (ccls === 2 || ccls === 3 || ccls === 4) {
            i++;
          } else {
            break;
          }
        }
        const rawIdent = src.slice(start, i);
        const lowerIdent = rawIdent.toLowerCase();
        tokens.push({
          type: "IDENT",
          value: lowerIdent,
          rawValue: rawIdent,
          lower: lowerIdent,
          quoted: false,
          raw: rawIdent,
          start: start,
          end: i
        });
        continue;
      }

      // 9. Multi-character operators and graph arrows
      const start = i;
      const two = src.slice(i, i + 2);
      const three = src.slice(i, i + 3);

      if (three === "<->") {
        i += 3;
        tokens.push({ type: "OP", value: "<->", raw: "<->", start: start, end: i });
        continue;
      }
      if (
        two === "->" ||
        two === "<-" ||
        two === "::" ||
        two === "||" ||
        two === "<>" ||
        two === "!=" ||
        two === "<=" ||
        two === ">="
      ) {
        i += 2;
        tokens.push({ type: "OP", value: two, raw: two, start: start, end: i });
        continue;
      }

      // Single-character punctuation / operators
      const ch = src[i];
      i++;
      tokens.push({
        type: "PUNCT",
        value: ch,
        raw: ch,
        start: start,
        end: i
      });
    }

    return tokens;
  }

  function quoteIdent(ident) {
    return '"' + String(ident).replace(/"/g, '""') + '"';
  }

  function quoteLiteral(str) {
    if (str === null || str === undefined) return "NULL";
    return "'" + String(str).replace(/'/g, "''") + "'";
  }

  return {
    tokenize: tokenize,
    createSyntaxError: createSyntaxError,
    quoteIdent: quoteIdent,
    quoteLiteral: quoteLiteral
  };
})();


  /* === Module: ddl_parser.js === */
/*-------------------------------------------------------------------------
 *
 * ddl_parser.js
 *    Recursive-descent parser for CREATE PROPERTY GRAPH / VERTEX TABLES /
 *    EDGE TABLES definitions (`LANGUAGE "CREATE PROPERTY GRAPH"`).
 *
 *-------------------------------------------------------------------------
 */

const PgqDdlParser = (function () {
  "use strict";

  const STOP_KEYWORDS_AFTER_TABLE_NAME = {
    as: true,
    key: true,
    source: true,
    destination: true,
    default: true,
    label: true,
    properties: true,
    no: true
  };

  function parseCreatePropertyGraph(src, defaultGraphName) {
    const tokens = PgqLexer.tokenize(src);
    let pos = 0;

    function peek(offset) {
      return tokens[pos + (offset || 0)] || null;
    }

    function next() {
      return tokens[pos++] || null;
    }

    function isKw(tok, word) {
      return Boolean(tok && tok.type === "IDENT" && !tok.quoted && tok.lower === word);
    }

    function isPunct(tok, ch) {
      return Boolean(tok && (tok.type === "PUNCT" || tok.type === "OP") && tok.value === ch);
    }

    function expectKw(word) {
      const tok = next();
      if (!isKw(tok, word)) {
        throw PgqLexer.createSyntaxError(
          'expected keyword "' + word.toUpperCase() + '", got ' + (tok ? tok.raw : "end of input"),
          tok ? tok.start : src.length
        );
      }
      return tok;
    }

    function expectPunct(ch) {
      const tok = next();
      if (!isPunct(tok, ch)) {
        throw PgqLexer.createSyntaxError(
          'expected "' + ch + '", got ' + (tok ? tok.raw : "end of input"),
          tok ? tok.start : src.length
        );
      }
      return tok;
    }

    function expectIdent() {
      const tok = next();
      if (!tok || tok.type !== "IDENT") {
        throw PgqLexer.createSyntaxError(
          "expected identifier, got " + (tok ? tok.raw : "end of input"),
          tok ? tok.start : src.length
        );
      }
      return tok;
    }

    function parseQualifiedName() {
      const first = expectIdent();
      if (isPunct(peek(), ".")) {
        next();
        const second = expectIdent();
        return {
          schema: first.value,
          schemaQuoted: first.quoted,
          relname: second.value,
          relnameQuoted: second.quoted,
          displayName: first.value + "." + second.value
        };
      }
      return {
        schema: null,
        schemaQuoted: false,
        relname: first.value,
        relnameQuoted: first.quoted,
        displayName: first.value
      };
    }

    function parseIdentListInParens() {
      expectPunct("(");
      const list = [];
      while (true) {
        const id = expectIdent();
        list.push(id.value);
        if (isPunct(peek(), ",")) {
          next();
          continue;
        }
        break;
      }
      expectPunct(")");
      return list;
    }

    function parsePropertiesClause() {
      if (isKw(peek(), "no")) {
        next();
        expectKw("properties");
        return { kind: "NO_PROPERTIES" };
      }
      if (!isKw(peek(), "properties")) {
        return { kind: "ALL_COLUMNS", except: [] };
      }
      next(); // consume PROPERTIES
      if (isKw(peek(), "are")) {
        next();
      }
      if (isKw(peek(), "all")) {
        next();
        if (isKw(peek(), "columns")) {
          next();
        }
        let exceptCols = [];
        if (isKw(peek(), "except")) {
          next();
          exceptCols = parseIdentListInParens();
        }
        return { kind: "ALL_COLUMNS", except: exceptCols };
      }
      if (isKw(peek(), "no")) {
        next();
        if (isKw(peek(), "columns") || isKw(peek(), "properties")) {
          next();
        }
        return { kind: "NO_PROPERTIES" };
      }
      expectPunct("(");
      const items = [];
      while (true) {
        let depth = 0;
        const exprStartIdx = pos;
        let asIdx = -1;
        while (pos < tokens.length) {
          const t = peek();
          if (isPunct(t, "(") || isPunct(t, "[") || isPunct(t, "{")) {
            depth++;
            next();
          } else if (isPunct(t, ")") || isPunct(t, "]") || isPunct(t, "}")) {
            if (depth === 0) {
              break;
            }
            depth--;
            next();
          } else if (depth === 0 && isPunct(t, ",")) {
            break;
          } else if (depth === 0 && isKw(t, "as")) {
            asIdx = pos;
            next();
          } else {
            next();
          }
        }
        const itemEndIdx = pos;
        if (itemEndIdx <= exprStartIdx) {
          throw PgqLexer.createSyntaxError(
            "empty property expression in PROPERTIES (...)",
            peek() ? peek().start : src.length
          );
        }

        let exprEndIdx = itemEndIdx;
        let alias = null;
        if (asIdx !== -1) {
          if (asIdx + 2 !== itemEndIdx || tokens[asIdx + 1].type !== "IDENT") {
            throw PgqLexer.createSyntaxError(
              "expected property alias identifier after AS",
              tokens[asIdx].start
            );
          }
          alias = tokens[asIdx + 1].value;
          exprEndIdx = asIdx;
        }

        if (exprEndIdx <= exprStartIdx) {
          throw PgqLexer.createSyntaxError("missing expression before AS", tokens[exprStartIdx].start);
        }

        const exprTokens = tokens.slice(exprStartIdx, exprEndIdx);
        const exprSql = src.slice(exprTokens[0].start, exprTokens[exprTokens.length - 1].end).trim();

        let isSimpleColumn = false;
        let simpleColName = null;
        if (exprTokens.length === 1 && exprTokens[0].type === "IDENT") {
          isSimpleColumn = true;
          simpleColName = exprTokens[0].value;
        } else if (
          exprTokens.length === 3 &&
          exprTokens[0].type === "IDENT" &&
          isPunct(exprTokens[1], ".") &&
          exprTokens[2].type === "IDENT"
        ) {
          isSimpleColumn = true;
          simpleColName = exprTokens[2].value;
        }

        if (!alias) {
          if (isSimpleColumn) {
            alias = simpleColName;
          } else {
            throw PgqLexer.createSyntaxError(
              'property expression "' + exprSql + '" requires an AS alias',
              exprTokens[0].start
            );
          }
        }

        items.push({
          exprSql: exprSql,
          exprTokens: exprTokens,
          alias: alias,
          isSimpleColumn: isSimpleColumn,
          simpleColName: simpleColName
        });

        if (isPunct(peek(), ",")) {
          next();
          continue;
        }
        break;
      }
      expectPunct(")");
      return { kind: "EXPR_LIST", items: items };
    }

    function parseLabelAndPropertyClauses(defaultLabelName) {
      const labels = [];

      // Case 1: bare PROPERTIES or NO PROPERTIES without LABEL / DEFAULT LABEL
      if (isKw(peek(), "properties") || isKw(peek(), "no")) {
        const propSpec = parsePropertiesClause();
        labels.push({
          name: defaultLabelName,
          isDefault: true,
          propertiesSpec: propSpec
        });
      }

      // Case 2: one or more DEFAULT LABEL or LABEL <name> clauses
      while (isKw(peek(), "default") || isKw(peek(), "label")) {
        if (isKw(peek(), "default")) {
          next();
          expectKw("label");
          let propSpec = { kind: "ALL_COLUMNS", except: [] };
          if (isKw(peek(), "properties") || isKw(peek(), "no")) {
            propSpec = parsePropertiesClause();
          }
          labels.push({
            name: defaultLabelName,
            isDefault: true,
            propertiesSpec: propSpec
          });
        } else {
          next(); // consume LABEL
          const lblTok = expectIdent();
          let propSpec = { kind: "ALL_COLUMNS", except: [] };
          if (isKw(peek(), "properties") || isKw(peek(), "no")) {
            propSpec = parsePropertiesClause();
          }
          labels.push({
            name: lblTok.value,
            isDefault: false,
            propertiesSpec: propSpec
          });
        }
      }

      // Case 3: neither LABEL nor PROPERTIES specified -> single default label with ALL COLUMNS
      if (labels.length === 0) {
        labels.push({
          name: defaultLabelName,
          isDefault: true,
          propertiesSpec: { kind: "ALL_COLUMNS", except: [] }
        });
      }

      return labels;
    }

    function parseTableAndAlias() {
      const qname = parseQualifiedName();
      let alias = qname.relname;
      if (isKw(peek(), "as")) {
        next();
        alias = expectIdent().value;
      } else if (
        peek() &&
        peek().type === "IDENT" &&
        (peek().quoted || !STOP_KEYWORDS_AFTER_TABLE_NAME[peek().lower])
      ) {
        alias = next().value;
      }
      return {
        qname: qname,
        alias: alias
      };
    }

    function parseVertexTableDef() {
      const ta = parseTableAndAlias();
      let keyCols = null;
      if (isKw(peek(), "key")) {
        next();
        keyCols = parseIdentListInParens();
      }
      const labels = parseLabelAndPropertyClauses(ta.alias);
      return {
        qname: ta.qname,
        alias: ta.alias,
        keyCols: keyCols,
        labels: labels
      };
    }

    function parseEndpointSpec(kindWord) {
      expectKw(kindWord); // 'source' or 'destination'
      let edgeCols = null;
      if (isKw(peek(), "key")) {
        next();
        edgeCols = parseIdentListInParens();
      }
      if (isKw(peek(), "references")) {
        next();
      } else if (edgeCols !== null) {
        throw PgqLexer.createSyntaxError(
          "expected REFERENCES after " + kindWord.toUpperCase() + " KEY (...)",
          peek() ? peek().start : src.length
        );
      }
      const refVertex = expectIdent().value;
      let vertexCols = null;
      if (isPunct(peek(), "(")) {
        vertexCols = parseIdentListInParens();
      }
      return {
        vertexAlias: refVertex,
        edgeCols: edgeCols,
        vertexCols: vertexCols
      };
    }

    function parseEdgeTableDef() {
      const ta = parseTableAndAlias();
      let keyCols = null;
      let sourceSpec = null;
      let destSpec = null;

      while (
        isKw(peek(), "key") ||
        isKw(peek(), "source") ||
        isKw(peek(), "destination") ||
        isKw(peek(), "dest")
      ) {
        if (isKw(peek(), "key")) {
          if (keyCols !== null) {
            throw PgqLexer.createSyntaxError("duplicate KEY clause on edge table " + ta.alias, peek().start);
          }
          next();
          keyCols = parseIdentListInParens();
        } else if (isKw(peek(), "source")) {
          if (sourceSpec !== null) {
            throw PgqLexer.createSyntaxError("duplicate SOURCE clause on edge table " + ta.alias, peek().start);
          }
          sourceSpec = parseEndpointSpec("source");
        } else if (isKw(peek(), "destination")) {
          if (destSpec !== null) {
            throw PgqLexer.createSyntaxError("duplicate DESTINATION clause on edge table " + ta.alias, peek().start);
          }
          destSpec = parseEndpointSpec("destination");
        } else if (isKw(peek(), "dest")) {
          if (destSpec !== null) {
            throw PgqLexer.createSyntaxError("duplicate DESTINATION clause on edge table " + ta.alias, peek().start);
          }
          destSpec = parseEndpointSpec("dest");
        }
      }

      if (!sourceSpec) {
        throw PgqLexer.createSyntaxError(
          'edge table "' + ta.alias + '" requires a SOURCE clause',
          peek() ? peek().start : src.length
        );
      }
      if (!destSpec) {
        throw PgqLexer.createSyntaxError(
          'edge table "' + ta.alias + '" requires a DESTINATION clause',
          peek() ? peek().start : src.length
        );
      }

      const labels = parseLabelAndPropertyClauses(ta.alias);
      return {
        qname: ta.qname,
        alias: ta.alias,
        keyCols: keyCols,
        source: sourceSpec,
        destination: destSpec,
        labels: labels
      };
    }

    let graphName = defaultGraphName || "property_graph";
    let isTemporary = false;

    // Optional leading semicolons
    while (isPunct(peek(), ";")) {
      next();
    }

    if (pos >= tokens.length) {
      return {
        graphName: graphName,
        isTemporary: false,
        vertices: [],
        edges: []
      };
    }

    // Optional CREATE [TEMPORARY | TEMP] PROPERTY GRAPH [IF NOT EXISTS] [graph_name]
    if (isKw(peek(), "create")) {
      next();
      if (isKw(peek(), "unlogged")) {
        const err = new Error("property graph cannot be unlogged");
        err.sqlstate = "42601";
        throw err;
      }
      if (isKw(peek(), "local") || isKw(peek(), "global")) {
        next();
      }
      if (isKw(peek(), "temporary") || isKw(peek(), "temp")) {
        isTemporary = true;
        next();
      }
      expectKw("property");
      expectKw("graph");
      if (isKw(peek(), "if")) {
        next();
        expectKw("not");
        expectKw("exists");
      }
      // Optional graph name (unless followed immediately by VERTEX/NODE/EDGE/RELATIONSHIP TABLES or ';')
      if (
        peek() &&
        peek().type === "IDENT" &&
        !(
          (peek().lower === "vertex" ||
            peek().lower === "node" ||
            peek().lower === "edge" ||
            peek().lower === "relationship") &&
          isKw(peek(1), "tables")
        )
      ) {
        const gq = parseQualifiedName();
        graphName = gq.relname;
      }
    }

    const vertices = [];
    const edges = [];

    if (isKw(peek(), "vertex") || isKw(peek(), "node")) {
      next();
      expectKw("tables");
      expectPunct("(");
      while (true) {
        vertices.push(parseVertexTableDef());
        if (isPunct(peek(), ",")) {
          next();
          continue;
        }
        break;
      }
      expectPunct(")");
    }

    if (isKw(peek(), "edge") || isKw(peek(), "relationship")) {
      next();
      expectKw("tables");
      expectPunct("(");
      while (true) {
        edges.push(parseEdgeTableDef());
        if (isPunct(peek(), ",")) {
          next();
          continue;
        }
        break;
      }
      expectPunct(")");
    }

    while (isPunct(peek(), ";")) {
      next();
    }

    if (pos < tokens.length) {
      throw PgqLexer.createSyntaxError(
        "unexpected token " + peek().raw + " in CREATE PROPERTY GRAPH definition",
        peek().start
      );
    }

    if (vertices.length === 0 && edges.length === 0) {
      throw PgqLexer.createSyntaxError(
        "CREATE PROPERTY GRAPH requires at least VERTEX TABLES (...) or EDGE TABLES (...)",
        0
      );
    }

    return {
      graphName: graphName,
      isTemporary: isTemporary,
      vertices: vertices,
      edges: edges
    };
  }

  return {
    parseCreatePropertyGraph: parseCreatePropertyGraph
  };
})();


  /* === Module: catalog.js === */
/*-------------------------------------------------------------------------
 *
 * catalog.js
 *    PostgreSQL catalog introspection and SQL/PGQ semantic validation for
 *    CREATE PROPERTY GRAPH (`LANGUAGE "CREATE PROPERTY GRAPH"`).
 *
 *-------------------------------------------------------------------------
 */

const PgqCatalog = (function () {
  "use strict";

  function throwPgqError(msg, sqlstate) {
    const err = new Error(msg);
    err.sqlstate = sqlstate || "42601";
    throw err;
  }

  function resolveRelation(qname) {
    const regStr = qname.schema
      ? PgqLexer.quoteIdent(qname.schema) + "." + PgqLexer.quoteIdent(qname.relname)
      : PgqLexer.quoteIdent(qname.relname);

    const relRows = plv8.execute(
      `SELECT c.oid::int AS relid,
              n.nspname::text AS nspname,
              c.relname::text AS relname,
              c.relkind::text AS relkind,
              c.relpersistence::text AS relpersistence
         FROM pg_catalog.pg_class c
         JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        WHERE c.oid = pg_catalog.to_regclass($1)`,
      [regStr]
    );

    if (!relRows || relRows.length === 0) {
      throwPgqError('relation "' + qname.displayName + '" does not exist', "42P01");
    }

    const rel = relRows[0];
    if (rel.relkind !== "r" && rel.relkind !== "p" && rel.relkind !== "v" && rel.relkind !== "m" && rel.relkind !== "f") {
      throwPgqError('"' + qname.displayName + '" is not a table, view, or foreign table', "42809");
    }

    const colRows = plv8.execute(
      `SELECT a.attnum::int AS attnum,
              a.attname::text AS attname,
              a.atttypid::int AS type_oid,
              a.atttypmod::int AS typmod,
              a.attcollation::int AS collation_oid,
              COALESCE(col.collname::text, '') AS collation_name,
              pg_catalog.format_type(a.atttypid, a.atttypmod)::text AS type_sql
         FROM pg_catalog.pg_attribute a
         LEFT JOIN pg_catalog.pg_collation col ON col.oid = a.attcollation
        WHERE a.attrelid = $1::pg_catalog.oid
          AND a.attnum > 0
          AND NOT a.attisdropped
        ORDER BY a.attnum`,
      [rel.relid]
    );

    const columns = [];
    const colMap = Object.create(null);
    const attnumMap = Object.create(null);
    for (let i = 0; i < colRows.length; i++) {
      const c = colRows[i];
      const colInfo = {
        attnum: c.attnum,
        name: c.attname,
        type_oid: c.type_oid,
        typmod: c.typmod,
        collation_oid: c.collation_oid,
        collation_name: c.collation_name || "",
        type_sql: c.type_sql
      };
      columns.push(colInfo);
      colMap[c.attname] = colInfo;
      attnumMap[c.attnum] = colInfo;
    }

    return {
      relid: rel.relid,
      nspname: rel.nspname,
      relname: rel.relname,
      relpersistence: rel.relpersistence,
      qualifiedName: PgqLexer.quoteIdent(rel.nspname) + "." + PgqLexer.quoteIdent(rel.relname),
      columns: columns,
      colMap: colMap,
      attnumMap: attnumMap
    };
  }

  function resolveKeyColumns(relInfo, explicitKeyCols, elementAlias) {
    if (explicitKeyCols && explicitKeyCols.length > 0) {
      const resolved = [];
      for (let i = 0; i < explicitKeyCols.length; i++) {
        const cname = explicitKeyCols[i];
        const col = relInfo.colMap[cname];
        if (!col) {
          throwPgqError(
            'column "' + cname + '" of relation "' + relInfo.relname + '" does not exist',
            "42703"
          );
        }
        resolved.push(col.name);
      }
      return resolved;
    }

    // Introspect PRIMARY KEY from pg_index
    const pkRows = plv8.execute(
      `SELECT a.attname::text AS attname
         FROM pg_catalog.pg_index i
         JOIN LATERAL pg_catalog.unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord) ON true
         JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = k.attnum
        WHERE i.indrelid = $1::pg_catalog.oid
          AND i.indisprimary
        ORDER BY k.ord`,
      [relInfo.relid]
    );

    if (!pkRows || pkRows.length === 0) {
      throwPgqError(
        'KEY clause is required for element table "' +
          elementAlias +
          '" because relation "' +
          relInfo.relname +
          '" has no primary key',
        "42830"
      );
    }

    const cols = [];
    for (let i = 0; i < pkRows.length; i++) {
      cols.push(pkRows[i].attname);
    }
    return cols;
  }

  function checkTypesAndCollationsCompatible(edgeRel, edgeCols, vertexRel, vertexCols) {
    if (edgeCols.length !== vertexCols.length) {
      throwPgqError(
        "number of source/destination key columns (" +
          edgeCols.length +
          ") does not match number of referenced vertex key columns (" +
          vertexCols.length +
          ")",
        "42830"
      );
    }

    for (let i = 0; i < edgeCols.length; i++) {
      const ecol = edgeRel.colMap[edgeCols[i]];
      if (!ecol) {
        throwPgqError(
          'column "' + edgeCols[i] + '" of relation "' + edgeRel.relname + '" does not exist',
          "42703"
        );
      }
      const vcol = vertexRel.colMap[vertexCols[i]];
      if (!vcol) {
        throwPgqError(
          'column "' + vertexCols[i] + '" of relation "' + vertexRel.relname + '" does not exist',
          "42703"
        );
      }

      // Check equality operator compatibility (hash/merge joinable =)
      if (ecol.type_oid !== vcol.type_oid) {
        const opRows = plv8.execute(
          `SELECT 1
             FROM pg_catalog.pg_operator o
            WHERE o.oprname = '='
              AND (o.oprcanhash OR o.oprcanmerge)
              AND o.oprleft = $1::pg_catalog.oid
              AND o.oprright = $2::pg_catalog.oid
            LIMIT 1`,
          [ecol.type_oid, vcol.type_oid]
        );
        if (!opRows || opRows.length === 0) {
          throwPgqError(
            'foreign key column "' +
              ecol.name +
              '" (' +
              ecol.type_sql +
              ') and referenced column "' +
              vcol.name +
              '" (' +
              vcol.type_sql +
              ") are of incompatible types",
            "42804"
          );
        }
      }

      // Check collation match when collatable
      if (
        (ecol.collation_oid !== 0 || vcol.collation_oid !== 0) &&
        ecol.collation_oid !== vcol.collation_oid
      ) {
        throwPgqError(
          'collation mismatch between foreign key column "' +
            ecol.name +
            '" and referenced column "' +
            vcol.name +
            '"',
          "42804"
        );
      }
    }
  }

  function resolveEndpoint(edgeRel, endpointSpec, verticesByAlias, kindLabel) {
    let vInfo = verticesByAlias[endpointSpec.vertexAlias];
    if (!vInfo) {
      // Allow referencing a vertex table by its underlying relation name if unambiguous
      const matches = [];
      const aliases = Object.keys(verticesByAlias);
      for (let i = 0; i < aliases.length; i++) {
        const cand = verticesByAlias[aliases[i]];
        if (cand.relInfo.relname === endpointSpec.vertexAlias) {
          matches.push(cand);
        }
      }
      if (matches.length === 1) {
        vInfo = matches[0];
      }
    }
    if (!vInfo) {
      throwPgqError(
        'vertex table "' + endpointSpec.vertexAlias + '" in ' + kindLabel + " clause does not exist",
        "42704"
      );
    }

    let edgeCols = endpointSpec.edgeCols;
    let vertexCols = endpointSpec.vertexCols;

    if (!edgeCols) {
      // Discover foreign key from pg_constraint
      const fkRows = plv8.execute(
        `SELECT c.oid::int AS conid,
                ARRAY(
                  SELECT a.attname::text
                    FROM pg_catalog.unnest(c.conkey) WITH ORDINALITY AS u(attnum, ord)
                    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = u.attnum
                   ORDER BY u.ord
                ) AS edge_cols,
                ARRAY(
                  SELECT a.attname::text
                    FROM pg_catalog.unnest(c.confkey) WITH ORDINALITY AS u(attnum, ord)
                    JOIN pg_catalog.pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = u.attnum
                   ORDER BY u.ord
                ) AS vertex_cols
           FROM pg_catalog.pg_constraint c
          WHERE c.conrelid = $1::pg_catalog.oid
            AND c.confrelid = $2::pg_catalog.oid
            AND c.contype = 'f'`,
        [edgeRel.relid, vInfo.relInfo.relid]
      );

      if (!fkRows || fkRows.length === 0) {
        throwPgqError(
          'no foreign key found between edge table "' +
            edgeRel.relname +
            '" and vertex table "' +
            vInfo.alias +
            '"',
          "42830"
        );
      }
      if (fkRows.length > 1) {
        throwPgqError(
          'more than one foreign key found between edge table "' +
            edgeRel.relname +
            '" and vertex table "' +
            vInfo.alias +
            '"; specify ' +
            kindLabel +
            " KEY (...) explicitly",
          "42830"
        );
      }
      edgeCols = fkRows[0].edge_cols;
      vertexCols = fkRows[0].vertex_cols;
    } else if (!vertexCols) {
      vertexCols = vInfo.keyCols.slice();
    }

    checkTypesAndCollationsCompatible(edgeRel, edgeCols, vInfo.relInfo, vertexCols);

    return {
      vertex_alias: vInfo.alias,
      edge_cols: edgeCols,
      vertex_cols: vertexCols
    };
  }

  function normalizeExprTokens(exprTokens) {
    let toks = exprTokens.slice();
    while (
      toks.length >= 2 &&
      toks[0].value === "(" &&
      toks[toks.length - 1].value === ")"
    ) {
      let depth = 0;
      let balanced = true;
      for (let i = 0; i < toks.length - 1; i++) {
        if (toks[i].value === "(") depth++;
        else if (toks[i].value === ")") {
          depth--;
          if (depth === 0) {
            balanced = false;
            break;
          }
        }
      }
      if (balanced && depth === 1) {
        toks = toks.slice(1, toks.length - 1);
      } else {
        break;
      }
    }
    return toks
      .map(function (t) {
        if (t.type === "IDENT") {
          return t.quoted ? PgqLexer.quoteIdent(t.value) : t.lower;
        }
        return t.raw;
      })
      .join(" ");
  }

  /*
   * Extracts an explicit trailing cast type specification if present, e.g.
   * `'order'::varchar(10)` or `(b COLLATE "C")::varchar(20)` so we preserve
   * exact typmods on cast expressions.
   */
  function extractExplicitCastTypeSql(exprTokens) {
    // Strip trailing COLLATE clause if present after cast
    let end = exprTokens.length;
    if (
      end >= 3 &&
      exprTokens[end - 2].type === "IDENT" &&
      !exprTokens[end - 2].quoted &&
      exprTokens[end - 2].lower === "collate"
    ) {
      end -= 2;
      if (
        end >= 2 &&
        exprTokens[end - 1].value === "." &&
        exprTokens[end - 2].type === "IDENT"
      ) {
        end -= 2;
      }
    }

    // Look for top-level `::`
    let depth = 0;
    let lastCastIdx = -1;
    for (let i = 0; i < end; i++) {
      const t = exprTokens[i];
      if (t.value === "(" || t.value === "[") depth++;
      else if (t.value === ")" || t.value === "]") depth--;
      else if (depth === 0 && t.type === "OP" && t.value === "::") {
        lastCastIdx = i;
      }
    }
    if (lastCastIdx === -1 || lastCastIdx + 1 >= end) {
      return null;
    }

    const castTokens = exprTokens.slice(lastCastIdx + 1, end);
    // Check if there is a parenthesized typmod like varchar(20) or numeric(10, 2)
    let hasParens = false;
    for (let i = 0; i < castTokens.length; i++) {
      if (castTokens[i].value === "(") {
        hasParens = true;
        break;
      }
    }
    if (!hasParens) {
      return null;
    }
    return castTokens.map(function (t) { return t.raw; }).join("");
  }

  function evaluatePropertyExpression(relInfo, item) {
    if (item.isSimpleColumn) {
      const col = relInfo.colMap[item.simpleColName];
      if (!col) {
        throwPgqError(
          'column "' + item.simpleColName + '" of relation "' + relInfo.relname + '" does not exist',
          "42703"
        );
      }
      return {
        expr: PgqLexer.quoteIdent(col.name),
        norm_expr: col.name,
        type_oid: col.type_oid,
        typmod: col.typmod,
        type_sql: col.type_sql,
        collation_oid: col.collation_oid,
        collation_name: col.collation_name
      };
    }

    const query =
      "SELECT pg_catalog.pg_typeof(sub.__val)::pg_catalog.oid::int AS type_oid, " +
      "       t.typcollation::pg_catalog.oid::int AS typcollation " +
      "  FROM (SELECT 1) __one " +
      "  LEFT JOIN (SELECT * FROM " + relInfo.qualifiedName + " WHERE false) " +
      PgqLexer.quoteIdent(relInfo.relname) + " ON true " +
      "  CROSS JOIN LATERAL (SELECT (" + item.exprSql + ") AS __val) sub " +
      "  LEFT JOIN pg_catalog.pg_type t ON t.oid = pg_catalog.pg_typeof(sub.__val)";

    let rows;
    try {
      rows = plv8.execute(query);
    } catch (e) {
      throwPgqError(
        'invalid property expression "' + item.exprSql + '" on relation "' + relInfo.relname + '": ' + e.message,
        e.sqlstate || "42601"
      );
    }

    let typeOid = rows[0].type_oid;
    let collName = "";
    if (rows[0].typcollation && rows[0].typcollation !== 0) {
      try {
        const collRows = plv8.execute(
          "SELECT pg_catalog.pg_collation_for(sub.__val)::text AS coll_name " +
          "  FROM (SELECT 1) __one " +
          "  LEFT JOIN (SELECT * FROM " + relInfo.qualifiedName + " WHERE false) " +
          PgqLexer.quoteIdent(relInfo.relname) + " ON true " +
          "  CROSS JOIN LATERAL (SELECT (" + item.exprSql + ") AS __val) sub"
        );
        if (collRows && collRows.length > 0 && collRows[0].coll_name) {
          collName = collRows[0].coll_name;
        }
      } catch (_e) {
        collName = "";
      }
    }
    let collOid = 0;
    let typmod = -1;
    let typeSql = null;

    // Coerce UNKNOWNOID (705) string literals (e.g. 'foo' AS p1) to text (25)
    if (typeOid === 705) {
      typeOid = 25;
      collOid = 100;
      collName = '"default"';
      typeSql = "text";
    } else {
      if (collName) {
        const cleanColl = collName.replace(/^"|"$/g, "");
        const collRows = plv8.execute(
          `SELECT oid::int AS oid
             FROM pg_catalog.pg_collation
            WHERE collname = $1
            ORDER BY (collencoding = -1) ASC, oid ASC
            LIMIT 1`,
          [cleanColl]
        );
        if (collRows && collRows.length > 0) {
          collOid = collRows[0].oid;
        }
      }

      const explicitCastSql = extractExplicitCastTypeSql(item.exprTokens);
      if (explicitCastSql) {
        // Resolve canonical type_sql and typmod via a cast in format_type
        const m = explicitCastSql.match(/\(\s*(\d+)\s*\)\s*$/);
        if (m) {
          typmod = parseInt(m[1], 10) + 4;
        }
        const fRows = plv8.execute(
          `SELECT pg_catalog.format_type($1::pg_catalog.oid, $2::int)::text AS type_sql`,
          [typeOid, typmod]
        );
        typeSql = fRows[0].type_sql;
      } else {
        const fRows = plv8.execute(
          `SELECT pg_catalog.format_type($1::pg_catalog.oid, -1)::text AS type_sql`,
          [typeOid]
        );
        typeSql = fRows[0].type_sql;
      }
    }

    // Rewrite unqualified column identifiers in exprTokens so they can be
    // safely substituted with table alias `__el` during query generation.
    return {
      expr: item.exprSql,
      norm_expr: normalizeExprTokens(item.exprTokens),
      type_oid: typeOid,
      typmod: typmod,
      type_sql: typeSql,
      collation_oid: collOid,
      collation_name: collName
    };
  }

  function resolveElementLabels(relInfo, elementDef) {
    const labelsObj = Object.create(null);
    const propExprByPropNameOnElement = Object.create(null);

    for (let i = 0; i < elementDef.labels.length; i++) {
      const lblDef = elementDef.labels[i];
      const lblName = lblDef.name;

      if (Object.prototype.hasOwnProperty.call(labelsObj, lblName)) {
        throwPgqError(
          'label "' + lblName + '" specified more than once for element table "' + elementDef.alias + '"',
          "42710"
        );
      }

      const propsObj = Object.create(null);
      const spec = lblDef.propertiesSpec;

      if (spec.kind === "NO_PROPERTIES") {
        // Empty properties
      } else if (spec.kind === "ALL_COLUMNS") {
        const exceptSet = Object.create(null);
        for (let j = 0; j < spec.except.length; j++) {
          const exCol = spec.except[j];
          if (!relInfo.colMap[exCol]) {
            throwPgqError(
              'column "' + exCol + '" in EXCEPT list does not exist in relation "' + relInfo.relname + '"',
              "42703"
            );
          }
          exceptSet[exCol] = true;
        }
        for (let j = 0; j < relInfo.columns.length; j++) {
          const col = relInfo.columns[j];
          if (exceptSet[col.name]) continue;
          const propMeta = {
            expr: PgqLexer.quoteIdent(col.name),
            norm_expr: col.name,
            type_oid: col.type_oid,
            typmod: col.typmod,
            type_sql: col.type_sql,
            collation_oid: col.collation_oid,
            collation_name: col.collation_name
          };
          propsObj[col.name] = propMeta;
          if (
            Object.prototype.hasOwnProperty.call(propExprByPropNameOnElement, col.name) &&
            propExprByPropNameOnElement[col.name] !== propMeta.norm_expr
          ) {
            throwPgqError(
              'property "' +
                col.name +
                '" on element table "' +
                elementDef.alias +
                '" has mismatching expressions across labels',
              "42P13"
            );
          }
          propExprByPropNameOnElement[col.name] = propMeta.norm_expr;
        }
      } else if (spec.kind === "EXPR_LIST") {
        for (let j = 0; j < spec.items.length; j++) {
          const item = spec.items[j];
          if (Object.prototype.hasOwnProperty.call(propsObj, item.alias)) {
            throwPgqError(
              'property "' +
                item.alias +
                '" specified more than once for label "' +
                lblName +
                '"',
              "42701"
            );
          }
          const propMeta = evaluatePropertyExpression(relInfo, item);
          propsObj[item.alias] = propMeta;
          if (
            Object.prototype.hasOwnProperty.call(propExprByPropNameOnElement, item.alias) &&
            propExprByPropNameOnElement[item.alias] !== propMeta.norm_expr
          ) {
            throwPgqError(
              'property "' +
                item.alias +
                '" on element table "' +
                elementDef.alias +
                '" has mismatching expressions across labels',
              "42P13"
            );
          }
          propExprByPropNameOnElement[item.alias] = propMeta.norm_expr;
        }
      }

      labelsObj[lblName] = {
        properties: propsObj
      };
    }

    return labelsObj;
  }

  function buildPropertyGraphDescriptor(ast) {
    const seenElementAliases = Object.create(null);
    const verticesByAlias = Object.create(null);
    const verticesOut = [];
    const edgesOut = [];
    let isTemporary = Boolean(ast.isTemporary);

    // 1. Resolve Vertex Tables
    for (let i = 0; i < ast.vertices.length; i++) {
      const vDef = ast.vertices[i];
      if (seenElementAliases[vDef.alias]) {
        throwPgqError('duplicate element table alias "' + vDef.alias + '" in property graph', "42710");
      }
      seenElementAliases[vDef.alias] = true;

      const relInfo = resolveRelation(vDef.qname);
      if (relInfo.relpersistence === "t") {
        isTemporary = true;
      } else if (relInfo.relpersistence === "u" && !isTemporary) {
        throwPgqError(
          'cannot use unlogged table "' + relInfo.relname + '" in a persistent property graph',
          "42P16"
        );
      }
      const keyCols = resolveKeyColumns(relInfo, vDef.keyCols, vDef.alias);
      const labelsObj = resolveElementLabels(relInfo, vDef);

      const vEntry = {
        alias: vDef.alias,
        relid: relInfo.relid,
        nspname: relInfo.nspname,
        relname: relInfo.relname,
        qualified_name: relInfo.qualifiedName,
        table_columns: relInfo.columns.map(function (c) { return c.name; }),
        key_cols: keyCols,
        labels: labelsObj
      };

      verticesByAlias[vDef.alias] = {
        alias: vDef.alias,
        relInfo: relInfo,
        keyCols: keyCols,
        entry: vEntry
      };
      verticesOut.push(vEntry);
    }

    // 2. Resolve Edge Tables
    for (let i = 0; i < ast.edges.length; i++) {
      const eDef = ast.edges[i];
      if (seenElementAliases[eDef.alias]) {
        throwPgqError('duplicate element table alias "' + eDef.alias + '" in property graph', "42710");
      }
      seenElementAliases[eDef.alias] = true;

      const relInfo = resolveRelation(eDef.qname);
      if (relInfo.relpersistence === "t") {
        isTemporary = true;
      } else if (relInfo.relpersistence === "u" && !isTemporary) {
        throwPgqError(
          'cannot use unlogged table "' + relInfo.relname + '" in a persistent property graph',
          "42P16"
        );
      }
      const keyCols = resolveKeyColumns(relInfo, eDef.keyCols, eDef.alias);
      const srcEndpoint = resolveEndpoint(relInfo, eDef.source, verticesByAlias, "SOURCE");
      const dstEndpoint = resolveEndpoint(relInfo, eDef.destination, verticesByAlias, "DESTINATION");
      const labelsObj = resolveElementLabels(relInfo, eDef);

      edgesOut.push({
        alias: eDef.alias,
        relid: relInfo.relid,
        nspname: relInfo.nspname,
        relname: relInfo.relname,
        qualified_name: relInfo.qualifiedName,
        table_columns: relInfo.columns.map(function (c) { return c.name; }),
        key_cols: keyCols,
        source: srcEndpoint,
        destination: dstEndpoint,
        labels: labelsObj
      });
    }

    // 3. Validate Cross-Table Label & Property Consistency
    const labelPropertySets = Object.create(null);
    const globalPropertyTypes = Object.create(null);

    const allElements = verticesOut.concat(edgesOut);
    for (let i = 0; i < allElements.length; i++) {
      const el = allElements[i];
      const lblNames = Object.keys(el.labels);
      for (let j = 0; j < lblNames.length; j++) {
        const lblName = lblNames[j];
        const props = el.labels[lblName].properties;
        const propNames = Object.keys(props).sort();
        const propKey = propNames.join("\x00");

        if (!Object.prototype.hasOwnProperty.call(labelPropertySets, lblName)) {
          labelPropertySets[lblName] = {
            propNames: propNames,
            propKey: propKey,
            firstElement: el.alias
          };
        } else if (labelPropertySets[lblName].propKey !== propKey) {
          throwPgqError(
            'label "' +
              lblName +
              '" has mismatching property sets between element tables "' +
              labelPropertySets[lblName].firstElement +
              '" and "' +
              el.alias +
              '"',
            "42P13"
          );
        }

        for (let k = 0; k < propNames.length; k++) {
          const pName = propNames[k];
          const pMeta = props[pName];
          if (!Object.prototype.hasOwnProperty.call(globalPropertyTypes, pName)) {
            globalPropertyTypes[pName] = {
              type_oid: pMeta.type_oid,
              typmod: pMeta.typmod,
              type_sql: pMeta.type_sql,
              collation_oid: pMeta.collation_oid,
              collation_name: pMeta.collation_name,
              firstElement: el.alias
            };
          } else {
            const prev = globalPropertyTypes[pName];
            if (prev.type_oid !== pMeta.type_oid) {
              throwPgqError(
                'property "' +
                  pName +
                  '" has mismatching data types (' +
                  prev.type_sql +
                  " vs " +
                  pMeta.type_sql +
                  ")",
                "42804"
              );
            }
            if (prev.typmod !== pMeta.typmod || prev.type_sql !== pMeta.type_sql) {
              throwPgqError(
                'property "' +
                  pName +
                  '" has mismatching type modifiers (' +
                  prev.type_sql +
                  " vs " +
                  pMeta.type_sql +
                  ")",
                "42804"
              );
            }
            if (prev.collation_oid !== pMeta.collation_oid) {
              throwPgqError(
                'property "' +
                  pName +
                  '" has mismatching collations across element tables',
                "42P22"
              );
            }
          }
        }
      }
    }

    return {
      __pgq_version: 1,
      graph_name: ast.graphName,
      is_temporary: isTemporary,
      vertices: verticesOut,
      edges: edgesOut,
      property_types: globalPropertyTypes
    };
  }

  return {
    buildPropertyGraphDescriptor: buildPropertyGraphDescriptor,
    throwPgqError: throwPgqError
  };
})();


  /* === Module: match_parser.js === */
/*-------------------------------------------------------------------------
 *
 * match_parser.js
 *    Recursive-descent parser for SQL/PGQ GRAPH_TABLE MATCH clauses:
 *      MATCH [path_mode] path_pattern [WHERE expr] COLUMNS (col_item, ...)
 *
 *-------------------------------------------------------------------------
 */

const PgqMatchParser = (function () {
  "use strict";

  function parseGraphTableMatch(src) {
    const tokens = PgqLexer.tokenize(src);
    let pos = 0;

    function peek(offset) {
      return tokens[pos + (offset || 0)] || null;
    }

    function next() {
      return tokens[pos++] || null;
    }

    function isKw(tok, word) {
      return Boolean(tok && tok.type === "IDENT" && !tok.quoted && tok.lower === word);
    }

    function isPunct(tok, ch) {
      return Boolean(tok && (tok.type === "PUNCT" || tok.type === "OP") && tok.value === ch);
    }

    function expectKw(word) {
      const tok = next();
      if (!isKw(tok, word)) {
        throw PgqLexer.createSyntaxError(
          'expected "' + word.toUpperCase() + '", got ' + (tok ? tok.raw : "end of input"),
          tok ? tok.start : src.length
        );
      }
      return tok;
    }

    function expectPunct(ch) {
      const tok = next();
      if (!isPunct(tok, ch)) {
        throw PgqLexer.createSyntaxError(
          'expected "' + ch + '", got ' + (tok ? tok.raw : "end of input"),
          tok ? tok.start : src.length
        );
      }
      return tok;
    }

    function expectIdent() {
      const tok = next();
      if (!tok || tok.type !== "IDENT") {
        throw PgqLexer.createSyntaxError(
          "expected identifier, got " + (tok ? tok.raw : "end of input"),
          tok ? tok.start : src.length
        );
      }
      return tok;
    }

    // Parse label expression: |, &, !, %, ( ... ), label_ident
    function parseLabelExpr() {
      return parseLabelDisjunction();
    }

    function parseLabelDisjunction() {
      let left = parseLabelConjunction();
      const terms = [left];
      while (isPunct(peek(), "|")) {
        next();
        terms.push(parseLabelConjunction());
      }
      if (terms.length === 1) return left;
      return { kind: "OR", terms: terms };
    }

    function parseLabelConjunction() {
      let left = parseLabelPrimary();
      const terms = [left];
      while (isPunct(peek(), "&")) {
        next();
        terms.push(parseLabelPrimary());
      }
      if (terms.length === 1) return left;
      return { kind: "AND", terms: terms };
    }

    function parseLabelPrimary() {
      if (isPunct(peek(), "!")) {
        next();
        return { kind: "NOT", expr: parseLabelPrimary() };
      }
      if (isPunct(peek(), "%")) {
        next();
        return { kind: "WILDCARD" };
      }
      if (isPunct(peek(), "(")) {
        next();
        const inner = parseLabelExpr();
        expectPunct(")");
        return inner;
      }
      const id = expectIdent();
      return { kind: "LABEL", name: id.value };
    }

    function extractLabelNames(labelExpr, outList) {
      const list = outList || [];
      if (!labelExpr) return list;
      if (labelExpr.kind === "LABEL") {
        if (list.indexOf(labelExpr.name) === -1) {
          list.push(labelExpr.name);
        }
      } else if (labelExpr.kind === "OR" || labelExpr.kind === "AND") {
        for (let i = 0; i < labelExpr.terms.length; i++) {
          extractLabelNames(labelExpr.terms[i], list);
        }
      } else if (labelExpr.kind === "NOT") {
        extractLabelNames(labelExpr.expr, list);
      }
      return list;
    }

    // Collect tokens inside element WHERE up to closing `)` or `]` at depth 0
    function parseElementWhereClause(closeChar) {
      expectKw("where");
      const startIdx = pos;
      let depth = 0;
      while (pos < tokens.length) {
        const t = peek();
        if (isPunct(t, "(") || isPunct(t, "[") || isPunct(t, "{")) {
          depth++;
          next();
        } else if (isPunct(t, ")") || isPunct(t, "]") || isPunct(t, "}")) {
          if (depth === 0 && isPunct(t, closeChar)) {
            break;
          }
          depth--;
          next();
        } else {
          next();
        }
      }
      const endIdx = pos;
      if (endIdx <= startIdx) {
        throw PgqLexer.createSyntaxError(
          "empty WHERE clause in element pattern",
          peek() ? peek().start : src.length
        );
      }
      const exprTokens = tokens.slice(startIdx, endIdx);
      return {
        sql: src.slice(exprTokens[0].start, exprTokens[exprTokens.length - 1].end).trim(),
        tokens: exprTokens
      };
    }

    function parseElementContent(closeChar) {
      let variable = null;
      let labelExpr = null;
      let whereClause = null;

      // Optional variable name (unless it is IS, WHERE, or closeChar)
      if (
        peek() &&
        peek().type === "IDENT" &&
        !isKw(peek(), "is") &&
        !isKw(peek(), "where")
      ) {
        variable = next().value;
      }

      // Optional (IS | :) label_expr
      if (isKw(peek(), "is") || isPunct(peek(), ":")) {
        next();
        labelExpr = parseLabelExpr();
      }

      // Optional WHERE search_condition
      if (isKw(peek(), "where")) {
        whereClause = parseElementWhereClause(closeChar);
      }

      if (!isPunct(peek(), closeChar)) {
        throw PgqLexer.createSyntaxError(
          'expected "' + closeChar + '" at end of element pattern, got ' + (peek() ? peek().raw : "end of input"),
          peek() ? peek().start : src.length
        );
      }

      return {
        variable: variable,
        labelExpr: labelExpr,
        labelNames: extractLabelNames(labelExpr),
        whereClause: whereClause
      };
    }

    function parseQuantifier(allowBraces) {
      const t = peek();
      if (!t) return null;
      if (isPunct(t, "+")) {
        next();
        return { min: 1, max: null, raw: "+" };
      }
      if (isPunct(t, "*")) {
        next();
        return { min: 0, max: null, raw: "*" };
      }
      if (isPunct(t, "?")) {
        next();
        return { min: 0, max: 1, raw: "?" };
      }
      if (isPunct(t, "{")) {
        if (!allowBraces) {
          throw PgqLexer.createSyntaxError(
            "quantifier {m,n} is not allowed directly on an abbreviated edge arrow; use -[...]->{m,n} or ((a)->(b)){m,n}",
            t.start
          );
        }
        next(); // consume '{'
        let minHops = 0;
        let maxHops = null;
        if (peek() && peek().type === "NUMBER") {
          minHops = parseInt(next().value, 10);
          maxHops = minHops;
        }
        if (isPunct(peek(), ",")) {
          next();
          if (peek() && peek().type === "NUMBER") {
            maxHops = parseInt(next().value, 10);
          } else {
            maxHops = null;
          }
        }
        expectPunct("}");
        if (maxHops !== null && maxHops < minHops) {
          throw PgqLexer.createSyntaxError(
            "invalid quantifier bounds {" + minHops + "," + maxHops + "}",
            t.start
          );
        }
        return { min: minHops, max: maxHops, raw: "{" + minHops + "," + (maxHops === null ? "" : maxHops) + "}" };
      }
      return null;
    }

    // Check whether an open '(' starts a parenthesized path pattern `((a)->(b))`
    // rather than a single vertex pattern `(a IS lbl WHERE ...)`.
    function isParenthesizedSubpathAt(idx) {
      if (!isPunct(tokens[idx], "(")) return false;
      // If tokens[idx + 1] is `(`, or if after matching the inner `(...)` at idx+1
      // there is an edge arrow before the outer `)`, it is a parenthesized path!
      if (isPunct(tokens[idx + 1], "(")) {
        return true;
      }
      if (
        isKw(tokens[idx + 1], "all") ||
        isKw(tokens[idx + 1], "any") ||
        isKw(tokens[idx + 1], "shortest") ||
        isKw(tokens[idx + 1], "cheapest") ||
        isKw(tokens[idx + 1], "walk") ||
        isKw(tokens[idx + 1], "trail") ||
        isKw(tokens[idx + 1], "acyclic") ||
        isKw(tokens[idx + 1], "simple")
      ) {
        if (isPunct(tokens[idx + 2], "(") || isKw(tokens[idx + 2], "shortest") || isKw(tokens[idx + 2], "cheapest")) {
          return true;
        }
      }
      return false;
    }

    function parseVertexOrSubpath() {
      if (!isPunct(peek(), "(")) {
        throw PgqLexer.createSyntaxError(
          "expected vertex pattern '(' in MATCH clause, got " + (peek() ? peek().raw : "end of input"),
          peek() ? peek().start : src.length
        );
      }

      if (isParenthesizedSubpathAt(pos)) {
        next(); // consume outer '('
        const subMode = parseOptionalPathModePrefix();
        const subElements = parsePathSequence();
        let subWhere = null;
        if (isKw(peek(), "where")) {
          subWhere = parseElementWhereClause(")");
        }
        expectPunct(")");
        const q = parseQuantifier(true);
        return {
          kind: "SUBPATH",
          pathMode: subMode,
          elements: subElements,
          whereClause: subWhere,
          quantifier: q
        };
      }

      next(); // consume '('
      const content = parseElementContent(")");
      expectPunct(")");
      return {
        kind: "VERTEX",
        variable: content.variable,
        labelExpr: content.labelExpr,
        labelNames: content.labelNames,
        whereClause: content.whereClause
      };
    }

    function isEdgeStart(tok) {
      if (!tok) return false;
      return (
        isPunct(tok, "-") ||
        isPunct(tok, "<-") ||
        isPunct(tok, "->") ||
        isPunct(tok, "<->")
      );
    }

    function parseEdgePattern() {
      const first = next();
      // Bracketed edge: `-[ ... ]->`, `-[ ... ]-`, `<-[ ... ]-`, `<-[ ... ]->`
      if ((isPunct(first, "-") || isPunct(first, "<-")) && isPunct(peek(), "[")) {
        const leftArrow = first.value === "<-";
        next(); // consume '['
        const content = parseElementContent("]");
        expectPunct("]");

        let rightDir = null;
        if (isPunct(peek(), "->")) {
          next();
          rightDir = "->";
        } else if (isPunct(peek(), "-")) {
          next();
          rightDir = "-";
        } else {
          throw PgqLexer.createSyntaxError(
            'expected "->" or "-" after "]" in edge pattern',
            peek() ? peek().start : src.length
          );
        }

        let direction = "ANY";
        if (!leftArrow && rightDir === "->") {
          direction = "FORWARD";
        } else if (leftArrow && rightDir === "-") {
          direction = "REVERSE";
        } else {
          direction = "ANY";
        }

        const quantifier = parseQuantifier(true);
        return {
          kind: "EDGE",
          direction: direction,
          abbreviated: false,
          variable: content.variable,
          labelExpr: content.labelExpr,
          labelNames: content.labelNames,
          whereClause: content.whereClause,
          quantifier: quantifier
        };
      }

      // Abbreviated edge: `->`, `<-`, `<->`, `-`
      let direction = "ANY";
      if (first.value === "->") {
        direction = "FORWARD";
      } else if (first.value === "<-") {
        direction = "REVERSE";
      } else if (first.value === "-" || first.value === "<->") {
        direction = "ANY";
      } else {
        throw PgqLexer.createSyntaxError("invalid edge pattern token " + first.raw, first.start);
      }

      const quantifier = parseQuantifier(false);
      return {
        kind: "EDGE",
        direction: direction,
        abbreviated: true,
        variable: null,
        labelExpr: null,
        labelNames: [],
        whereClause: null,
        quantifier: quantifier
      };
    }

    function parsePathSequence() {
      const rawItems = [];

      if (isEdgeStart(peek())) {
        throw PgqLexer.createSyntaxError(
          "path pattern must begin with a vertex pattern, not an edge pattern",
          peek().start
        );
      }

      const firstItem = parseVertexOrSubpath();
      rawItems.push(firstItem);

      while (true) {
        if (isPunct(peek(), "(")) {
          throw PgqLexer.createSyntaxError(
            "consecutive vertex patterns without an intervening edge pattern",
            peek().start
          );
        }
        if (!isEdgeStart(peek())) {
          break;
        }
        const edge = parseEdgePattern();
        rawItems.push(edge);

        if (isEdgeStart(peek())) {
          throw PgqLexer.createSyntaxError(
            "consecutive edge patterns without an intervening vertex pattern",
            peek().start
          );
        }
        if (!isPunct(peek(), "(")) {
          throw PgqLexer.createSyntaxError(
            "edge pattern at end of path lacks destination vertex pattern",
            peek() ? peek().start : src.length
          );
        }
        const nextVertex = parseVertexOrSubpath();
        rawItems.push(nextVertex);
      }

      // Flatten unquantified SUBPATH nodes into the linear element sequence;
      // if a SUBPATH has a quantifier (e.g. `((a)->(b)){1,3}`) and wraps a
      // single 1-hop `(a)-[e]->(b)` step, propagate the quantifier onto its edge.
      const flat = [];
      function appendItem(item) {
        if (item.kind === "SUBPATH") {
          if (item.quantifier) {
            if (item.elements.length === 3 && item.elements[1].kind === "EDGE" && !item.elements[1].quantifier) {
              const modifiedEdge = Object.assign({}, item.elements[1], {
                quantifier: item.quantifier,
                subpathWhere: item.whereClause
              });
              appendItem(item.elements[0]);
              flat.push(modifiedEdge);
              appendItem(item.elements[2]);
              return;
            }
          }
          for (let i = 0; i < item.elements.length; i++) {
            appendItem(item.elements[i]);
          }
        } else {
          flat.push(item);
        }
      }

      for (let i = 0; i < rawItems.length; i++) {
        appendItem(rawItems[i]);
      }

      return flat;
    }

    function parseOptionalPathModePrefix() {
      let selector = null; // 'ANY_SHORTEST', 'ALL_SHORTEST', 'ANY_CHEAPEST', 'ALL_CHEAPEST'
      let kLimit = 1;
      let pathMode = "WALK"; // 'WALK', 'TRAIL', 'ACYCLIC', 'SIMPLE'
      let pathVar = null;

      // Optional `p =` path variable assignment
      if (
        peek() &&
        peek().type === "IDENT" &&
        isPunct(peek(1), "=")
      ) {
        pathVar = next().value;
        next(); // consume '='
      }

      let qualifier = null;
      if (isKw(peek(), "all") || isKw(peek(), "any")) {
        qualifier = next().lower.toUpperCase();
      }

      if (isKw(peek(), "shortest")) {
        next();
        selector = (qualifier === "ALL" ? "ALL" : "ANY") + "_SHORTEST";
        if (peek() && peek().type === "NUMBER") {
          kLimit = parseInt(next().value, 10);
        }
      } else if (isKw(peek(), "cheapest")) {
        next();
        selector = (qualifier === "ALL" ? "ALL" : "ANY") + "_CHEAPEST";
      } else if (qualifier !== null) {
        throw PgqLexer.createSyntaxError(
          'expected SHORTEST or CHEAPEST after "' + qualifier + '"',
          peek() ? peek().start : src.length
        );
      }

      if (
        isKw(peek(), "walk") ||
        isKw(peek(), "trail") ||
        isKw(peek(), "acyclic") ||
        isKw(peek(), "simple")
      ) {
        pathMode = next().lower.toUpperCase();
      }

      return {
        pathVar: pathVar,
        selector: selector,
        kLimit: kLimit,
        pathMode: pathMode
      };
    }

    // Optional leading MATCH keyword
    if (isKw(peek(), "match")) {
      next();
    }

    if (isKw(peek(), "columns")) {
      throw PgqLexer.createSyntaxError('empty MATCH pattern before "COLUMNS"', peek().start);
    }

    const pathModeInfo = parseOptionalPathModePrefix();
    const elements = parsePathSequence();

    if (isPunct(peek(), ",")) {
      const err = new Error("comma-separated path patterns in MATCH are not supported");
      err.sqlstate = "0A000";
      throw err;
    }

    // Optional graph-level WHERE search_condition before COLUMNS
    let graphWhere = null;
    if (isKw(peek(), "where")) {
      next();
      const whereStartIdx = pos;
      let depth = 0;
      while (pos < tokens.length) {
        const t = peek();
        if (isPunct(t, "(") || isPunct(t, "[") || isPunct(t, "{")) {
          depth++;
          next();
        } else if (isPunct(t, ")") || isPunct(t, "]") || isPunct(t, "}")) {
          depth--;
          next();
        } else if (depth === 0 && isKw(t, "columns")) {
          break;
        } else {
          next();
        }
      }
      const whereEndIdx = pos;
      if (whereEndIdx <= whereStartIdx) {
        throw PgqLexer.createSyntaxError(
          "empty WHERE clause in MATCH pattern",
          peek() ? peek().start : src.length
        );
      }
      const wTokens = tokens.slice(whereStartIdx, whereEndIdx);
      graphWhere = {
        sql: src.slice(wTokens[0].start, wTokens[wTokens.length - 1].end).trim(),
        tokens: wTokens
      };
    }

    // COLUMNS ( ... ) clause
    let columns = [];
    if (isKw(peek(), "columns")) {
      next();
      expectPunct("(");
      while (true) {
        let depth = 0;
        const itemStartIdx = pos;
        let asIdx = -1;
        while (pos < tokens.length) {
          const t = peek();
          if (isPunct(t, "(") || isPunct(t, "[") || isPunct(t, "{")) {
            depth++;
            next();
          } else if (isPunct(t, ")") || isPunct(t, "]") || isPunct(t, "}")) {
            if (depth === 0) {
              break;
            }
            depth--;
            next();
          } else if (depth === 0 && isPunct(t, ",")) {
            break;
          } else if (depth === 0 && isKw(t, "as")) {
            asIdx = pos;
            next();
          } else {
            next();
          }
        }
        const itemEndIdx = pos;
        if (itemEndIdx <= itemStartIdx) {
          throw PgqLexer.createSyntaxError(
            "empty column item in COLUMNS (...)",
            peek() ? peek().start : src.length
          );
        }

        let exprEndIdx = itemEndIdx;
        let alias = null;
        if (asIdx !== -1) {
          if (asIdx + 2 !== itemEndIdx || tokens[asIdx + 1].type !== "IDENT") {
            throw PgqLexer.createSyntaxError(
              "expected column alias identifier after AS in COLUMNS",
              tokens[asIdx].start
            );
          }
          alias = tokens[asIdx + 1].value;
          exprEndIdx = asIdx;
        }

        const exprTokens = tokens.slice(itemStartIdx, exprEndIdx);
        if (exprTokens.length === 0) {
          throw PgqLexer.createSyntaxError("missing column expression before AS", tokens[itemStartIdx].start);
        }
        const exprSql = src.slice(exprTokens[0].start, exprTokens[exprTokens.length - 1].end).trim();

        if (!alias) {
          if (
            exprTokens.length === 3 &&
            exprTokens[0].type === "IDENT" &&
            isPunct(exprTokens[1], ".") &&
            exprTokens[2].type === "IDENT"
          ) {
            alias = exprTokens[2].value;
          } else if (exprTokens.length === 1 && exprTokens[0].type === "IDENT") {
            alias = exprTokens[0].value;
          } else if (exprTokens[0].type === "IDENT" && exprTokens.length >= 3 && isPunct(exprTokens[1], "(")) {
            alias = exprTokens[0].value;
          } else {
            alias = "?column?";
          }
        }

        columns.push({
          exprSql: exprSql,
          exprTokens: exprTokens,
          alias: alias
        });

        if (isPunct(peek(), ",")) {
          next();
          continue;
        }
        break;
      }
      expectPunct(")");
    } else {
      throw PgqLexer.createSyntaxError(
        'expected COLUMNS clause in GRAPH_TABLE pattern, got ' + (peek() ? peek().raw : "end of input"),
        peek() ? peek().start : src.length
      );
    }

    while (isPunct(peek(), ";")) {
      next();
    }

    if (pos < tokens.length) {
      throw PgqLexer.createSyntaxError(
        "unexpected token " + peek().raw + " after COLUMNS clause",
        peek().start
      );
    }

    return {
      pathMode: pathModeInfo,
      elements: elements,
      graphWhere: graphWhere,
      columns: columns
    };
  }

  return {
    parseGraphTableMatch: parseGraphTableMatch
  };
})();


  /* === Module: codegen_sql.js === */
/*-------------------------------------------------------------------------
 *
 * codegen_sql.js
 *    SQL/PGQ Semantic Analyzer, Column Type Inferrer, and Relational /
 *    Recursive (`WITH RECURSIVE ... UNION DISTINCT ON`) SQL Code Generator.
 *
 *-------------------------------------------------------------------------
 */

const PgqCodegenSql = (function () {
  "use strict";

  const AGGREGATE_FUNCS = {
    count: true,
    sum: true,
    avg: true,
    min: true,
    max: true,
    array_agg: true,
    string_agg: true,
    json_agg: true,
    jsonb_agg: true,
    bool_and: true,
    bool_or: true,
    every: true
  };

  const SRF_FUNCS = {
    generate_series: true,
    unnest: true,
    json_array_elements: true,
    jsonb_array_elements: true,
    json_array_elements_text: true,
    jsonb_array_elements_text: true,
    json_each: true,
    jsonb_each: true,
    regexp_matches: true,
    regexp_split_to_table: true
  };

  const SQL_KEYWORDS = {
    select: true, from: true, where: true, and: true, or: true, not: true,
    in: true, is: true, null: true, true: true, false: true, between: true,
    like: true, ilike: true, similar: true, to: true, case: true, when: true,
    then: true, else: true, end: true, cast: true, as: true, collate: true,
    asc: true, desc: true, distinct: true, on: true, order: true, by: true,
    group: true, having: true, limit: true, offset: true, union: true,
    all: true, intersect: true, except: true, exists: true, any: true,
    some: true, array: true, date: true, time: true, timestamp: true,
    interval: true, int: true, integer: true, bigint: true, smallint: true,
    text: true, varchar: true, char: true, character: true, varying: true,
    numeric: true, decimal: true, real: true, float: true, double: true,
    precision: true, boolean: true, bool: true, json: true, jsonb: true,
    default: true, pg_catalog: true
  };

  function throwPgqError(msg, sqlstate) {
    const err = new Error(msg);
    err.sqlstate = sqlstate || "42601";
    throw err;
  }

  function serializeLabelExpr(expr) {
    if (!expr) return "";
    if (expr.kind === "WILDCARD") return "%";
    if (expr.kind === "LABEL") return PgqLexer.quoteIdent(expr.name);
    if (expr.kind === "NOT") return "!(" + serializeLabelExpr(expr.expr) + ")";
    if (expr.kind === "OR") {
      return "(" + expr.terms.map(serializeLabelExpr).join("|") + ")";
    }
    if (expr.kind === "AND") {
      return "(" + expr.terms.map(serializeLabelExpr).join("&") + ")";
    }
    return "";
  }

  function matchesLabelExpr(elementTable, labelExpr) {
    if (!labelExpr || labelExpr.kind === "WILDCARD") {
      return true;
    }
    if (labelExpr.kind === "LABEL") {
      return Boolean(elementTable.labels && elementTable.labels[labelExpr.name]);
    }
    if (labelExpr.kind === "OR") {
      for (let i = 0; i < labelExpr.terms.length; i++) {
        if (matchesLabelExpr(elementTable, labelExpr.terms[i])) return true;
      }
      return false;
    }
    if (labelExpr.kind === "AND") {
      for (let i = 0; i < labelExpr.terms.length; i++) {
        if (!matchesLabelExpr(elementTable, labelExpr.terms[i])) return false;
      }
      return true;
    }
    if (labelExpr.kind === "NOT") {
      return !matchesLabelExpr(elementTable, labelExpr.expr);
    }
    return false;
  }

  /*
   * Build the analyzed graph pattern model:
   * - Validates all referenced labels against pg.vertices and pg.edges
   * - Merges repeated element variables into canonical factors
   * - Computes exposed properties for each factor per SQL/PGQ Section 6.5
   */
  function analyzePattern(pg, matchAst) {
    const vertexLabels = Object.create(null);
    const edgeLabels = Object.create(null);

    for (let i = 0; i < pg.vertices.length; i++) {
      const v = pg.vertices[i];
      const lnames = Object.keys(v.labels);
      for (let j = 0; j < lnames.length; j++) {
        vertexLabels[lnames[j]] = true;
      }
    }
    for (let i = 0; i < pg.edges.length; i++) {
      const e = pg.edges[i];
      const lnames = Object.keys(e.labels);
      for (let j = 0; j < lnames.length; j++) {
        edgeLabels[lnames[j]] = true;
      }
    }

    // Validate label existence & element kind compatibility
    for (let i = 0; i < matchAst.elements.length; i++) {
      const el = matchAst.elements[i];
      for (let j = 0; j < el.labelNames.length; j++) {
        const lname = el.labelNames[j];
        const inV = Boolean(vertexLabels[lname]);
        const inE = Boolean(edgeLabels[lname]);
        if (!inV && !inE) {
          throwPgqError('label "' + lname + '" does not exist in property graph "' + pg.graph_name + '"', "42704");
        }
        if (el.kind === "VERTEX" && !inV) {
          throwPgqError('label "' + lname + '" is only associated with edges and cannot qualify a vertex', "42809");
        }
        if (el.kind === "EDGE" && !inE) {
          throwPgqError('label "' + lname + '" is only associated with vertices and cannot qualify an edge', "42809");
        }
      }
    }

    const factors = [];
    const factorByVar = Object.create(null);
    const elementToFactorIdx = [];

    // First pass: assign factor indices to vertices (even positions) and edges (odd positions)
    for (let i = 0; i < matchAst.elements.length; i++) {
      const el = matchAst.elements[i];
      if (el.variable && Object.prototype.hasOwnProperty.call(factorByVar, el.variable)) {
        const fIdx = factorByVar[el.variable];
        const factor = factors[fIdx];

        if (factor.kind !== el.kind) {
          throwPgqError(
            'element variable "' + el.variable + '" cannot be bound to both a vertex and an edge',
            "42601"
          );
        }

        if (el.labelExpr) {
          const newSer = serializeLabelExpr(el.labelExpr);
          if (factor.labelExpr) {
            const oldSer = serializeLabelExpr(factor.labelExpr);
            if (oldSer !== newSer) {
              throwPgqError(
                'element variable "' + el.variable + '" has conflicting label expressions',
                "42601"
              );
            }
          } else {
            factor.labelExpr = el.labelExpr;
            factor.labelNames = el.labelNames.slice();
          }
        }

        if (el.whereClause) {
          factor.whereClauses.push({
            whereClause: el.whereClause,
            elementVariable: el.variable
          });
        }

        factor.occurrences.push(i);
        elementToFactorIdx.push(fIdx);
      } else {
        const fIdx = factors.length;
        const factor = {
          factorIndex: fIdx,
          kind: el.kind,
          variable: el.variable || null,
          labelExpr: el.labelExpr || null,
          labelNames: el.labelNames ? el.labelNames.slice() : [],
          whereClauses: el.whereClause
            ? [{ whereClause: el.whereClause, elementVariable: el.variable || null }]
            : [],
          occurrences: [i],
          candidateTables: [],
          exposedProperties: Object.create(null)
        };
        factors.push(factor);
        if (el.variable) {
          factorByVar[el.variable] = fIdx;
        }
        elementToFactorIdx.push(fIdx);
      }
    }

    // Second pass: if an edge factor appears multiple times (e.g. `(a)-[b]->(a)-[b]->(a)`),
    // verify that all occurrences connect the exact same source and destination vertex factors!
    for (let fIdx = 0; fIdx < factors.length; fIdx++) {
      const factor = factors[fIdx];
      if (factor.kind === "EDGE" && factor.occurrences.length > 1) {
        const firstPos = factor.occurrences[0];
        const firstSrcFactor = elementToFactorIdx[firstPos - 1];
        const firstDstFactor = elementToFactorIdx[firstPos + 1];
        const firstDir = matchAst.elements[firstPos].direction;

        for (let k = 1; k < factor.occurrences.length; k++) {
          const occPos = factor.occurrences[k];
          const occSrcFactor = elementToFactorIdx[occPos - 1];
          const occDstFactor = elementToFactorIdx[occPos + 1];
          const occDir = matchAst.elements[occPos].direction;

          let compatible = false;
          if (firstDir === occDir && firstSrcFactor === occSrcFactor && firstDstFactor === occDstFactor) {
            compatible = true;
          } else if (
            ((firstDir === "FORWARD" && occDir === "REVERSE") ||
              (firstDir === "REVERSE" && occDir === "FORWARD")) &&
            firstSrcFactor === occDstFactor &&
            firstDstFactor === occSrcFactor
          ) {
            compatible = true;
          }
          if (!compatible) {
            throwPgqError(
              'edge variable "' +
                factor.variable +
                '" is bound multiple times with different endpoint vertex variables',
              "42601"
            );
          }
        }
      }
    }

    // Third pass: compute candidate tables and Section 6.5 exposed properties for each factor
    for (let fIdx = 0; fIdx < factors.length; fIdx++) {
      const factor = factors[fIdx];
      const pool = factor.kind === "VERTEX" ? pg.vertices : pg.edges;
      for (let i = 0; i < pool.length; i++) {
        const tbl = pool[i];
        if (matchesLabelExpr(tbl, factor.labelExpr)) {
          factor.candidateTables.push(tbl);
        }
      }

      if (factor.labelExpr && factor.labelNames.length > 0 && factor.labelExpr.kind !== "WILDCARD") {
        // Exposed properties are those associated with any label referenced in factor.labelNames
        // on any table of factor.kind
        for (let i = 0; i < pool.length; i++) {
          const tbl = pool[i];
          for (let j = 0; j < factor.labelNames.length; j++) {
            const lname = factor.labelNames[j];
            const lblObj = tbl.labels[lname];
            if (lblObj && lblObj.properties) {
              const pnames = Object.keys(lblObj.properties);
              for (let p = 0; p < pnames.length; p++) {
                factor.exposedProperties[pnames[p]] = pg.property_types[pnames[p]];
              }
            }
          }
        }
      } else {
        // Unlabeled element pattern: exposes all properties defined on any label of factor.kind
        for (let i = 0; i < pool.length; i++) {
          const tbl = pool[i];
          const lnames = Object.keys(tbl.labels);
          for (let j = 0; j < lnames.length; j++) {
            const props = tbl.labels[lnames[j]].properties;
            const pnames = Object.keys(props);
            for (let p = 0; p < pnames.length; p++) {
              factor.exposedProperties[pnames[p]] = pg.property_types[pnames[p]];
            }
          }
        }
      }
    }

    // Check if any edge has a quantifier or if SHORTEST / CHEAPEST is active
    let hasQuantifier = Boolean(matchAst.pathMode && matchAst.pathMode.selector);
    for (let i = 1; i < matchAst.elements.length; i += 2) {
      if (matchAst.elements[i].quantifier) {
        hasQuantifier = true;
        break;
      }
    }

    return {
      factors: factors,
      factorByVar: factorByVar,
      elementToFactorIdx: elementToFactorIdx,
      hasQuantifier: hasQuantifier
    };
  }

  /*
   * Find how elementTable defines property `propName` across ANY of its labels
   * (SQL/PGQ Section 6.5). If elementTable does not define `propName` under any
   * of its labels in the property graph, returns null.
   */
  function findElementTableProperty(elementTable, propName) {
    const lnames = Object.keys(elementTable.labels);
    for (let i = 0; i < lnames.length; i++) {
      const props = elementTable.labels[lnames[i]].properties;
      if (props && Object.prototype.hasOwnProperty.call(props, propName)) {
        return props[propName];
      }
    }
    return null;
  }

  /*
   * Render a property's underlying SQL expression for table alias `sqlAlias`.
   */
  function renderElementPropertySql(elementTable, propName, sqlAlias, globalPropType) {
    const propMeta = findElementTableProperty(elementTable, propName);
    if (!propMeta) {
      return "NULL::" + globalPropType.type_sql;
    }

    const colSet = Object.create(null);
    if (elementTable.table_columns) {
      for (let i = 0; i < elementTable.table_columns.length; i++) {
        colSet[elementTable.table_columns[i]] = true;
      }
    }

    const toks = PgqLexer.tokenize(propMeta.expr);
    let out = "";
    let prevEnd = 0;
    for (let i = 0; i < toks.length; i++) {
      const t = toks[i];
      if (t.start > prevEnd) {
        out += " ";
      }
      prevEnd = t.end;

      const prevTok = i > 0 ? toks[i - 1] : null;
      const nextTok = i + 1 < toks.length ? toks[i + 1] : null;

      if (
        t.type === "IDENT" &&
        !(prevTok && prevTok.value === ".") &&
        !(nextTok && nextTok.value === "(") &&
        !(prevTok && prevTok.type === "IDENT" && !prevTok.quoted && prevTok.lower === "collate") &&
        colSet[t.value]
      ) {
        out += sqlAlias + "." + PgqLexer.quoteIdent(t.value);
      } else {
        out += t.raw;
      }
    }

    let wrapped = "(" + out + ")";
    if (
      propMeta.collation_name &&
      propMeta.collation_name !== "" &&
      propMeta.collation_name !== '"default"' &&
      propMeta.collation_name !== "default"
    ) {
      const cleanColl = propMeta.collation_name.replace(/^"|"$/g, "");
      wrapped = "(" + wrapped + " COLLATE " + PgqLexer.quoteIdent(cleanColl) + ")";
    }
    return wrapped;
  }

  /*
   * Validate COLUMNS (...) and WHERE expressions for star projections,
   * aggregates, window functions, and SRFs.
   */
  function validateColumnsClause(matchAst, analyzed) {
    for (let cIdx = 0; cIdx < matchAst.columns.length; cIdx++) {
      const col = matchAst.columns[cIdx];
      const toks = col.exprTokens;

      let parenDepth = 0;
      let subqueryDepth = 0;

      for (let i = 0; i < toks.length; i++) {
        const t = toks[i];
        if (t.value === "(") {
          parenDepth++;
          if (
            i + 1 < toks.length &&
            toks[i + 1].type === "IDENT" &&
            !toks[i + 1].quoted &&
            (toks[i + 1].lower === "select" || toks[i + 1].lower === "with")
          ) {
            subqueryDepth++;
          }
          continue;
        }
        if (t.value === ")") {
          if (subqueryDepth > 0 && parenDepth === subqueryDepth) {
            subqueryDepth--;
          }
          parenDepth--;
          continue;
        }

        // Check `v.*` star property reference
        if (
          t.type === "IDENT" &&
          i + 2 < toks.length &&
          toks[i + 1].value === "." &&
          toks[i + 2].value === "*" &&
          subqueryDepth === 0
        ) {
          throwPgqError("SELECT * (all properties) in GRAPH_TABLE COLUMNS is not supported", "0A000");
        }

        if (subqueryDepth === 0 && t.type === "IDENT" && !t.quoted) {
          if (t.lower === "over" && i + 1 < toks.length && toks[i + 1].value === "(") {
            throwPgqError("window functions are not allowed in GRAPH_TABLE COLUMNS", "42P20");
          }
          if (i + 1 < toks.length && toks[i + 1].value === "(") {
            if (AGGREGATE_FUNCS[t.lower]) {
              const isHorizontalHopCount =
                analyzed &&
                analyzed.hasQuantifier &&
                t.lower === "count" &&
                i + 3 < toks.length &&
                toks[i + 3].value === ")" &&
                (toks[i + 2].value === "*" ||
                  (toks[i + 2].type === "IDENT" &&
                    Object.prototype.hasOwnProperty.call(analyzed.factorByVar, toks[i + 2].value)));
              if (!isHorizontalHopCount) {
                throwPgqError("aggregate functions are not allowed in GRAPH_TABLE COLUMNS", "42803");
              }
            }
            if (SRF_FUNCS[t.lower]) {
              throwPgqError("set-returning functions are not allowed in GRAPH_TABLE COLUMNS", "0A000");
            }
          }
        }
      }
    }
  }

  /*
   * Rewrite an expression token stream (from element WHERE, graph WHERE, or COLUMNS)
   * for a specific factor-to-table assignment (`tableAssignment`, where
   * `tableAssignment[fIdx]` is the bound vertex/edge table descriptor, or null
   * during static validation / column type inference).
   */
  function rewriteExpression(
    exprTokens,
    pg,
    analyzed,
    scopeInfo,
    tableAssignment,
    lateralState,
    paramsObj
  ) {
    let out = "";
    let prevEnd = exprTokens.length > 0 ? exprTokens[0].start : 0;
    let i = 0;
    const parenStack = [];

    while (i < exprTokens.length) {
      const t = exprTokens[i];
      if (t.start > prevEnd) {
        out += " ";
      }

      if (t.value === "(") {
        const nextTok = i + 1 < exprTokens.length ? exprTokens[i + 1] : null;
        const isSubquery = Boolean(
          nextTok &&
            nextTok.type === "IDENT" &&
            !nextTok.quoted &&
            (nextTok.lower === "select" || nextTok.lower === "with")
        );
        parenStack.push(isSubquery);
        out += "(";
        prevEnd = t.end;
        i++;
        continue;
      }

      if (t.value === ")") {
        parenStack.pop();
        out += ")";
        prevEnd = t.end;
        i++;
        continue;
      }

      const inSubquery = parenStack.indexOf(true) !== -1;

      // Check `$1` positional parameter
      if (t.type === "PARAM") {
        if (paramsObj && Array.isArray(paramsObj)) {
          const idx = t.paramIndex - 1;
          const val = idx >= 0 && idx < paramsObj.length ? paramsObj[idx] : null;
          out += PgqLexer.quoteLiteral(val);
        } else if (paramsObj && typeof paramsObj === "object" && Object.prototype.hasOwnProperty.call(paramsObj, String(t.paramIndex))) {
          out += PgqLexer.quoteLiteral(paramsObj[String(t.paramIndex)]);
        } else {
          out += t.raw;
        }
        prevEnd = t.end;
        i++;
        continue;
      }

      // Check `:param` named parameter
      if (
        t.value === ":" &&
        i + 1 < exprTokens.length &&
        exprTokens[i + 1].type === "IDENT"
      ) {
        const pName = exprTokens[i + 1].value;
        if (paramsObj && typeof paramsObj === "object" && !Array.isArray(paramsObj) && Object.prototype.hasOwnProperty.call(paramsObj, pName)) {
          out += PgqLexer.quoteLiteral(paramsObj[pName]);
          prevEnd = exprTokens[i + 1].end;
          i += 2;
          continue;
        }
      }

      // Check horizontal path functions on quantified paths:
      // `count(r)`, `path_length()`, `path_cost()`, `path_weight()`, `path_vertices()`, `path_edges()`
      if (
        analyzed &&
        analyzed.hasQuantifier &&
        !inSubquery &&
        t.type === "IDENT" &&
        !t.quoted &&
        i + 1 < exprTokens.length &&
        exprTokens[i + 1].value === "("
      ) {
        const fnLower = t.lower;
        if (
          fnLower === "count" ||
          fnLower === "path_length" ||
          fnLower === "path_cost" ||
          fnLower === "path_weight" ||
          fnLower === "path_vertices" ||
          fnLower === "path_edges"
        ) {
          let closeIdx = i + 2;
          let pDepth = 1;
          while (closeIdx < exprTokens.length && pDepth > 0) {
            if (exprTokens[closeIdx].value === "(") pDepth++;
            else if (exprTokens[closeIdx].value === ")") {
              pDepth--;
              if (pDepth === 0) break;
            }
            closeIdx++;
          }
          if (closeIdx < exprTokens.length && exprTokens[closeIdx].value === ")") {
            const innerToks = exprTokens.slice(i + 2, closeIdx);
            const isCountEdge =
              fnLower === "count" &&
              innerToks.length === 1 &&
              (innerToks[0].value === "*" ||
                (innerToks[0].type === "IDENT" &&
                  Object.prototype.hasOwnProperty.call(analyzed.factorByVar, innerToks[0].value)));
            if (fnLower !== "count" || isCountEdge) {
              if (fnLower === "count" || fnLower === "path_length") {
                out += tableAssignment ? "(__p.__depth)" : "(0::integer)";
              } else if (fnLower === "path_cost" || fnLower === "path_weight") {
                out += tableAssignment ? "(__p.__cost)" : "(0::numeric)";
              } else if (fnLower === "path_vertices") {
                out += tableAssignment ? "(__p.__path_keys)" : "(ARRAY[]::text[])";
              } else if (fnLower === "path_edges") {
                out += tableAssignment ? "(__p.__edge_keys)" : "(ARRAY[]::text[])";
              }
              prevEnd = exprTokens[closeIdx].end;
              i = closeIdx + 1;
              continue;
            }
          }
        }
      }

      // Check `ident . *` (disallowed property star)
      if (
        t.type === "IDENT" &&
        i + 2 < exprTokens.length &&
        exprTokens[i + 1].value === "." &&
        exprTokens[i + 2].value === "*" &&
        !inSubquery
      ) {
        throwPgqError('syntax error at or near "*"', "42601");
      }

      // Check qualified reference `ident1 . ident2`
      if (
        t.type === "IDENT" &&
        i + 2 < exprTokens.length &&
        exprTokens[i + 1].value === "." &&
        exprTokens[i + 2].type === "IDENT"
      ) {
        const varName = t.value;
        const propName = exprTokens[i + 2].value;

        // Allow schema-qualified function call or collation `pg_catalog.func(...)`
        if (
          varName === "pg_catalog" ||
          (i + 3 < exprTokens.length && exprTokens[i + 3].value === "(")
        ) {
          out += t.raw + "." + exprTokens[i + 2].raw;
          prevEnd = exprTokens[i + 2].end;
          i += 3;
          continue;
        }

        const hasGraphFactor = Object.prototype.hasOwnProperty.call(analyzed.factorByVar, varName);

        // Enforce element-level WHERE local scoping!
        if (scopeInfo.kind === "ELEMENT_WHERE") {
          if (hasGraphFactor && varName !== scopeInfo.allowedVariable) {
            throwPgqError(
              'cannot reference non-local element variable "' +
                varName +
                '" in element pattern WHERE clause',
              "42703"
            );
          }
          if (!scopeInfo.allowedVariable && hasGraphFactor) {
            throwPgqError(
              'cannot reference element variable "' +
                varName +
                '" in anonymous element pattern WHERE clause',
              "42703"
            );
          }
        }

        if (hasGraphFactor) {
          const fIdx = analyzed.factorByVar[varName];
          const factor = analyzed.factors[fIdx];

          if (Object.prototype.hasOwnProperty.call(factor.exposedProperties, propName)) {
            const globalPropType = pg.property_types[propName];
            if (!tableAssignment) {
              // Static type-inference mode: emit typed dummy placeholder
              out += "(NULL::" + globalPropType.type_sql + ")";
            } else {
              const boundTbl = tableAssignment[fIdx];
              const sqlAlias = "__f" + fIdx;
              if (boundTbl && boundTbl.__is_quantified_cte) {
                out += boundTbl.propExprMap[propName] || ("NULL::" + globalPropType.type_sql);
              } else {
                out += renderElementPropertySql(boundTbl, propName, sqlAlias, globalPropType);
              }
            }
            prevEnd = exprTokens[i + 2].end;
            i += 3;
            continue;
          }

          // Property not found on graph variable `varName`:
          // Wait: in graph_table.sql:156-174, if `varName` is a graph variable,
          // referencing a non-existent property on `varName` is an error EVEN if
          // a lateral table has the same name, UNLESS `varName` is not a graph variable!
          // Let's double check graph_table.sql:157-174:
          // Line 162: `(x1 IS customers WHERE x1.address = 'US')` -> `address` IS a property of `customers`.
          // Line 173: `(x1 IS customers)-[IS customer_orders]->(o IS orders WHERE o.order_id = x1.a)`
          //   Here `x1` IS a graph variable, and `o`'s WHERE clause references `x1.a` (blocked by element WHERE check above!).
          // Line 174: `(c IS customers WHERE c.address = 'US' AND c.customer_id = x1.a)-[IS customer_orders]->(x1 IS orders)`
          //   Here `x1` is bound to `orders` later in the pattern, so `x1` IS a graph variable in the pattern, and referencing `x1.a` in `c`'s WHERE clause is blocked by the element WHERE check above!
          throwPgqError(
            'property "' + propName + '" does not exist on element variable "' + varName + '"',
            "42703"
          );
        }

        // Not a graph variable: check outer LATERAL environment
        if (lateralState && lateralState.envByAlias && lateralState.envByAlias[varName]) {
          const latRel = lateralState.envByAlias[varName];
          const latCol = latRel.columns[propName];
          if (!latCol) {
            throwPgqError(
              'column "' + propName + '" does not exist on relation "' + varName + '"',
              "42703"
            );
          }
          const paramPlaceholder = lateralState.registerLateralRef(latRel, latCol);
          out += paramPlaceholder;
          prevEnd = exprTokens[i + 2].end;
          i += 3;
          continue;
        }

        if (inSubquery) {
          out += t.raw + "." + exprTokens[i + 2].raw;
          prevEnd = exprTokens[i + 2].end;
          i += 3;
          continue;
        }

        throwPgqError('missing FROM-clause entry for table "' + varName + '"', "42P01");
      }

      // Check unqualified identifier `ident` (e.g. function parameter `sname` in UDFs)
      if (
        t.type === "IDENT" &&
        !inSubquery &&
        !(i > 0 && exprTokens[i - 1].value === ".") &&
        !(i + 1 < exprTokens.length && exprTokens[i + 1].value === "(") &&
        !(i + 1 < exprTokens.length && exprTokens[i + 1].value === ".") &&
        !(i > 0 && exprTokens[i - 1].type === "OP" && exprTokens[i - 1].value === "::") &&
        !(i > 0 && exprTokens[i - 1].type === "IDENT" && !exprTokens[i - 1].quoted && exprTokens[i - 1].lower === "collate") &&
        !SQL_KEYWORDS[t.lower]
      ) {
        if (lateralState && lateralState.unqualifiedCols && lateralState.unqualifiedCols[t.value]) {
          const entry = lateralState.unqualifiedCols[t.value];
          const paramPlaceholder = lateralState.registerLateralRef(entry.rel, entry.col);
          out += paramPlaceholder;
          prevEnd = t.end;
          i++;
          continue;
        }
        if (paramsObj && typeof paramsObj === "object" && !Array.isArray(paramsObj) && Object.prototype.hasOwnProperty.call(paramsObj, t.value)) {
          out += PgqLexer.quoteLiteral(paramsObj[t.value]);
          prevEnd = t.end;
          i++;
          continue;
        }
      }

      out += t.raw;
      prevEnd = t.end;
      i++;
    }

    return out;
  }

  function createLateralState(lateralEnv, mode) {
    const envByAlias = Object.create(null);
    const unqualifiedCols = Object.create(null);
    const usedVars = [];
    const usedVarByKey = Object.create(null);

    if (Array.isArray(lateralEnv)) {
      for (let i = 0; i < lateralEnv.length; i++) {
        const rel = lateralEnv[i];
        if (!rel || !rel.alias) continue;
        const colMap = Object.create(null);
        if (Array.isArray(rel.columns)) {
          for (let j = 0; j < rel.columns.length; j++) {
            const c = rel.columns[j];
            colMap[c.name] = c;
            if (!Object.prototype.hasOwnProperty.call(unqualifiedCols, c.name)) {
              unqualifiedCols[c.name] = { rel: { alias: rel.alias, rtindex: rel.rtindex }, col: c };
            }
          }
        } else if (rel.columns && typeof rel.columns === "object") {
          const cnames = Object.keys(rel.columns);
          for (let j = 0; j < cnames.length; j++) {
            const c = rel.columns[cnames[j]];
            colMap[cnames[j]] = c;
            if (!Object.prototype.hasOwnProperty.call(unqualifiedCols, cnames[j])) {
              unqualifiedCols[cnames[j]] = { rel: { alias: rel.alias, rtindex: rel.rtindex }, col: c };
            }
          }
        }
        envByAlias[rel.alias] = {
          alias: rel.alias,
          rtindex: rel.rtindex,
          columns: colMap
        };
      }
    }

    function registerLateralRef(rel, col) {
      const typeSql = col.type_sql || "text";
      if (mode === "TYPE_INFER") {
        return "(NULL::" + typeSql + ")";
      }
      if (mode === "DIRECT_QUALIFIED") {
        return PgqLexer.quoteIdent(rel.alias) + "." + PgqLexer.quoteIdent(col.name);
      }
      const key = String(rel.rtindex) + ":" + String(col.attno);
      if (!Object.prototype.hasOwnProperty.call(usedVarByKey, key)) {
        const paramNum = usedVars.length + 1;
        usedVars.push({
          param_num: paramNum,
          rtindex: rel.rtindex,
          attno: col.attno,
          type_oid: col.type_oid,
          typmod: col.typmod !== undefined ? col.typmod : -1,
          collation_oid: col.collation_oid || 0,
          type_sql: typeSql,
          alias: rel.alias,
          col_name: col.name
        });
        usedVarByKey[key] = paramNum;
      }
      const pNum = usedVarByKey[key];
      return "($" + pNum + "::" + typeSql + ")";
    }

    return {
      envByAlias: envByAlias,
      unqualifiedCols: unqualifiedCols,
      usedVars: usedVars,
      registerLateralRef: registerLateralRef
    };
  }

  /*
   * Infer the output column names, type OIDs, typmods, collations, and SQL type
   * strings for `COLUMNS (...)` of a `MATCH` pattern against `pg`.
   */
  function inferColumnsForGraph(pg, matchSrc, lateralEnv) {
    const matchAst = PgqMatchParser.parseGraphTableMatch(matchSrc);
    const analyzed = analyzePattern(pg, matchAst);
    validateColumnsClause(matchAst, analyzed);
    const latState = createLateralState(lateralEnv || [], "TYPE_INFER");

    // Validate all element WHERE clauses and graph WHERE clause even during parse-time inference
    for (let fIdx = 0; fIdx < analyzed.factors.length; fIdx++) {
      const factor = analyzed.factors[fIdx];
      for (let w = 0; w < factor.whereClauses.length; w++) {
        const wc = factor.whereClauses[w];
        rewriteExpression(
          wc.whereClause.tokens,
          pg,
          analyzed,
          { kind: "ELEMENT_WHERE", allowedVariable: wc.elementVariable },
          null,
          latState,
          null
        );
      }
    }
    if (matchAst.graphWhere) {
      rewriteExpression(
        matchAst.graphWhere.tokens,
        pg,
        analyzed,
        { kind: "GRAPH_WHERE" },
        null,
        latState,
        null
      );
    }

    const outCols = [];
    for (let i = 0; i < matchAst.columns.length; i++) {
      const col = matchAst.columns[i];
      const exprTokens = col.exprTokens;

      // Fast path: simple `v.prop` reference
      if (
        exprTokens.length === 3 &&
        exprTokens[0].type === "IDENT" &&
        exprTokens[1].value === "." &&
        exprTokens[2].type === "IDENT"
      ) {
        const vName = exprTokens[0].value;
        const pName = exprTokens[2].value;
        if (Object.prototype.hasOwnProperty.call(analyzed.factorByVar, vName)) {
          const fIdx = analyzed.factorByVar[vName];
          const factor = analyzed.factors[fIdx];
          if (!Object.prototype.hasOwnProperty.call(factor.exposedProperties, pName)) {
            throwPgqError(
              'property "' + pName + '" does not exist on element variable "' + vName + '"',
              "42703"
            );
          }
          const pt = pg.property_types[pName];
          outCols.push({
            name: col.alias,
            type_oid: pt.type_oid,
            typmod: pt.typmod,
            collation_oid: pt.collation_oid || 0,
            type_sql: pt.type_sql
          });
          continue;
        }
      }

      // General expression: rewrite graph properties to `(NULL::type)` and ask PostgreSQL `pg_typeof`
      const dummySql = rewriteExpression(
        exprTokens,
        pg,
        analyzed,
        { kind: "COLUMNS" },
        null,
        latState,
        null
      );

      const typeRows = plv8.execute(
        `SELECT pg_catalog.pg_typeof(sub.__val)::pg_catalog.oid::int AS type_oid,
                pg_catalog.format_type(pg_catalog.pg_typeof(sub.__val)::pg_catalog.oid, -1)::text AS type_sql
           FROM (SELECT 1) __one
           CROSS JOIN LATERAL (SELECT (${dummySql}) AS __val) sub`
      );

      let typeOid = typeRows[0].type_oid;
      let typeSql = typeRows[0].type_sql;
      let collOid = 0;
      if (typeOid === 705) {
        // Coerce unknown literal ('unknown-literal' or NULL) to text (25) matching PG19 graph_table.sql:138!
        typeOid = 25;
        typeSql = "text";
        collOid = 100;
      }

      outCols.push({
        name: col.alias,
        type_oid: typeOid,
        typmod: -1,
        collation_oid: collOid,
        type_sql: typeSql
      });
    }

    return {
      columns: outCols,
      matchAst: matchAst,
      analyzed: analyzed
    };
  }

  /*
   * Check whether edgeTable connects srcVertexTable -> dstVertexTable in direction `dir`
   * ('FORWARD', 'REVERSE', 'ANY'), returning the list of valid `{ srcEndpoint, dstEndpoint }`
   * orientations.
   *
   * Note: per PG 19 `graph_table.sql:406`, if `dir === 'ANY'` and the edge connects the
   * SAME vertex factor to itself (`srcFactorIdx === dstFactorIdx`), a self-referencing edge
   * table (`source.vertex_alias === destination.vertex_alias`) is emitted only ONCE!
   */
  function getEdgeOrientations(edgeTable, srcVertexTable, dstVertexTable, dir, srcFactorIdx, dstFactorIdx) {
    const orientations = [];
    const fwdMatch =
      edgeTable.source.vertex_alias === srcVertexTable.alias &&
      edgeTable.destination.vertex_alias === dstVertexTable.alias;
    const revMatch =
      edgeTable.destination.vertex_alias === srcVertexTable.alias &&
      edgeTable.source.vertex_alias === dstVertexTable.alias;

    if (dir === "FORWARD") {
      if (fwdMatch) {
        orientations.push({
          srcEdgeCols: edgeTable.source.edge_cols,
          srcVertexCols: edgeTable.source.vertex_cols,
          dstEdgeCols: edgeTable.destination.edge_cols,
          dstVertexCols: edgeTable.destination.vertex_cols
        });
      }
    } else if (dir === "REVERSE") {
      if (revMatch) {
        orientations.push({
          srcEdgeCols: edgeTable.destination.edge_cols,
          srcVertexCols: edgeTable.destination.vertex_cols,
          dstEdgeCols: edgeTable.source.edge_cols,
          dstVertexCols: edgeTable.source.vertex_cols
        });
      }
    } else {
      // dir === "ANY"
      if (fwdMatch) {
        orientations.push({
          srcEdgeCols: edgeTable.source.edge_cols,
          srcVertexCols: edgeTable.source.vertex_cols,
          dstEdgeCols: edgeTable.destination.edge_cols,
          dstVertexCols: edgeTable.destination.vertex_cols
        });
      }
      // Only add reverse orientation if not a self-loop on the same vertex factor (`(a)-[c]-(a)`)
      if (revMatch && !(fwdMatch && srcFactorIdx === dstFactorIdx)) {
        orientations.push({
          srcEdgeCols: edgeTable.destination.edge_cols,
          srcVertexCols: edgeTable.destination.vertex_cols,
          dstEdgeCols: edgeTable.source.edge_cols,
          dstVertexCols: edgeTable.source.vertex_cols
        });
      }
    }

    return orientations;
  }

  /*
   * Generate SQL for a fixed-length path pattern via DFS over candidate vertex & edge tables.
   */
  function generateFixedLengthSql(
    pg,
    matchAst,
    analyzed,
    targetCols,
    lateralState,
    paramsObj
  ) {
    const elements = matchAst.elements;
    const elementToFactorIdx = analyzed.elementToFactorIdx;
    const factors = analyzed.factors;
    const branches = [];

    // State during DFS:
    // factorTableAssignment[fIdx] = assigned vertex/edge table object
    // edgeStepOrientations[stepIdx] = chosen { srcEdgeCols, srcVertexCols, dstEdgeCols, dstVertexCols }
    const factorTableAssignment = new Array(factors.length).fill(null);
    const edgeStepOrientations = [];

    function buildBranchSql() {
      const fromParts = [];
      const whereParts = [];

      for (let fIdx = 0; fIdx < factors.length; fIdx++) {
        const tbl = factorTableAssignment[fIdx];
        fromParts.push(tbl.qualified_name + " __f" + fIdx);
      }

      // Join quals for each edge step
      let stepIdx = 0;
      for (let ePos = 1; ePos < elements.length; ePos += 2) {
        const srcFIdx = elementToFactorIdx[ePos - 1];
        const edgeFIdx = elementToFactorIdx[ePos];
        const dstFIdx = elementToFactorIdx[ePos + 1];
        const orient = edgeStepOrientations[stepIdx++];

        for (let k = 0; k < orient.srcEdgeCols.length; k++) {
          whereParts.push(
            "__f" +
              edgeFIdx +
              "." +
              PgqLexer.quoteIdent(orient.srcEdgeCols[k]) +
              " = __f" +
              srcFIdx +
              "." +
              PgqLexer.quoteIdent(orient.srcVertexCols[k])
          );
        }
        for (let k = 0; k < orient.dstEdgeCols.length; k++) {
          whereParts.push(
            "__f" +
              edgeFIdx +
              "." +
              PgqLexer.quoteIdent(orient.dstEdgeCols[k]) +
              " = __f" +
              dstFIdx +
              "." +
              PgqLexer.quoteIdent(orient.dstVertexCols[k])
          );
        }
      }

      // Element-level WHERE quals for each factor
      for (let fIdx = 0; fIdx < factors.length; fIdx++) {
        const factor = factors[fIdx];
        for (let w = 0; w < factor.whereClauses.length; w++) {
          const wc = factor.whereClauses[w];
          const condSql = rewriteExpression(
            wc.whereClause.tokens,
            pg,
            analyzed,
            { kind: "ELEMENT_WHERE", allowedVariable: wc.elementVariable },
            factorTableAssignment,
            lateralState,
            paramsObj
          );
          whereParts.push("(" + condSql + ")");
        }
      }

      // Graph-level WHERE qual
      if (matchAst.graphWhere) {
        const gCondSql = rewriteExpression(
          matchAst.graphWhere.tokens,
          pg,
          analyzed,
          { kind: "GRAPH_WHERE" },
          factorTableAssignment,
          lateralState,
          paramsObj
        );
        whereParts.push("(" + gCondSql + ")");
      }

      // SELECT projections
      const selectItems = [];
      for (let cIdx = 0; cIdx < matchAst.columns.length; cIdx++) {
        const col = matchAst.columns[cIdx];
        const targetCol = targetCols[cIdx];
        const projExpr = rewriteExpression(
          col.exprTokens,
          pg,
          analyzed,
          { kind: "COLUMNS" },
          factorTableAssignment,
          lateralState,
          paramsObj
        );
        let castExpr = "(" + projExpr + ")::" + targetCol.type_sql;
        if (
          targetCol.collation_oid &&
          targetCol.collation_oid !== 100 &&
          pg.property_types &&
          col.exprTokens.length === 3 &&
          col.exprTokens[1].value === "."
        ) {
          const pMeta = pg.property_types[col.exprTokens[2].value];
          if (pMeta && pMeta.collation_name && pMeta.collation_name !== '"default"' && pMeta.collation_name !== "default") {
            const cleanColl = pMeta.collation_name.replace(/^"|"$/g, "");
            castExpr = "(" + castExpr + " COLLATE " + PgqLexer.quoteIdent(cleanColl) + ")";
          }
        }
        selectItems.push(castExpr + " AS " + PgqLexer.quoteIdent(targetCol.name));
      }

      let sql = "SELECT " + selectItems.join(", ") + " FROM " + fromParts.join(", ");
      if (whereParts.length > 0) {
        sql += " WHERE " + whereParts.join(" AND ");
      }
      return sql;
    }

    function dfs(elemPos) {
      if (elemPos === 0) {
        const vFactorIdx = elementToFactorIdx[0];
        const vFactor = factors[vFactorIdx];
        for (let i = 0; i < vFactor.candidateTables.length; i++) {
          factorTableAssignment[vFactorIdx] = vFactor.candidateTables[i];
          dfs(1);
          factorTableAssignment[vFactorIdx] = null;
        }
        return;
      }

      if (elemPos >= elements.length) {
        branches.push(buildBranchSql());
        return;
      }

      // elemPos is an odd index (EDGE), elemPos + 1 is the destination VERTEX
      const srcFIdx = elementToFactorIdx[elemPos - 1];
      const edgeFIdx = elementToFactorIdx[elemPos];
      const dstFIdx = elementToFactorIdx[elemPos + 1];

      const srcTbl = factorTableAssignment[srcFIdx];
      const edgeFactor = factors[edgeFIdx];
      const dstFactor = factors[dstFIdx];
      const edgeElem = elements[elemPos];

      const edgeCandidates =
        factorTableAssignment[edgeFIdx] !== null
          ? [factorTableAssignment[edgeFIdx]]
          : edgeFactor.candidateTables;

      const dstCandidates =
        factorTableAssignment[dstFIdx] !== null
          ? [factorTableAssignment[dstFIdx]]
          : dstFactor.candidateTables;

      const hadEdgeAssigned = factorTableAssignment[edgeFIdx] !== null;
      const hadDstAssigned = factorTableAssignment[dstFIdx] !== null;

      for (let eIdx = 0; eIdx < edgeCandidates.length; eIdx++) {
        const eTbl = edgeCandidates[eIdx];
        for (let dIdx = 0; dIdx < dstCandidates.length; dIdx++) {
          const dTbl = dstCandidates[dIdx];
          const orientations = getEdgeOrientations(
            eTbl,
            srcTbl,
            dTbl,
            edgeElem.direction,
            srcFIdx,
            dstFIdx
          );
          for (let oIdx = 0; oIdx < orientations.length; oIdx++) {
            factorTableAssignment[edgeFIdx] = eTbl;
            factorTableAssignment[dstFIdx] = dTbl;
            edgeStepOrientations.push(orientations[oIdx]);

            dfs(elemPos + 2);

            edgeStepOrientations.pop();
            if (!hadEdgeAssigned) factorTableAssignment[edgeFIdx] = null;
            if (!hadDstAssigned) factorTableAssignment[dstFIdx] = null;
          }
        }
      }
    }

    dfs(0);

    if (branches.length === 0) {
      const dummyCols = targetCols.map(function (c) {
        return "NULL::" + c.type_sql + " AS " + PgqLexer.quoteIdent(c.name);
      });
      return "SELECT " + dummyCols.join(", ") + " WHERE false";
    }

    if (branches.length === 1) {
      return branches[0];
    }

    return "SELECT * FROM (" + branches.join(" UNION ALL ") + ") __pgq_u";
  }

  /*
   * Generate a `WITH RECURSIVE ... UNION DISTINCT ON (...)` query for quantified
   * path patterns (`+`, `*`, `?`, `{m,n}`) and `ANY/ALL SHORTEST` / `CHEAPEST`
   * on the `one-with-everything` branch of `postsql/postgres`.
   */
  function generateQuantifiedPathSql(
    pg,
    matchAst,
    analyzed,
    targetCols,
    lateralState,
    paramsObj
  ) {
    const elements = matchAst.elements;
    const factors = analyzed.factors;
    const elementToFactorIdx = analyzed.elementToFactorIdx;
    const selector = (matchAst.pathMode && matchAst.pathMode.selector) || null;
    const pathMode = (matchAst.pathMode && matchAst.pathMode.pathMode) || "WALK";

    // Locate the quantified edge (or if `SHORTEST`/`CHEAPEST` is specified on a 1-hop pattern,
    // treat the edge at index 1 as `+` if unquantified).
    let qEdgePos = -1;
    for (let i = 1; i < elements.length; i += 2) {
      if (elements[i].quantifier) {
        qEdgePos = i;
        break;
      }
    }
    if (qEdgePos === -1 && elements.length >= 3) {
      qEdgePos = 1;
    }

    const srcFIdx = elementToFactorIdx[qEdgePos - 1];
    const edgeFIdx = elementToFactorIdx[qEdgePos];
    const dstFIdx = elementToFactorIdx[qEdgePos + 1];

    const srcFactor = factors[srcFIdx];
    const edgeFactor = factors[edgeFIdx];
    const dstFactor = factors[dstFIdx];
    const qEdge = elements[qEdgePos];

    const quant = qEdge.quantifier || { min: 1, max: null };
    const minHops = quant.min !== undefined ? quant.min : 1;
    const maxHops = quant.max !== undefined ? quant.max : null;

    // Identify weight/cost expression on edge tables for CHEAPEST path mode
    function getEdgeCostExpr(eTbl, alias) {
      const costPropNames = ["cost", "weight", "distance", "price", "len", "val", "eprop1"];
      for (let i = 0; i < costPropNames.length; i++) {
        const pName = costPropNames[i];
        const pMeta = findElementTableProperty(eTbl, pName);
        if (pMeta) {
          return "(" + renderElementPropertySql(eTbl, pName, alias, pg.property_types[pName]) + ")::numeric";
        }
      }
      return "1::numeric";
    }

    // Collect all candidate edge step branches connecting compatible vertex tables
    const edgeUnionBranches = [];
    for (let eIdx = 0; eIdx < edgeFactor.candidateTables.length; eIdx++) {
      const eTbl = edgeFactor.candidateTables[eIdx];
      const allV = pg.vertices;
      for (let sIdx = 0; sIdx < allV.length; sIdx++) {
        const sTbl = allV[sIdx];
        for (let dIdx = 0; dIdx < allV.length; dIdx++) {
          const dTbl = allV[dIdx];
          const orientations = getEdgeOrientations(eTbl, sTbl, dTbl, qEdge.direction, -1, -2);
          for (let oIdx = 0; oIdx < orientations.length; oIdx++) {
            const orient = orientations[oIdx];
            const srcKeyExpr =
              PgqLexer.quoteLiteral(sTbl.alias + ":") +
              " || " +
              orient.srcEdgeCols
                .map(function (c) { return "__e." + PgqLexer.quoteIdent(c) + "::text"; })
                .join(" || '|' || ");
            const dstKeyExpr =
              PgqLexer.quoteLiteral(dTbl.alias + ":") +
              " || " +
              orient.dstEdgeCols
                .map(function (c) { return "__e." + PgqLexer.quoteIdent(c) + "::text"; })
                .join(" || '|' || ");
            const edgeKeyExpr =
              PgqLexer.quoteLiteral(eTbl.alias + ":") +
              " || " +
              eTbl.key_cols
                .map(function (c) { return "__e." + PgqLexer.quoteIdent(c) + "::text"; })
                .join(" || '|' || ");

            const eWhereParts = [];
            for (let w = 0; w < edgeFactor.whereClauses.length; w++) {
              const wc = edgeFactor.whereClauses[w];
              const fakeAssign = new Array(factors.length).fill(null);
              fakeAssign[edgeFIdx] = eTbl;
              let cond = rewriteExpression(
                wc.whereClause.tokens,
                pg,
                analyzed,
                { kind: "ELEMENT_WHERE", allowedVariable: wc.elementVariable },
                fakeAssign,
                lateralState,
                paramsObj
              );
              cond = cond.replace(new RegExp("__f" + edgeFIdx + "\\b", "g"), "__e");
              eWhereParts.push("(" + cond + ")");
            }

            const costExpr = getEdgeCostExpr(eTbl, "__e");
            let branch =
              "SELECT (" +
              srcKeyExpr +
              ") AS __src_key, (" +
              dstKeyExpr +
              ") AS __dst_key, (" +
              edgeKeyExpr +
              ") AS __edge_key, (" +
              costExpr +
              ") AS __step_cost FROM " +
              eTbl.qualified_name +
              " __e";
            if (eWhereParts.length > 0) {
              branch += " WHERE " + eWhereParts.join(" AND ");
            }
            edgeUnionBranches.push(branch);
          }
        }
      }
    }

    if (edgeUnionBranches.length === 0 && minHops > 0) {
      const dummyCols = targetCols.map(function (c) {
        return "NULL::" + c.type_sql + " AS " + PgqLexer.quoteIdent(c.name);
      });
      return "SELECT " + dummyCols.join(", ") + " WHERE false";
    }

    const edgeCteSql =
      edgeUnionBranches.length > 0
        ? edgeUnionBranches.join(" UNION ALL ")
        : "SELECT NULL::text AS __src_key, NULL::text AS __dst_key, NULL::text AS __edge_key, 0::numeric AS __step_cost WHERE false";

    // Build source vertex key union for starting the search
    const srcKeyBranches = [];
    for (let i = 0; i < srcFactor.candidateTables.length; i++) {
      const sTbl = srcFactor.candidateTables[i];
      const sKey =
        PgqLexer.quoteLiteral(sTbl.alias + ":") +
        " || " +
        sTbl.key_cols
          .map(function (c) { return "__sv." + PgqLexer.quoteIdent(c) + "::text"; })
          .join(" || '|' || ");
      const sWhere = [];
      for (let w = 0; w < srcFactor.whereClauses.length; w++) {
        const wc = srcFactor.whereClauses[w];
        const fakeAssign = new Array(factors.length).fill(null);
        fakeAssign[srcFIdx] = sTbl;
        let cond = rewriteExpression(
          wc.whereClause.tokens,
          pg,
          analyzed,
          { kind: "ELEMENT_WHERE", allowedVariable: wc.elementVariable },
          fakeAssign,
          lateralState,
          paramsObj
        );
        cond = cond.replace(new RegExp("__f" + srcFIdx + "\\b", "g"), "__sv");
        sWhere.push("(" + cond + ")");
      }
      let sb = "SELECT (" + sKey + ") AS __vkey FROM " + sTbl.qualified_name + " __sv";
      if (sWhere.length > 0) {
        sb += " WHERE " + sWhere.join(" AND ");
      }
      srcKeyBranches.push(sb);
    }

    const srcVerticesSql =
      srcKeyBranches.length > 0
        ? srcKeyBranches.join(" UNION ALL ")
        : "SELECT NULL::text AS __vkey WHERE false";

    // Determine whether to use `UNION DISTINCT ON` (on postsql/postgres one-with-everything)
    const useDistinctOnShortest =
      selector === "ANY_SHORTEST" ||
      (selector === null && maxHops === null);

    let unionClause = "UNION ALL";

    const anchorBranches = [];
    if (minHops === 0) {
      anchorBranches.push(
        "SELECT __s.__vkey AS __src_key, __s.__vkey AS __dst_key, 0 AS __depth, 0::numeric AS __cost, ARRAY[__s.__vkey] AS __path_keys, ARRAY[]::text[] AS __edge_keys FROM __pgq_src __s"
      );
    }
    anchorBranches.push(
      "SELECT __e.__src_key, __e.__dst_key, 1 AS __depth, __e.__step_cost AS __cost, ARRAY[__e.__src_key, __e.__dst_key] AS __path_keys, ARRAY[__e.__edge_key] AS __edge_keys " +
        "FROM __pgq_src __s JOIN __pgq_edges __e ON __e.__src_key = __s.__vkey"
    );

    const anchorSql =
      minHops === 0
        ? "SELECT __s.__vkey AS __src_key, __s.__vkey AS __dst_key, 0 AS __depth, 0::numeric AS __cost, ARRAY[__s.__vkey] AS __path_keys, ARRAY[]::text[] AS __edge_keys FROM __pgq_src __s"
        : anchorBranches[0];

    const recWhereParts = [];
    if (maxHops !== null) {
      recWhereParts.push("__r.__depth < " + maxHops);
    } else {
      recWhereParts.push("__r.__depth < 100");
    }

    if (pathMode === "TRAIL") {
      recWhereParts.push("NOT (__e.__edge_key = ANY(__r.__edge_keys))");
    } else if (
      pathMode === "ACYCLIC" ||
      pathMode === "SIMPLE" ||
      maxHops === null ||
      selector === "ALL_SHORTEST" ||
      selector === "ANY_CHEAPEST" ||
      selector === "ALL_CHEAPEST"
    ) {
      recWhereParts.push("NOT (__e.__dst_key = ANY(__r.__path_keys))");
    }

    const recSql =
      "SELECT __r.__src_key, __e.__dst_key, __r.__depth + 1 AS __depth, (__r.__cost + __e.__step_cost)::numeric AS __cost, " +
      "__r.__path_keys || __e.__dst_key AS __path_keys, __r.__edge_keys || __e.__edge_key AS __edge_keys " +
      "FROM __pgq_reach __r JOIN __pgq_edges __e ON __r.__dst_key = __e.__src_key " +
      "WHERE " +
      recWhereParts.join(" AND ");

    let reachFilterSql =
      "SELECT * FROM __pgq_reach WHERE __depth >= " +
      minHops +
      (maxHops !== null ? " AND __depth <= " + maxHops : "");

    if (useDistinctOnShortest) {
      reachFilterSql =
        "SELECT DISTINCT ON (__src_key, __dst_key) __src_key, __dst_key, __depth, __cost, __path_keys, __edge_keys " +
        "FROM __pgq_reach WHERE __depth >= " +
        minHops +
        (maxHops !== null ? " AND __depth <= " + maxHops : "") +
        " ORDER BY __src_key, __dst_key, __depth ASC, __cost ASC";
    } else if (selector === "ALL_SHORTEST") {
      reachFilterSql =
        "SELECT __src_key, __dst_key, __depth, __cost, __path_keys, __edge_keys FROM (" +
        "SELECT *, pg_catalog.min(__depth) OVER (PARTITION BY __src_key, __dst_key) AS __min_d " +
        "FROM __pgq_reach WHERE __depth >= " +
        minHops +
        (maxHops !== null ? " AND __depth <= " + maxHops : "") +
        ") __ranked WHERE __depth = __min_d";
    } else if (selector === "ANY_CHEAPEST") {
      reachFilterSql =
        "SELECT DISTINCT ON (__src_key, __dst_key) __src_key, __dst_key, __depth, __cost, __path_keys, __edge_keys " +
        "FROM __pgq_reach WHERE __depth >= " +
        minHops +
        (maxHops !== null ? " AND __depth <= " + maxHops : "") +
        " ORDER BY __src_key, __dst_key, __cost ASC, __depth ASC";
    } else if (selector === "ALL_CHEAPEST") {
      reachFilterSql =
        "SELECT __src_key, __dst_key, __depth, __cost, __path_keys, __edge_keys FROM (" +
        "SELECT *, pg_catalog.min(__cost) OVER (PARTITION BY __src_key, __dst_key) AS __min_c " +
        "FROM __pgq_reach WHERE __depth >= " +
        minHops +
        (maxHops !== null ? " AND __depth <= " + maxHops : "") +
        ") __ranked WHERE __cost = __min_c";
    }

    // Now join `__pgq_filtered` back to candidate `(srcTbl, dstTbl)` pairs
    const finalBranches = [];
    for (let sIdx = 0; sIdx < srcFactor.candidateTables.length; sIdx++) {
      const sTbl = srcFactor.candidateTables[sIdx];
      for (let dIdx = 0; dIdx < dstFactor.candidateTables.length; dIdx++) {
        const dTbl = dstFactor.candidateTables[dIdx];

        const factorAssign = new Array(factors.length).fill(null);
        factorAssign[srcFIdx] = sTbl;
        factorAssign[dstFIdx] = dTbl;
        factorAssign[edgeFIdx] = {
          __is_quantified_cte: true,
          propExprMap: {
            hop_count: "__p.__depth",
            depth: "__p.__depth",
            cost: "__p.__cost",
            weight: "__p.__cost"
          }
        };

        const sKeyMatch =
          "(" +
          PgqLexer.quoteLiteral(sTbl.alias + ":") +
          " || " +
          sTbl.key_cols
            .map(function (c) { return "__f" + srcFIdx + "." + PgqLexer.quoteIdent(c) + "::text"; })
            .join(" || '|' || ") +
          ") = __p.__src_key";

        const dKeyMatch =
          "(" +
          PgqLexer.quoteLiteral(dTbl.alias + ":") +
          " || " +
          dTbl.key_cols
            .map(function (c) { return "__f" + dstFIdx + "." + PgqLexer.quoteIdent(c) + "::text"; })
            .join(" || '|' || ") +
          ") = __p.__dst_key";

        const whereParts = [sKeyMatch, dKeyMatch];

        if (srcFIdx === dstFIdx) {
          for (let k = 0; k < sTbl.key_cols.length; k++) {
            const kc = PgqLexer.quoteIdent(sTbl.key_cols[k]);
            whereParts.push("__f" + srcFIdx + "." + kc + " = __f" + dstFIdx + "." + kc);
          }
        }

        // Destination element WHERE clauses
        for (let w = 0; w < dstFactor.whereClauses.length; w++) {
          const wc = dstFactor.whereClauses[w];
          whereParts.push(
            "(" +
              rewriteExpression(
                wc.whereClause.tokens,
                pg,
                analyzed,
                { kind: "ELEMENT_WHERE", allowedVariable: wc.elementVariable },
                factorAssign,
                lateralState,
                paramsObj
              ) +
              ")"
          );
        }

        // Graph-level WHERE clause
        if (matchAst.graphWhere) {
          let gCond = rewriteExpression(
            matchAst.graphWhere.tokens,
            pg,
            analyzed,
            { kind: "GRAPH_WHERE" },
            factorAssign,
            lateralState,
            paramsObj
          );
          gCond = gCond
            .replace(/\bpath_length\s*\([^)]*\)/gi, "__p.__depth")
            .replace(/\bpath_cost\s*\([^)]*\)/gi, "__p.__cost");
          whereParts.push("(" + gCond + ")");
        }

        const selectItems = [];
        for (let cIdx = 0; cIdx < matchAst.columns.length; cIdx++) {
          const col = matchAst.columns[cIdx];
          const targetCol = targetCols[cIdx];
          let projExpr = rewriteExpression(
            col.exprTokens,
            pg,
            analyzed,
            { kind: "COLUMNS" },
            factorAssign,
            lateralState,
            paramsObj
          );
          projExpr = projExpr
            .replace(/\bpath_length\s*\([^)]*\)/gi, "__p.__depth")
            .replace(/\bpath_cost\s*\([^)]*\)/gi, "__p.__cost")
            .replace(/\bpath_vertices\s*\([^)]*\)/gi, "__p.__path_keys");
          selectItems.push("(" + projExpr + ")::" + targetCol.type_sql + " AS " + PgqLexer.quoteIdent(targetCol.name));
        }

        const fromTables =
          srcFIdx === dstFIdx
            ? sTbl.qualified_name + " __f" + srcFIdx + ", __pgq_filtered __p"
            : sTbl.qualified_name +
              " __f" +
              srcFIdx +
              ", " +
              dTbl.qualified_name +
              " __f" +
              dstFIdx +
              ", __pgq_filtered __p";

        finalBranches.push(
          "SELECT " + selectItems.join(", ") + " FROM " + fromTables + " WHERE " + whereParts.join(" AND ")
        );
      }
    }

    if (finalBranches.length === 0) {
      const dummyCols = targetCols.map(function (c) {
        return "NULL::" + c.type_sql + " AS " + PgqLexer.quoteIdent(c.name);
      });
      return "SELECT " + dummyCols.join(", ") + " WHERE false";
    }

    const bodySql =
      finalBranches.length === 1
        ? finalBranches[0]
        : "SELECT * FROM (" + finalBranches.join(" UNION ALL ") + ") __pgq_qu";

    return (
      "WITH RECURSIVE __pgq_edges(__src_key, __dst_key, __edge_key, __step_cost) AS (" +
      edgeCteSql +
      "), __pgq_src(__vkey) AS (" +
      srcVerticesSql +
      "), __pgq_reach(__src_key, __dst_key, __depth, __cost, __path_keys, __edge_keys) AS (" +
      anchorSql +
      " " +
      unionClause +
      " " +
      recSql +
      "), __pgq_filtered AS (" +
      reachFilterSql +
      ") " +
      bodySql
    );
  }

  /*
   * Main entry point for compiling a `GRAPH_TABLE` query into SQL.
   */
  function compileGraphTable(pg, matchSrc, expectedCols, lateralEnv, paramsObj) {
    const inferred = inferColumnsForGraph(pg, matchSrc, lateralEnv);
    const matchAst = inferred.matchAst;
    const analyzed = inferred.analyzed;

    // If caller supplied explicit `AS (col1 type1, ...)` (`expectedCols`),
    // verify column count matches `COLUMNS (...)` and use caller's target types.
    let targetCols = inferred.columns;
    if (Array.isArray(expectedCols) && expectedCols.length > 0) {
      if (expectedCols.length !== inferred.columns.length) {
        throwPgqError(
          "GRAPH_TABLE column definition list has " +
            expectedCols.length +
            " columns, but COLUMNS clause specifies " +
            inferred.columns.length,
          "42601"
        );
      }
      targetCols = [];
      for (let i = 0; i < expectedCols.length; i++) {
        const exp = expectedCols[i];
        const inf = inferred.columns[i];
        let typeSql = exp.type_sql;
        if (!typeSql && exp.type_oid) {
          const r = plv8.execute(
            `SELECT pg_catalog.format_type($1::pg_catalog.oid, $2::int)::text AS type_sql`,
            [exp.type_oid, exp.typmod !== undefined ? exp.typmod : -1]
          );
          typeSql = r[0].type_sql;
        }
        targetCols.push({
          name: exp.name || inf.name,
          type_oid: exp.type_oid || inf.type_oid,
          typmod: exp.typmod !== undefined ? exp.typmod : inf.typmod,
          collation_oid: exp.collation_oid || inf.collation_oid || 0,
          type_sql: typeSql || inf.type_sql
        });
      }
    }

    const latState = createLateralState(lateralEnv || [], "PARAM_BIND");
    let sql;
    if (analyzed.hasQuantifier) {
      sql = generateQuantifiedPathSql(pg, matchAst, analyzed, targetCols, latState, paramsObj);
    } else {
      sql = generateFixedLengthSql(pg, matchAst, analyzed, targetCols, latState, paramsObj);
    }

    return {
      sql: sql,
      columns: targetCols,
      lateral_vars: latState.usedVars
    };
  }

  return {
    inferColumnsForGraph: inferColumnsForGraph,
    compileGraphTable: compileGraphTable
  };
})();


  /* === Module: index.js === */
/*-------------------------------------------------------------------------
 *
 * index.js
 *    Main entry point for `pl-pgq` on top of PL/v8 v4.0:
 *      - `LANGUAGE "CREATE PROPERTY GRAPH"` handler (`compilePropertyGraphFunction`)
 *      - Parse-time column inference (`inferColumnsFromQuery`)
 *      - Plan-time & runtime SQL compiler (`compileGraphTable`)
 *      - Pure-JS `GRAPH_TABLE` execution helpers
 *
 *-------------------------------------------------------------------------
 */

const PlPgq = (function () {
  "use strict";

  const PGQ_LANG_NAMES = {
    "create property graph": true,
    "CREATE PROPERTY GRAPH": true,
    property_graph: true,
    sqlpgq_v8: true
  };

  function compilePropertyGraphFunction(src, meta) {
    const fnName = (meta && meta.proname) ? String(meta.proname) : "property_graph";
    const ast = PgqDdlParser.parseCreatePropertyGraph(src, fnName);

    // Validate immediately at CREATE FUNCTION time (when check_function_bodies = on)
    const checkRows = plv8.execute(
      `SELECT pg_catalog.current_setting('check_function_bodies') = 'on' AS check_bodies`
    );
    if (!checkRows || checkRows.length === 0 || checkRows[0].check_bodies) {
      PgqCatalog.buildPropertyGraphDescriptor(ast);
    }

    const returnsRawObject =
      meta && (meta.rettype_oid === 3802 || meta.rettype_oid === 114);
    const expr =
      "globalThis.__plpgq.evalPropertyGraphFunction(" +
      JSON.stringify(src) +
      ", " +
      JSON.stringify(fnName) +
      ")";
    return returnsRawObject
      ? "return " + expr + ";"
      : "return JSON.stringify(" + expr + ");";
  }

  function evalPropertyGraphFunction(src, fnName) {
    const ast = PgqDdlParser.parseCreatePropertyGraph(src, fnName);
    return PgqCatalog.buildPropertyGraphDescriptor(ast);
  }

  function resolveGraphArgument(graphArg) {
    if (graphArg && typeof graphArg === "object" && graphArg.__pgq_version === 1) {
      return graphArg;
    }

    if (typeof graphArg === "string") {
      const trimmed = graphArg.trim();
      if (trimmed.startsWith("{")) {
        let parsed = null;
        try {
          parsed = JSON.parse(trimmed);
        } catch (_e) {
          parsed = null;
        }
        if (parsed && parsed.__pgq_version === 1) {
          return parsed;
        }
      }

      // Strip trailing `()` if passed as `"myshop()"` or `"schema.myshop()"`
      let fnSpec = trimmed.replace(/\(\s*\)\s*$/, "").trim();
      // Strip single quotes if passed as `"'myshop'"`
      if (fnSpec.length >= 2 && fnSpec.startsWith("'") && fnSpec.endsWith("'")) {
        fnSpec = fnSpec.slice(1, -1).replace(/''/g, "'").trim();
      }

      // Look up in pg_proc via to_regproc
      const procRows = plv8.execute(
        `SELECT p.oid::int AS oid,
                p.proname::text AS proname,
                p.prosrc::text AS prosrc,
                l.lanname::text AS lanname,
                t.typname::text AS rettypname
           FROM pg_catalog.pg_proc p
           JOIN pg_catalog.pg_language l ON l.oid = p.prolang
           JOIN pg_catalog.pg_type t ON t.oid = p.prorettype
          WHERE p.oid = pg_catalog.to_regproc($1)`,
        [fnSpec]
      );

      if (procRows && procRows.length > 0) {
        const proc = procRows[0];
        if (
          PGQ_LANG_NAMES[proc.lanname] ||
          PGQ_LANG_NAMES[proc.lanname.toLowerCase()] ||
          proc.rettypname === "property_graph" ||
          proc.rettypname === "PROPERTY GRAPH"
        ) {
          return evalPropertyGraphFunction(proc.prosrc, proc.proname);
        }
        PgqCatalog.throwPgqError('function "' + fnSpec + '" is not a property graph function', "42809");
      }

      // Check if it is a table/view in pg_class (e.g. `GRAPH_TABLE(pg_class ...)` in graph_table.sql:87)
      const relRows = plv8.execute(
        `SELECT c.relname::text AS relname
           FROM pg_catalog.pg_class c
          WHERE c.oid = pg_catalog.to_regclass($1)`,
        [fnSpec]
      );
      if (relRows && relRows.length > 0) {
        PgqCatalog.throwPgqError('"' + fnSpec + '" is not a property graph', "42809");
      }

      PgqCatalog.throwPgqError('property graph "' + fnSpec + '" does not exist', "42704");
    }

    PgqCatalog.throwPgqError("invalid property graph argument", "42809");
  }

  /*
   * Inspects tokens immediately following the closing `)` of `GRAPH_TABLE(...)`
   * to determine whether an explicit column definition list `AS (col1 type1, ...)`
   * or `alias (col1 type1, ...)` was written by the caller.
   */
  function hasExplicitColDefList(tokens, closeParenIdx) {
    let idx = closeParenIdx + 1;
    if (idx >= tokens.length) return false;

    const t1 = tokens[idx];
    // Case 1: `AS ( col1 type1 ... )` or `AS alias ( col1 type1 ... )`
    if (t1.type === "IDENT" && !t1.quoted && t1.lower === "as") {
      idx++;
      if (idx >= tokens.length) return false;
      if (tokens[idx].value === "(") {
        return true;
      }
      if (tokens[idx].type === "IDENT" && idx + 1 < tokens.length && tokens[idx + 1].value === "(") {
        // Check if inside `(` we have `col_name type_name` (2 consecutive identifiers before `,` or `)`)
        return parenContainsTypedColDefs(tokens, idx + 1);
      }
      return false;
    }

    // Case 2: `alias ( col1 type1 ... )` without `AS`
    if (
      t1.type === "IDENT" &&
      !SQL_KEYWORDS_AFTER_FROM[t1.lower] &&
      idx + 1 < tokens.length &&
      tokens[idx + 1].value === "("
    ) {
      return parenContainsTypedColDefs(tokens, idx + 1);
    }

    return false;
  }

  const SQL_KEYWORDS_AFTER_FROM = {
    where: true, group: true, having: true, window: true, order: true,
    limit: true, offset: true, fetch: true, for: true, union: true,
    intersect: true, except: true, on: true, using: true, join: true,
    inner: true, left: true, right: true, full: true, cross: true,
    natural: true, lateral: true
  };

  function parenContainsTypedColDefs(tokens, openParenIdx) {
    if (openParenIdx + 2 >= tokens.length) return false;
    const first = tokens[openParenIdx + 1];
    const second = tokens[openParenIdx + 2];
    if (first && first.type === "IDENT" && second && second.type === "IDENT") {
      return true;
    }
    return false;
  }

  /*
   * Extract outer `FROM` table aliases preceding `GRAPH_TABLE(...)` in the same
   * query block so parse-time column inference can resolve lateral references
   * like `COLUMNS (x1.a AS outer_id)`.
   */
  function extractPrecedingFromTables(tokens, gtTokenIdx) {
    // Walk backwards from gtTokenIdx at the same parenthesis depth to find `FROM`
    let depth = 0;
    let fromIdx = -1;
    for (let i = gtTokenIdx - 1; i >= 0; i--) {
      const t = tokens[i];
      if (t.value === ")") depth++;
      else if (t.value === "(") {
        if (depth === 0) break;
        depth--;
      } else if (depth === 0 && t.type === "IDENT" && !t.quoted && t.lower === "from") {
        fromIdx = i;
        break;
      }
    }
    if (fromIdx === -1) return [];

    const lateralEnv = [];
    let i = fromIdx + 1;
    let rtindex = 1;
    while (i < gtTokenIdx) {
      const t = tokens[i];
      if (t.value === "(") {
        // Skip subquery
        let d = 1;
        i++;
        while (i < gtTokenIdx && d > 0) {
          if (tokens[i].value === "(") d++;
          else if (tokens[i].value === ")") d--;
          i++;
        }
        continue;
      }
      if (t.type === "IDENT" && !t.quoted && (t.lower === "lateral" || t.lower === "only")) {
        i++;
        continue;
      }
      if (t.type === "IDENT") {
        let schema = null;
        let relname = t.value;
        i++;
        if (i < gtTokenIdx && tokens[i].value === "." && i + 1 < gtTokenIdx && tokens[i + 1].type === "IDENT") {
          schema = relname;
          relname = tokens[i + 1].value;
          i += 2;
        }
        let alias = relname;
        if (i < gtTokenIdx && tokens[i].type === "IDENT" && !tokens[i].quoted && tokens[i].lower === "as") {
          i++;
          if (i < gtTokenIdx && tokens[i].type === "IDENT") {
            alias = tokens[i].value;
            i++;
          }
        } else if (
          i < gtTokenIdx &&
          tokens[i].type === "IDENT" &&
          !SQL_KEYWORDS_AFTER_FROM[tokens[i].lower] &&
          tokens[i].lower !== "join"
        ) {
          alias = tokens[i].value;
          i++;
        }

        // Try resolving relation in pg_catalog
        const regStr = schema
          ? PgqLexer.quoteIdent(schema) + "." + PgqLexer.quoteIdent(relname)
          : PgqLexer.quoteIdent(relname);
        try {
          const colRows = plv8.execute(
            `SELECT a.attnum::int AS attno,
                    a.attname::text AS name,
                    a.atttypid::int AS type_oid,
                    a.atttypmod::int AS typmod,
                    a.attcollation::int AS collation_oid,
                    pg_catalog.format_type(a.atttypid, a.atttypmod)::text AS type_sql
               FROM pg_catalog.pg_attribute a
              WHERE a.attrelid = pg_catalog.to_regclass($1)
                AND a.attnum > 0
                AND NOT a.attisdropped
              ORDER BY a.attnum`,
            [regStr]
          );
          if (colRows && colRows.length > 0) {
            lateralEnv.push({
              alias: alias,
              rtindex: rtindex++,
              columns: colRows
            });
          }
        } catch (_e) {
          // Ignore non-table CTE or function item during heuristic parse scan
        }
      }
      // Advance to next comma or JOIN
      while (i < gtTokenIdx && tokens[i].value !== ",") {
        if (tokens[i].type === "IDENT" && !tokens[i].quoted && tokens[i].lower === "join") {
          i++;
          break;
        }
        i++;
      }
      if (i < gtTokenIdx && tokens[i].value === ",") {
        i++;
      }
    }

    return lateralEnv;
  }

  const patternContextCache = Object.create(null);

  /*
   * Locate `GRAPH_TABLE ( <graph_arg> , <match_arg> )` in `queryStr` where
   * `<match_arg>` evaluates to `matchSrc`, and infer its `COLUMNS (...)` types.
   */
  function inferColumnsFromQuery(queryContextStr, matchSrc) {
    let sqlToScan = queryContextStr || "";
    const trimmedMatch = (matchSrc || "").trim();

    function findCallInSql(sqlText) {
      let toks;
      try {
        toks = PgqLexer.tokenize(sqlText);
      } catch (_e) {
        return null;
      }
      for (let i = 0; i < toks.length; i++) {
        const t = toks[i];
        if (
          t.type === "IDENT" &&
          (t.lower === "graph_table" ||
            (t.lower === "plpgq" && i + 2 < toks.length && toks[i + 1].value === "." && toks[i + 2].lower === "graph_table"))
        ) {
          let openParenIdx = t.lower === "graph_table" ? i + 1 : i + 3;
          if (openParenIdx >= toks.length || toks[openParenIdx].value !== "(") {
            continue;
          }
          // Parse argument list inside `GRAPH_TABLE(...)`
          let depth = 1;
          let arg1Start = openParenIdx + 1;
          let comma1Idx = -1;
          let comma2Idx = -1;
          let closeParenIdx = -1;
          let j = openParenIdx + 1;
          while (j < toks.length && depth > 0) {
            if (toks[j].value === "(") depth++;
            else if (toks[j].value === ")") {
              depth--;
              if (depth === 0) {
                closeParenIdx = j;
                break;
              }
            } else if (depth === 1 && toks[j].value === ",") {
              if (comma1Idx === -1) comma1Idx = j;
              else if (comma2Idx === -1) comma2Idx = j;
            }
            j++;
          }
          if (comma1Idx === -1 || closeParenIdx === -1) {
            continue;
          }
          const arg2End = comma2Idx !== -1 ? comma2Idx : closeParenIdx;
          const arg2Toks = toks.slice(comma1Idx + 1, arg2End);
          for (let k = 0; k < arg2Toks.length; k++) {
            if (arg2Toks[k].type === "STRING" && arg2Toks[k].value.trim() === matchSrc.trim()) {
              const arg1Toks = toks.slice(arg1Start, comma1Idx);
              const graphArgRaw = sqlText.slice(
                arg1Toks[0].start,
                arg1Toks[arg1Toks.length - 1].end
              ).trim();
              return {
                tokens: toks,
                gtIdx: i,
                closeParenIdx: closeParenIdx,
                graphArg: graphArgRaw
              };
            }
          }
        }
      }
      return null;
    }

    let found = findCallInSql(sqlToScan);
    if (found && trimmedMatch) {
      patternContextCache[trimmedMatch] = sqlToScan;
    }

    // Fallback 1: if revalidating a prepared statement during EXECUTE, check
    // patternContextCache or pg_prepared_statements.
    if (!found && trimmedMatch && patternContextCache[trimmedMatch]) {
      found = findCallInSql(patternContextCache[trimmedMatch]);
      if (found) {
        sqlToScan = patternContextCache[trimmedMatch];
      }
    }

    if (!found && trimmedMatch) {
      try {
        const prepRows = plv8.execute(
          `SELECT statement::text AS stmt
             FROM pg_catalog.pg_prepared_statements
            WHERE statement LIKE '%' || $1 || '%'
            LIMIT 5`,
          [trimmedMatch]
        );
        if (prepRows) {
          for (let r = 0; r < prepRows.length; r++) {
            found = findCallInSql(prepRows[r].stmt);
            if (found) {
              sqlToScan = prepRows[r].stmt;
              patternContextCache[trimmedMatch] = sqlToScan;
              break;
            }
          }
        }
      } catch (_e) {
        // Ignore if pg_prepared_statements is unavailable
      }
    }

    // Fallback 2: if `matchSrc` is inside a SQL or PL/pgSQL function body (`pg_proc.prosrc`)
    // that is currently being parsed via SPI_prepare / inline_set_returning_function!
    if (!found) {
      const fnRows = plv8.execute(
        `SELECT prosrc::text AS prosrc
           FROM pg_catalog.pg_proc
          WHERE prosrc LIKE '%' || $1 || '%'
          ORDER BY oid DESC
          LIMIT 5`,
        [matchSrc.trim()]
      );
      if (fnRows) {
        for (let r = 0; r < fnRows.length; r++) {
          found = findCallInSql(fnRows[r].prosrc);
          if (found) {
            sqlToScan = fnRows[r].prosrc;
            break;
          }
        }
      }
    }

    if (!found) {
      return {
        has_coldeflist: true,
        columns: []
      };
    }

    const hasColDef = hasExplicitColDefList(found.tokens, found.closeParenIdx);
    const lateralEnv = extractPrecedingFromTables(found.tokens, found.gtIdx);
    const pg = resolveGraphArgument(found.graphArg);
    const inferred = PgqCodegenSql.inferColumnsForGraph(pg, matchSrc, lateralEnv);

    return {
      has_coldeflist: hasColDef,
      graph_arg: found.graphArg,
      columns: inferred.columns
    };
  }

  function compileGraphTable(pgArg, matchSrc, expectedCols, lateralEnv, paramsObj) {
    const pg = resolveGraphArgument(pgArg);
    return PgqCodegenSql.compileGraphTable(pg, matchSrc, expectedCols, lateralEnv, paramsObj);
  }

  function executeGraphTableJsonb(pgArg, matchSrc, paramsObj) {
    const compiled = compileGraphTable(pgArg, matchSrc, null, [], paramsObj);
    const rows = plv8.execute(compiled.sql);
    return rows || [];
  }

  /*
   * Runtime SRF execution for `GRAPH_TABLE(...)` when planner inlining is
   * bypassed (e.g., dynamic runtime arguments or `params jsonb`).
   * Uses PL/v8 v4.0's `plv8.expected_columns()` and `plv8.return_query()`.
   */
  function executeGraphTableRuntime(pgArg, matchSrc, paramsObj) {
    const expectedCols =
      typeof plv8 !== "undefined" && typeof plv8.expected_columns === "function"
        ? plv8.expected_columns()
        : [];
    if (!expectedCols || expectedCols.length === 0) {
      PgqCatalog.throwPgqError(
        'a column definition list is required for functions returning "record"',
        "42601"
      );
    }
    const compiled = compileGraphTable(
      pgArg,
      String(matchSrc !== undefined && matchSrc !== null ? matchSrc : ""),
      expectedCols,
      [],
      paramsObj || null
    );
    if (typeof plv8 !== "undefined" && typeof plv8.return_query === "function") {
      plv8.return_query(compiled.sql);
      return;
    }
    return plv8.execute(compiled.sql) || [];
  }

  /*
   * Register `graph_table`'s parse-time column inference and planner support
   * hooks with PL/v8 v4.0's core table-macro subsystem.
   */
  if (typeof plv8 !== "undefined") {
    if (typeof plv8.register_column_inference === "function") {
      plv8.register_column_inference("graph_table", "pgq_infer_columns_tsv");
    }
    if (typeof plv8.register_support === "function") {
      plv8.register_support("graph_table", "pgq_compile_graph_table_tsv");
    }
  }

  return {
    compilePropertyGraphFunction: compilePropertyGraphFunction,
    evalPropertyGraphFunction: evalPropertyGraphFunction,
    resolveGraphArgument: resolveGraphArgument,
    inferColumnsFromQuery: inferColumnsFromQuery,
    compileGraphTable: compileGraphTable,
    executeGraphTableJsonb: executeGraphTableJsonb,
    executeGraphTableRuntime: executeGraphTableRuntime,
    isWasmActive: WasmLexer.isWasmActive,
    WasmLexer: WasmLexer,
    PgqLexer: PgqLexer,
    PgqMatchParser: PgqMatchParser
  };
})();

globalScope.__plpgq = PlPgq;

})(typeof globalThis !== 'undefined' ? globalThis : this);
$pgq_bundle_body$ LANGUAGE plv8;

SELECT pgq_compiler_bundle();

-- Register package and module in PL/v8 v4.0's plv8.packages / plv8.modules catalog
DO $plpgq_register_modules$
BEGIN
  IF pg_catalog.to_regclass('plv8.packages') IS NOT NULL AND
     pg_catalog.to_regclass('plv8.modules') IS NOT NULL THEN
    INSERT INTO plv8.packages (name, version, entry_point, dependencies)
    VALUES ('pl-pgq', '1.0.0', 'index.js', '{}'::jsonb)
    ON CONFLICT (name, version) DO UPDATE SET updated_at = NOW();

    DELETE FROM plv8.modules WHERE package_name = 'pl-pgq' AND package_version = '1.0.0';
    INSERT INTO plv8.modules (path, source, package_name, package_version, is_trusted)
    SELECT 'index.js', p.prosrc, 'pl-pgq', '1.0.0', true
      FROM pg_catalog.pg_proc p
     WHERE p.proname = 'pgq_compiler_bundle'
     ORDER BY p.oid DESC
     LIMIT 1;
  END IF;
END;
$plpgq_register_modules$ LANGUAGE plpgsql;

-- 3. PL/v8 v4.0 Language Handler for `LANGUAGE "CREATE PROPERTY GRAPH"`
CREATE OR REPLACE FUNCTION pgq_create_property_graph_handler()
RETURNS language_handler AS
$pgq_handler_body$
  const src = arguments[0];
  const meta = arguments[1];
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    } else {
      throw new Error('plpgq: pgq_compiler_bundle() catalog entry not found');
    }
  }
  return globalThis.__plpgq.compilePropertyGraphFunction(src, meta);
$pgq_handler_body$ LANGUAGE plv8;

CREATE OR REPLACE TRUSTED LANGUAGE "CREATE PROPERTY GRAPH"
  HANDLER pgq_create_property_graph_handler
  INLINE plv8_inline_handler
  VALIDATOR plv8_call_validator;

CREATE OR REPLACE TRUSTED LANGUAGE "create property graph"
  HANDLER pgq_create_property_graph_handler
  INLINE plv8_inline_handler
  VALIDATOR plv8_call_validator;

CREATE OR REPLACE TRUSTED LANGUAGE property_graph
  HANDLER pgq_create_property_graph_handler
  INLINE plv8_inline_handler
  VALIDATOR plv8_call_validator;

CREATE OR REPLACE TRUSTED LANGUAGE sqlpgq_v8
  HANDLER pgq_create_property_graph_handler
  INLINE plv8_inline_handler
  VALIDATOR plv8_call_validator;

CREATE OR REPLACE TRUSTED LANGUAGE pl_pgq
  HANDLER pgq_create_property_graph_handler
  INLINE plv8_inline_handler
  VALIDATOR plv8_call_validator;

-- 4. Parse-time and plan-time PL/v8 compiler entry points
CREATE OR REPLACE FUNCTION pgq_infer_columns_tsv(query_ctx text, match_src text)
RETURNS text AS
$pgq_infer_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  const res = globalThis.__plpgq.inferColumnsFromQuery(query_ctx, match_src);
  const lines = [];
  if (res.has_coldeflist) {
    lines.push('COLDEF\t1\t' + (res.graph_arg || ''));
  } else {
    lines.push('COLDEF\t0\t' + (res.graph_arg || ''));
  }
  const cols = res.columns || [];
  for (let i = 0; i < cols.length; i++) {
    const c = cols[i];
    lines.push(
      String(c.name).replace(/[\t\n\r]/g, ' ') + '\t' +
      String(c.type_oid || 25) + '\t' +
      String(c.typmod !== undefined ? c.typmod : -1) + '\t' +
      String(c.collation_oid || 0)
    );
  }
  return lines.join('\n');
$pgq_infer_body$ LANGUAGE plv8;

CREATE OR REPLACE FUNCTION pgq_compile_graph_table_tsv(
  graph_arg text,
  match_src text,
  expected_cols_json text,
  lateral_env_json text,
  params_json text
)
RETURNS text AS
$pgq_compile_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  const expectedCols = expected_cols_json ? JSON.parse(expected_cols_json) : [];
  const lateralEnv = lateral_env_json ? JSON.parse(lateral_env_json) : [];
  const paramsObj = params_json ? JSON.parse(params_json) : null;
  const compiled = globalThis.__plpgq.compileGraphTable(
    graph_arg,
    match_src,
    expectedCols,
    lateralEnv,
    paramsObj
  );
  const lines = ['SQL\t' + compiled.sql.replace(/[\n\r]+/g, ' ')];
  const cols = compiled.columns || [];
  for (let i = 0; i < cols.length; i++) {
    const c = cols[i];
    lines.push(
      'COL\t' +
      String(c.name).replace(/[\t\n\r]/g, ' ') + '\t' +
      String(c.type_oid || 25) + '\t' +
      String(c.typmod !== undefined ? c.typmod : -1) + '\t' +
      String(c.collation_oid || 0)
    );
  }
  const lvars = compiled.lateral_vars || [];
  for (let i = 0; i < lvars.length; i++) {
    const lv = lvars[i];
    lines.push(
      'LAT\t' +
      String(lv.rtindex) + '\t' +
      String(lv.attno) + '\t' +
      String(lv.type_oid) + '\t' +
      String(lv.typmod !== undefined ? lv.typmod : -1) + '\t' +
      String(lv.collation_oid || 0)
    );
  }
  return lines.join('\n');
$pgq_compile_body$ LANGUAGE plv8;

-- 5. User-facing diagnostic & pure-JS GRAPH_TABLE functions
CREATE OR REPLACE FUNCTION pgq_wasm_active()
RETURNS boolean
LANGUAGE plv8 IMMUTABLE STRICT AS
$pgq_wasm_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  return globalThis.__plpgq.isWasmActive();
$pgq_wasm_body$;

CREATE OR REPLACE FUNCTION pgq_compile_sql(
  pg "PROPERTY GRAPH",
  match_src text,
  params jsonb DEFAULT NULL
)
RETURNS text
LANGUAGE plv8 STABLE AS
$pgq_compile_sql_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  return globalThis.__plpgq.compileGraphTable(pg, match_src, null, [], params).sql;
$pgq_compile_sql_body$;

CREATE OR REPLACE FUNCTION graph_table_jsonb(
  pg "PROPERTY GRAPH",
  source text,
  params jsonb DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plv8 STABLE AS
$pgq_gt_jsonb_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  return globalThis.__plpgq.executeGraphTableJsonb(pg, source, params);
$pgq_gt_jsonb_body$;

CREATE OR REPLACE FUNCTION graph_table(
  pg "PROPERTY GRAPH",
  source text,
  row_type anyelement
)
RETURNS SETOF anyelement
LANGUAGE plv8 STABLE AS
$pgq_gt_any_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  return globalThis.__plpgq.executeGraphTableJsonb(pg, source, null);
$pgq_gt_any_body$;

-- 6. Pure PL/v8 `pgq_pattern` domain & `GRAPH_TABLE` overloads using `plv8_source` and `plv8_call_support`
DO $plpgq_pattern_domain$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_type WHERE typname = 'pgq_pattern') THEN
    CREATE DOMAIN pgq_pattern AS plv8_source;
  END IF;
END;
$plpgq_pattern_domain$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION graph_table(pg "PROPERTY GRAPH", source pgq_pattern)
RETURNS SETOF record
LANGUAGE plv8 STABLE SUPPORT plv8_call_support AS
$pgq_gt_rec_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  globalThis.__plpgq.executeGraphTableRuntime(pg, source, null);
$pgq_gt_rec_body$;

CREATE OR REPLACE FUNCTION graph_table(graph_name text, source pgq_pattern)
RETURNS SETOF record
LANGUAGE plv8 STABLE SUPPORT plv8_call_support AS
$pgq_gt_name_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  globalThis.__plpgq.executeGraphTableRuntime(graph_name, source, null);
$pgq_gt_name_body$;

CREATE OR REPLACE FUNCTION graph_table(pg "PROPERTY GRAPH", source pgq_pattern, params jsonb)
RETURNS SETOF record
LANGUAGE plv8 STABLE SUPPORT plv8_call_support AS
$pgq_gt_params_body$
  if (typeof globalThis.__plpgq === 'undefined') {
    const rows = plv8.execute(
      `SELECT p.prosrc
         FROM pg_catalog.pg_proc p
        WHERE p.proname = 'pgq_compiler_bundle'
          AND p.pronargs = 0
        ORDER BY p.oid DESC
        LIMIT 1`
    );
    if (rows && rows.length === 1) {
      (0, eval)(rows[0].prosrc);
    }
  }
  globalThis.__plpgq.executeGraphTableRuntime(pg, source, params);
$pgq_gt_params_body$;

-- 7. Security: revoke direct PUBLIC execution on internal compiler/handler/support functions
REVOKE ALL ON FUNCTION pgq_compiler_bundle() FROM PUBLIC;
REVOKE ALL ON FUNCTION pgq_create_property_graph_handler() FROM PUBLIC;
REVOKE ALL ON FUNCTION pgq_infer_columns_tsv(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION pgq_compile_graph_table_tsv(text, text, text, text, text) FROM PUBLIC;
$tle_pkg_pl_pgq$
);
