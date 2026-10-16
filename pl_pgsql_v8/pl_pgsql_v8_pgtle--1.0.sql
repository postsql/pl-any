-- Register pl_pgsql_v8 as a Trusted Language Extension (pg_tle)
-- Prerequisite: CREATE EXTENSION IF NOT EXISTS pg_tle;

SELECT pgtle.install_extension(
  'pl_pgsql_v8',
  '1.0',
  'PL/pgSQL compiled to JavaScript on V8 (pl_pgsql_v8 / plpgsql_v8 / pl/pgsql+v8)',
$tle_pkg_pl_pgsql_v8$
CREATE OR REPLACE FUNCTION plv8_plpgsql_handler()
RETURNS language_handler AS
$plpgsql_v8_Compiler$
if (typeof globalThis.__plpgsql_v8_compile !== 'function') {
  globalThis.__plpgsql_v8_compile = (function() {
    const COND_MAP = {
      successful_completion: '00000',
      warning: '01',
      no_data: '02',
      sql_statement_not_yet_complete: '03000',
      connection_exception: '08',
      triggered_action_exception: '09000',
      feature_not_supported: '0A000',
      invalid_transaction_initiation: '0B000',
      locator_exception: '0F000',
      invalid_grantor: '0L000',
      invalid_role_specification: '0P000',
      diagnostics_exception: '0Z',
      stacked_diagnostics_accessed_without_active_handler: '0Z002',
      case_not_found: '20000',
      cardinality_violation: '21000',
      data_exception: '22',
      array_subscript_error: '2202E',
      character_not_in_repertoire: '22021',
      datetime_field_overflow: '22008',
      division_by_zero: '22012',
      error_in_assignment: '22005',
      escape_character_conflict: '2200B',
      indicator_overflow: '22022',
      interval_field_overflow: '22015',
      invalid_argument_for_logarithm: '2201E',
      invalid_argument_for_ntile_function: '22014',
      invalid_argument_for_nth_value_function: '22016',
      invalid_argument_for_power_function: '2201F',
      invalid_argument_for_width_bucket_function: '2201G',
      invalid_character_value_for_cast: '22018',
      invalid_datetime_format: '22007',
      invalid_escape_character: '22019',
      invalid_escape_octet: '2200D',
      invalid_escape_sequence: '22025',
      nonstandard_use_of_escape_character: '22P06',
      invalid_indicator_parameter_value: '22010',
      invalid_parameter_value: '22023',
      invalid_preceding_or_following_size: '22013',
      invalid_regular_expression: '2201B',
      invalid_row_count_in_limit_clause: '2201W',
      invalid_row_count_in_result_offset_clause: '2201X',
      invalid_tablesample_argument: '2202H',
      invalid_tablesample_repeat: '2202G',
      invalid_time_zone_displacement_value: '22009',
      invalid_use_of_escape_character: '2200C',
      most_specific_type_mismatch: '2200G',
      null_value_not_allowed: '22004',
      null_value_no_indicator_parameter: '22002',
      numeric_value_out_of_range: '22003',
      sequence_generator_limit_exceeded: '2200H',
      string_data_length_mismatch: '22026',
      string_data_right_truncation: '22001',
      substring_error: '22011',
      trim_error: '22027',
      unterminated_c_string: '22024',
      zero_length_character_string: '2200F',
      floating_point_exception: '22P01',
      invalid_text_representation: '22P02',
      invalid_binary_representation: '22P03',
      bad_copy_file_format: '22P04',
      untranslatable_character: '22P05',
      not_an_xml_document: '2200L',
      invalid_xml_document: '2200M',
      invalid_xml_content: '2200N',
      invalid_xml_comment: '2200S',
      invalid_xml_processing_instruction: '2200T',
      duplicate_json_object_key_value: '22030',
      invalid_argument_for_sql_json_datetime_function: '22031',
      invalid_json_text: '22032',
      invalid_sql_json_subscript: '22033',
      more_than_one_sql_json_item: '22034',
      no_sql_json_item: '22035',
      non_numeric_sql_json_item: '22036',
      non_unique_keys_in_a_json_object: '22037',
      singleton_sql_json_item_required: '22038',
      sql_json_array_not_found: '22039',
      sql_json_member_not_found: '2203A',
      sql_json_number_not_found: '2203B',
      sql_json_object_not_found: '2203C',
      too_many_json_array_elements: '2203D',
      too_many_json_object_members: '2203E',
      sql_json_scalar_required: '2203F',
      integrity_constraint_violation: '23',
      restrict_violation: '23001',
      not_null_violation: '23502',
      foreign_key_violation: '23503',
      unique_violation: '23505',
      check_violation: '23514',
      exclusion_violation: '23P01',
      invalid_cursor_state: '24000',
      invalid_transaction_state: '25',
      active_sql_transaction: '25001',
      branch_transaction_already_active: '25002',
      held_cursor_requires_same_isolation_level: '25008',
      inappropriate_access_mode_for_branch_transaction: '25003',
      inappropriate_isolation_level_for_branch_transaction: '25004',
      no_active_sql_transaction_for_branch_transaction: '25005',
      read_only_sql_transaction: '25006',
      schema_and_data_statement_mixing_not_supported: '25007',
      no_active_sql_transaction: '25P01',
      in_failed_sql_transaction: '25P02',
      idle_in_transaction_session_timeout: '25P03',
      invalid_sql_statement_name: '26000',
      triggered_data_change_violation: '27000',
      invalid_authorization_specification: '28000',
      invalid_password: '28P01',
      dependent_privilege_descriptors_still_exist: '2B000',
      dependent_objects_still_exist: '2BP01',
      invalid_transaction_termination: '2D000',
      sql_routine_exception: '2F',
      function_executed_no_return_statement: '2F005',
      modifying_sql_data_not_permitted: '2F002',
      prohibited_sql_statement_attempted: '2F003',
      reading_sql_data_not_permitted: '2F004',
      invalid_cursor_name: '34000',
      external_routine_exception: '38',
      containing_sql_not_permitted: '38001',
      modifying_sql_data_not_permitted_ext: '38002',
      prohibited_sql_statement_attempted_ext: '38003',
      reading_sql_data_not_permitted_ext: '38004',
      external_routine_invocation_exception: '39',
      invalid_sqlstate_returned: '39001',
      null_value_not_allowed_ext: '39004',
      trigger_protocol_violated: '39P01',
      srf_protocol_violated: '39P02',
      event_trigger_protocol_violated: '39P03',
      savepoint_exception: '3B000',
      invalid_savepoint_specification: '3B001',
      invalid_catalog_name: '3D000',
      invalid_schema_name: '3F000',
      transaction_rollback: '40',
      transaction_integrity_constraint_violation: '40002',
      serialization_failure: '40001',
      statement_completion_unknown: '40003',
      deadlock_detected: '40P01',
      syntax_error_or_access_rule_violation: '42',
      syntax_error: '42601',
      insufficient_privilege: '42501',
      cannot_coerce: '42846',
      grouping_error: '42803',
      windowing_error: '42P20',
      invalid_recursion: '42P19',
      invalid_foreign_key: '42830',
      invalid_name: '42602',
      name_too_long: '42622',
      reserved_name: '42939',
      datatype_mismatch: '42804',
      indeterminate_datatype: '42P18',
      collation_mismatch: '42P21',
      indeterminate_collation: '42P22',
      wrong_object_type: '42809',
      generated_always: '428C9',
      undefined_column: '42703',
      undefined_function: '42883',
      undefined_table: '42P01',
      undefined_parameter: '42P02',
      undefined_object: '42704',
      duplicate_column: '42701',
      duplicate_cursor: '42P03',
      duplicate_database: '42P04',
      duplicate_function: '42723',
      duplicate_prepared_statement: '42P05',
      duplicate_schema: '42P06',
      duplicate_table: '42P07',
      duplicate_alias: '42712',
      duplicate_object: '42710',
      ambiguous_column: '42702',
      ambiguous_function: '42725',
      ambiguous_parameter: '42P08',
      ambiguous_alias: '42P09',
      invalid_column_reference: '42P10',
      invalid_column_definition: '42611',
      invalid_cursor_definition: '42P11',
      invalid_database_definition: '42P12',
      invalid_function_definition: '42P13',
      invalid_prepared_statement_definition: '42P14',
      invalid_schema_definition: '42P15',
      invalid_table_definition: '42P16',
      invalid_object_definition: '42P17',
      with_check_option_violation: '44000',
      insufficient_resources: '53',
      disk_full: '53100',
      out_of_memory: '53200',
      too_many_connections: '53300',
      configuration_limit_exceeded: '53400',
      program_limit_exceeded: '54',
      statement_too_complex: '54001',
      too_many_columns: '54011',
      too_many_arguments: '54023',
      object_not_in_prerequisite_state: '55000',
      object_in_use: '55006',
      cant_change_runtime_param: '55P02',
      lock_not_available: '55P03',
      unsafe_new_enum_value_usage: '55P04',
      operator_intervention: '57',
      query_canceled: '57014',
      admin_shutdown: '57P01',
      crash_shutdown: '57P02',
      cannot_connect_now: '57P03',
      database_dropped: '57P04',
      idle_session_timeout: '57P05',
      system_error: '58',
      io_error: '58030',
      undefined_file: '58P01',
      duplicate_file: '58P02',
      snapshot_too_old: '72000',
      config_file_error: 'F0000',
      lock_file_exists: 'F0001',
      fdw_error: 'HV000',
      plpgsql_error: 'P0000',
      raise_exception: 'P0001',
      no_data_found: 'P0002',
      too_many_rows: 'P0003',
      assert_failure: 'P0004',
      internal_error: 'XX000',
      data_corrupted: 'XX001',
      index_corrupted: 'XX002'
    };

    function ensureRuntime() {
      if (globalThis.__plpgsql_v8_rt) return globalThis.__plpgsql_v8_rt;
      const rt = {
        COND_MAP: COND_MAP,
        pg: function() {
          return (typeof plv8 !== 'undefined') ? plv8 : pljs;
        },
        resolveCode: function(codeOrCond) {
          if (!codeOrCond) return 'P0001';
          const s = String(codeOrCond).trim();
          const low = s.toLowerCase();
          if (COND_MAP[low]) {
            return COND_MAP[low].length === 2 ? (COND_MAP[low] + '000') : COND_MAP[low];
          }
          if (/^[0-9A-Za-z]{5}$/.test(s)) return s.toUpperCase();
          return 'P0001';
        },
        makeError: function(codeOrCond, msg, opts) {
          let code = rt.resolveCode(codeOrCond);
          if (opts && opts.errcode) {
            code = rt.resolveCode(opts.errcode);
          }
          const finalMsg = (opts && opts.message !== undefined && opts.message !== null)
            ? String(opts.message)
            : (msg !== undefined && msg !== null ? String(msg) : String(codeOrCond || code));
          const err = new Error(finalMsg);
          err.sqlerrcode = code;
          err.code = code;
          if (opts) {
            if (opts.detail !== undefined && opts.detail !== null) err.detail = String(opts.detail);
            if (opts.hint !== undefined && opts.hint !== null) err.hint = String(opts.hint);
            if (opts.schema !== undefined && opts.schema !== null) err.schema_name = String(opts.schema);
            if (opts.table !== undefined && opts.table !== null) err.table_name = String(opts.table);
            if (opts.column !== undefined && opts.column !== null) err.column_name = String(opts.column);
            if (opts.datatype !== undefined && opts.datatype !== null) err.datatype_name = String(opts.datatype);
            if (opts.constraint !== undefined && opts.constraint !== null) err.constraint_name = String(opts.constraint);
          }
          return err;
        },
        formatRaise: function(fmt, args) {
          if (fmt === null || fmt === undefined) return '';
          const s = String(fmt);
          let idx = 0;
          let out = '';
          for (let i = 0; i < s.length; i++) {
            if (s[i] === '%') {
              if (i + 1 < s.length && s[i + 1] === '%') {
                out += '%';
                i++;
              } else {
                const v = (args && idx < args.length) ? args[idx++] : undefined;
                if (v === null || v === undefined) {
                  out += '<NULL>';
                } else if (typeof v === 'object' && !(v instanceof Date)) {
                  out += JSON.stringify(v, function(_, x) {
                    if (typeof x === 'bigint') {
                      return (x >= -9007199254740991n && x <= 9007199254740991n) ? Number(x) : x.toString();
                    }
                    return x;
                  });
                } else {
                  out += String(v);
                }
              }
            } else {
              out += s[i];
            }
          }
          return out;
        },
        doRaise: function(level, codeOrCond, fmt, args, opts) {
          const lvl = (level || 'EXCEPTION').toUpperCase();
          const msg = (fmt !== null && fmt !== undefined)
            ? rt.formatRaise(fmt, args || [])
            : ((opts && opts.message !== undefined && opts.message !== null) ? String(opts.message) : (codeOrCond || 'exception'));
          if (lvl === 'EXCEPTION') {
            throw rt.makeError(codeOrCond || 'P0001', msg, opts);
          }
          const pg = rt.pg();
          const lvlConst = (lvl === 'DEBUG') ? DEBUG1
            : (lvl === 'LOG') ? LOG
            : (lvl === 'INFO') ? INFO
            : (lvl === 'WARNING') ? WARNING
            : NOTICE;
          pg.elog(lvlConst, msg);
        },
        extractSqlState: function(err) {
          if (!err) return 'XX000';
          if (typeof err.sqlerrcode === 'string' && err.sqlerrcode.length === 5) {
            return err.sqlerrcode.toUpperCase();
          }
          if (typeof err.code === 'string' && err.code.length === 5) {
            return err.code.toUpperCase();
          }
          const msg = String(err.message || err);
          if (/division by zero/i.test(msg)) return '22012';
          if (/unique constraint|duplicate key/i.test(msg)) return '23505';
          if (/foreign key constraint/i.test(msg)) return '23503';
          if (/not-null constraint|null value in column/i.test(msg)) return '23502';
          if (/check constraint/i.test(msg)) return '23514';
          if (/out of range/i.test(msg)) return '22003';
          if (/invalid input syntax/i.test(msg)) return '22P02';
          if (/value too long/i.test(msg)) return '22001';
          if (/does not exist/i.test(msg)) {
            if (/relation/i.test(msg)) return '42P01';
            if (/column/i.test(msg)) return '42703';
            if (/function/i.test(msg)) return '42883';
          }
          if (/permission denied/i.test(msg)) return '42501';
          if (/syntax error/i.test(msg)) return '42601';
          return 'P0001';
        },
        matchException: function(err, conds) {
          const state = rt.extractSqlState(err);
          for (let i = 0; i < conds.length; i++) {
            const c = conds[i];
            if (c === 'OTHERS') return true;
            const low = c.toLowerCase();
            const mapped = COND_MAP[low] || c.toUpperCase();
            if (mapped.length === 2) {
              if (state.slice(0, 2) === mapped) return true;
              if (mapped === 'P0' && state.slice(0, 2) === 'P0') return true;
            } else if (mapped === 'P0000') {
              if (state.slice(0, 2) === 'P0') return true;
            } else if (state === mapped) {
              return true;
            }
          }
          return false;
        },
        toText: function(v) {
          if (v === null || v === undefined) return null;
          if (typeof v === 'boolean') return v ? 'true' : 'false';
          if (v instanceof Date) return v.toISOString();
          return String(v);
        },
        toBool: function(v) {
          if (v === null || v === undefined) return null;
          if (typeof v === 'boolean') return v;
          if (typeof v === 'number') return v !== 0;
          if (typeof v === 'bigint') return v !== 0n;
          if (typeof v === 'string') {
            const s = v.trim().toLowerCase();
            if (s === 't' || s === 'true' || s === 'yes' || s === 'y' || s === 'on' || s === '1') return true;
            if (s === 'f' || s === 'false' || s === 'no' || s === 'n' || s === 'off' || s === '0') return false;
            throw rt.makeError('22P02', 'invalid input syntax for type boolean: "' + v + '"');
          }
          return Boolean(v);
        },
        truthy: function(v) {
          if (v === null || v === undefined || v === false) return false;
          if (v === true) return true;
          return rt.toBool(v) === true;
        },
        and: function(a, b) {
          const ba = rt.toBool(a);
          const bb = rt.toBool(b);
          if (ba === false || bb === false) return false;
          if (ba === null || bb === null) return null;
          return true;
        },
        or: function(a, b) {
          const ba = rt.toBool(a);
          const bb = rt.toBool(b);
          if (ba === true || bb === true) return true;
          if (ba === null || bb === null) return null;
          return false;
        },
        not: function(a) {
          const ba = rt.toBool(a);
          return ba === null ? null : !ba;
        },
        normBigInt: function(bi) {
          if (bi < -9223372036854775808n || bi > 9223372036854775807n) {
            throw rt.makeError('22003', 'bigint out of range');
          }
          if (bi >= -2147483648n && bi <= 2147483647n) {
            const n = Number(bi);
            return n === 0 ? 0 : n;
          }
          return bi;
        },
        tryBigInt: function(v) {
          if (typeof v === 'bigint') return v;
          if (typeof v === 'number' && Number.isInteger(v)) return BigInt(v);
          if (typeof v === 'string') {
            const s = v.trim();
            if (/^[+-]?[0-9]+$/.test(s)) return BigInt(s);
          }
          return null;
        },
        toNum: function(v) {
          if (typeof v === 'number') return v;
          if (typeof v === 'bigint') return Number(v);
          if (typeof v === 'string') {
            const s = v.trim();
            if (s === '') throw rt.makeError('22P02', 'invalid input syntax for type numeric: ""');
            const n = Number(s);
            if (Number.isNaN(n) && s.toLowerCase() !== 'nan') {
              throw rt.makeError('22P02', 'invalid input syntax for type numeric: "' + v + '"');
            }
            return n;
          }
          return Number(v);
        },
        add: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          if (typeof a === 'bigint' || typeof b === 'bigint') {
            const ba = rt.tryBigInt(a), bb = rt.tryBigInt(b);
            if (ba !== null && bb !== null) return rt.normBigInt(ba + bb);
          }
          return rt.toNum(a) + rt.toNum(b);
        },
        sub: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          if (typeof a === 'bigint' || typeof b === 'bigint') {
            const ba = rt.tryBigInt(a), bb = rt.tryBigInt(b);
            if (ba !== null && bb !== null) return rt.normBigInt(ba - bb);
          }
          return rt.toNum(a) - rt.toNum(b);
        },
        mul: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          if (typeof a === 'bigint' || typeof b === 'bigint') {
            const ba = rt.tryBigInt(a), bb = rt.tryBigInt(b);
            if (ba !== null && bb !== null) return rt.normBigInt(ba * bb);
          }
          const r = rt.toNum(a) * rt.toNum(b);
          return r === 0 ? 0 : r;
        },
        div: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          const nb = rt.toNum(b);
          if (nb === 0) throw rt.makeError('22012', 'division by zero');
          return rt.toNum(a) / nb;
        },
        idiv: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          if (typeof a === 'bigint' || typeof b === 'bigint') {
            const ba = rt.tryBigInt(a), bb = rt.tryBigInt(b);
            if (ba !== null && bb !== null) {
              if (bb === 0n) throw rt.makeError('22012', 'division by zero');
              return rt.normBigInt(ba / bb);
            }
          }
          const nb = rt.toNum(b);
          if (nb === 0) throw rt.makeError('22012', 'division by zero');
          const r = Math.trunc(rt.toNum(a) / nb);
          return r === 0 ? 0 : r;
        },
        mod: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          if (typeof a === 'bigint' || typeof b === 'bigint') {
            const ba = rt.tryBigInt(a), bb = rt.tryBigInt(b);
            if (ba !== null && bb !== null) {
              if (bb === 0n) throw rt.makeError('22012', 'division by zero');
              return rt.normBigInt(ba % bb);
            }
          }
          const nb = rt.toNum(b);
          if (nb === 0) throw rt.makeError('22012', 'division by zero');
          const r = rt.toNum(a) % nb;
          return r === 0 ? 0 : r;
        },
        pow: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return Math.pow(rt.toNum(a), rt.toNum(b));
        },
        uplus: function(a) {
          if (a === null || a === undefined) return null;
          if (typeof a === 'bigint') return rt.normBigInt(a);
          return +rt.toNum(a);
        },
        uminus: function(a) {
          if (a === null || a === undefined) return null;
          if (typeof a === 'bigint') return rt.normBigInt(-a);
          const r = -rt.toNum(a);
          return r === 0 ? 0 : r;
        },
        concat: function(a, b) {
          if (Array.isArray(a) && Array.isArray(b)) return a.concat(b);
          if (Array.isArray(a)) return (b === null || b === undefined) ? a.slice() : a.concat([b]);
          if (Array.isArray(b)) return (a === null || a === undefined) ? b.slice() : [a].concat(b);
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.toText(a) + rt.toText(b);
        },
        cmpVal: function(a, b) {
          if (a instanceof Date && b instanceof Date) {
            return a.getTime() < b.getTime() ? -1 : (a.getTime() > b.getTime() ? 1 : 0);
          }
          if (Array.isArray(a) && Array.isArray(b)) {
            const len = Math.min(a.length, b.length);
            for (let i = 0; i < len; i++) {
              if (a[i] === null && b[i] === null) continue;
              if (a[i] === null) return 1;
              if (b[i] === null) return -1;
              const c = rt.cmpVal(a[i], b[i]);
              if (c !== 0) return c;
            }
            return a.length < b.length ? -1 : (a.length > b.length ? 1 : 0);
          }
          if (typeof a === 'bigint' || typeof b === 'bigint') {
            const ba = rt.tryBigInt(a), bb = rt.tryBigInt(b);
            if (ba !== null && bb !== null) {
              return ba < bb ? -1 : (ba > bb ? 1 : 0);
            }
            const na = Number(a), nb = Number(b);
            if (!Number.isNaN(na) && !Number.isNaN(nb)) {
              return na < nb ? -1 : (na > nb ? 1 : 0);
            }
          }
          if ((typeof a === 'number' && typeof b === 'string') || (typeof a === 'string' && typeof b === 'number')) {
            const na = Number(a), nb = Number(b);
            if (!Number.isNaN(na) && !Number.isNaN(nb)) {
              return na < nb ? -1 : (na > nb ? 1 : 0);
            }
          }
          return a < b ? -1 : (a > b ? 1 : (a === b ? 0 : NaN));
        },
        eq: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.cmpVal(a, b) === 0;
        },
        ne: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.cmpVal(a, b) !== 0;
        },
        lt: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.cmpVal(a, b) < 0;
        },
        le: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.cmpVal(a, b) <= 0;
        },
        gt: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.cmpVal(a, b) > 0;
        },
        ge: function(a, b) {
          if (a === null || a === undefined || b === null || b === undefined) return null;
          return rt.cmpVal(a, b) >= 0;
        },
        isDistinctFrom: function(a, b) {
          const na = (a === null || a === undefined);
          const nb = (b === null || b === undefined);
          if (na && nb) return false;
          if (na || nb) return true;
          return rt.cmpVal(a, b) !== 0;
        },
        between: function(v, lo, hi) {
          return rt.and(rt.ge(v, lo), rt.le(v, hi));
        },
        inList: function(v, list) {
          if (v === null || v === undefined) return null;
          let sawNull = false;
          for (let i = 0; i < list.length; i++) {
            const item = list[i];
            if (item === null || item === undefined) {
              sawNull = true;
            } else if (rt.eq(v, item) === true) {
              return true;
            }
          }
          return sawNull ? null : false;
        },
        like: function(s, pat, ilike) {
          if (s === null || s === undefined || pat === null || pat === undefined) return null;
          const p = String(pat);
          let rx = '^';
          for (let i = 0; i < p.length; i++) {
            const c = p[i];
            if (c === '\\' && i + 1 < p.length) {
              i++;
              rx += p[i].replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            } else if (c === '%') {
              rx += '[\\s\\S]*';
            } else if (c === '_') {
              rx += '[\\s\\S]';
            } else {
              rx += c.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
            }
          }
          rx += '$';
          const re = new RegExp(rx, ilike ? 'i' : '');
          return re.test(String(s));
        },
        coalesce: function(args) {
          for (let i = 0; i < args.length; i++) {
            if (args[i] !== null && args[i] !== undefined) return args[i];
          }
          return null;
        },
        nullif: function(a, b) {
          if (a === null || a === undefined) return null;
          if (b === null || b === undefined) return a;
          return rt.eq(a, b) === true ? null : a;
        },
        greatest: function(args) {
          let best = null;
          for (let i = 0; i < args.length; i++) {
            const v = args[i];
            if (v !== null && v !== undefined) {
              if (best === null || rt.gt(v, best) === true) best = v;
            }
          }
          return best;
        },
        least: function(args) {
          let best = null;
          for (let i = 0; i < args.length; i++) {
            const v = args[i];
            if (v !== null && v !== undefined) {
              if (best === null || rt.lt(v, best) === true) best = v;
            }
          }
          return best;
        },
        getElem: function(arr, idx) {
          if (arr === null || arr === undefined || idx === null || idx === undefined) return null;
          const i = Math.trunc(rt.toNum(idx));
          const v = arr.__zeroIndexed ? arr[i] : arr[i - 1];
          return v === undefined ? null : v;
        },
        getSlice: function(arr, lo, hi) {
          if (arr === null || arr === undefined || lo === null || lo === undefined || hi === null || hi === undefined) return null;
          const s = Math.max(1, Math.trunc(rt.toNum(lo)));
          const e = Math.trunc(rt.toNum(hi));
          if (e < s) return [];
          return arr.slice(s - 1, e);
        },
        setElem: function(arr, idx, val) {
          if (idx === null || idx === undefined) {
            throw rt.makeError('22004', 'array subscript in assignment must not be null');
          }
          const res = Array.isArray(arr) ? arr.slice() : [];
          const i = Math.trunc(rt.toNum(idx)) - 1;
          if (i < 0) {
            throw rt.makeError('2202E', 'array subscript out of range');
          }
          while (res.length < i) res.push(null);
          res[i] = (val === undefined ? null : val);
          return res;
        },
        setSlice: function(arr, lo, hi, val) {
          if (lo === null || lo === undefined || hi === null || hi === undefined) {
            throw rt.makeError('22004', 'array slice subscript in assignment must not be null');
          }
          const res = Array.isArray(arr) ? arr.slice() : [];
          const s = Math.trunc(rt.toNum(lo)) - 1;
          const e = Math.trunc(rt.toNum(hi)) - 1;
          if (s < 0 || e < s) {
            throw rt.makeError('2202E', 'array subscript out of range');
          }
          const src = Array.isArray(val) ? val : [];
          while (res.length <= e) res.push(null);
          for (let i = s; i <= e; i++) {
            res[i] = (i - s < src.length && src[i - s] !== undefined) ? src[i - s] : null;
          }
          return res;
        },
        setField: function(obj, field, val) {
          const res = (obj && typeof obj === 'object') ? Object.assign({}, obj) : {};
          res[field] = (val === undefined ? null : val);
          return res;
        },
        flattenForeach: function(arr, sliceDim) {
          if (arr === null || arr === undefined || !Array.isArray(arr)) return [];
          const dim = sliceDim ? Math.trunc(Number(sliceDim)) : 0;
          function getDepth(a) {
            if (!Array.isArray(a) || a.length === 0) return 1;
            return Array.isArray(a[0]) ? 1 + getDepth(a[0]) : 1;
          }
          const totalDepth = getDepth(arr);
          if (dim > totalDepth) {
            throw rt.makeError('2202E', 'slice dimension (' + dim + ') is out of range (0..' + totalDepth + ')');
          }
          const out = [];
          function walk(node, curDepth) {
            if (!Array.isArray(node)) {
              out.push(node === undefined ? null : node);
              return;
            }
            if (totalDepth - curDepth === dim) {
              out.push(node);
              return;
            }
            for (let i = 0; i < node.length; i++) {
              walk(node[i], curDepth + 1);
            }
          }
          if (dim === 0) {
            function flatScalars(node) {
              for (let i = 0; i < node.length; i++) {
                if (Array.isArray(node[i])) flatScalars(node[i]);
                else out.push(node[i] === undefined ? null : node[i]);
              }
            }
            flatScalars(arr);
          } else {
            walk(arr, 0);
          }
          return out;
        },
        coerce: function(val, sqlType, notNull, varName) {
          if (val === undefined) val = null;
          if (val === null) {
            if (notNull) {
              throw rt.makeError('22004', 'null value cannot be assigned to variable "' + (varName || '') + '" declared NOT NULL');
            }
            return null;
          }
          if (!sqlType) return val;
          const t = sqlType.toLowerCase().trim();
          if (t.endsWith('[]')) {
            if (Array.isArray(val)) {
              const baseElemType = t.replace(/(\[\])+$/, '').trim();
              return val.map(function(x) {
                return Array.isArray(x) ? rt.coerce(x, t, false, varName) : rt.coerce(x, baseElemType, false, varName);
              });
            }
            return val;
          }
          if (t === 'int' || t === 'int4' || t === 'integer' || t === 'serial') {
            const n = Math.round(rt.toNum(val));
            if (!Number.isFinite(n) || n < -2147483648 || n > 2147483647) {
              throw rt.makeError('22003', 'integer out of range');
            }
            return n === 0 ? 0 : n;
          }
          if (t === 'int2' || t === 'smallint' || t === 'smallserial') {
            const n = Math.round(rt.toNum(val));
            if (!Number.isFinite(n) || n < -32768 || n > 32767) {
              throw rt.makeError('22003', 'smallint out of range');
            }
            return n === 0 ? 0 : n;
          }
          if (t === 'int8' || t === 'bigint' || t === 'bigserial') {
            const bi = rt.tryBigInt(val);
            if (bi !== null) {
              return rt.normBigInt(bi);
            }
            const n = Math.round(rt.toNum(val));
            if (!Number.isFinite(n) || n < -9223372036854775808 || n >= 9223372036854775808) {
              throw rt.makeError('22003', 'bigint out of range');
            }
            return rt.normBigInt(BigInt(n));
          }
          if (t === 'oid') {
            const n = Math.round(rt.toNum(val));
            if (!Number.isFinite(n) || n < 0 || n > 4294967295) {
              throw rt.makeError('22003', 'OID out of range');
            }
            return n === 0 ? 0 : n;
          }
          if (t === 'float4' || t === 'float8' || t === 'real' || t === 'double precision' || t === 'numeric' || t === 'decimal' || t.startsWith('numeric(') || t.startsWith('decimal(')) {
            let n = rt.toNum(val);
            const m = t.match(/^(?:numeric|decimal)\s*\(\s*(\d+)\s*(?:,\s*(-?\d+))?\s*\)$/);
            if (m) {
              const scale = m[2] !== undefined ? parseInt(m[2], 10) : 0;
              const factor = Math.pow(10, scale);
              n = Math.round(n * factor) / factor;
            }
            return n === 0 ? 0 : n;
          }
          if (t === 'bool' || t === 'boolean') {
            return rt.toBool(val);
          }
          if (t === 'text' || t === 'varchar' || t === 'character varying' || t === 'char' || t === 'character' || t === 'bpchar' || t.startsWith('varchar(') || t.startsWith('character varying(') || t.startsWith('char(') || t.startsWith('character(')) {
            let s = rt.toText(val);
            const m = t.match(/\((\d+)\)$/);
            if (m) {
              const maxLen = parseInt(m[1], 10);
              if (s.length > maxLen) {
                if (s.slice(maxLen).trim().length > 0) {
                  throw rt.makeError('22001', 'value too long for type ' + sqlType);
                }
                s = s.slice(0, maxLen);
              }
            }
            return s;
          }
          if (t === 'json' || t === 'jsonb') {
            if (typeof val === 'string') {
              try {
                return JSON.parse(val);
              } catch (e) {
                throw rt.makeError('22P02', 'invalid input syntax for type json');
              }
            }
            return val;
          }
          return val;
        },
        evalSql: function(sql, params) {
          const rows = rt.pg().execute(sql, params || []);
          if (!rows || rows.length === 0) return null;
          const r = rows[0];
          if (r === null || r === undefined) return null;
          const keys = Object.keys(r);
          return keys.length > 0 ? r[keys[0]] : null;
        },
        returnNext: function(val, isScalar, outColNames) {
          const pg = rt.pg();
          if (isScalar && val !== null && val !== undefined && typeof val === 'object' && !Array.isArray(val) && !(val instanceof Date) && !ArrayBuffer.isView(val)) {
            const keys = Object.keys(val);
            pg.return_next(keys.length > 0 ? val[keys[0]] : null);
          } else if (!isScalar && outColNames && outColNames.length > 0 && val !== null && val !== undefined && typeof val === 'object' && !Array.isArray(val)) {
            const keys = Object.keys(val);
            const mapped = {};
            for (let i = 0; i < outColNames.length; i++) {
              const colName = outColNames[i];
              if (i < keys.length) {
                mapped[colName] = val[keys[i]];
              } else if (val[colName] !== undefined) {
                mapped[colName] = val[colName];
              } else {
                mapped[colName] = null;
              }
            }
            pg.return_next(mapped);
          } else {
            pg.return_next(val);
          }
        },
        returnQuery: function(sql, params, isScalar, outColNames) {
          if (sql === null || sql === undefined) {
            throw rt.makeError('22004', 'query string argument of EXECUTE is null');
          }
          const pg = rt.pg();
          if (typeof pg.return_query === 'function') {
            const n = pg.return_query(String(sql), params || []);
            return typeof n === 'number' ? n : 0;
          }
          const rows = pg.execute(String(sql), params || []) || [];
          for (let i = 0; i < rows.length; i++) {
            rt.returnNext(rows[i], isScalar, outColNames);
          }
          return rows.length;
        },
        openCursor: function(sql, params) {
          const pg = rt.pg();
          const plan = pg.prepare(sql);
          let portal;
          try {
            portal = plan.cursor(params || []);
          } catch (e) {
            try { plan.free(); } catch (_) {}
            throw e;
          }
          return { plan: plan, portal: portal, sql: sql };
        },
        fetchCursor: function(cur, mode, count) {
          if (!cur || !cur.portal) {
            throw rt.makeError('24000', 'cursor is not open');
          }
          const m = (mode || 'NEXT').toUpperCase();
          if (m === 'NEXT') {
            const row = cur.portal.fetch();
            return row === undefined ? null : row;
          }
          if (m === 'PRIOR') {
            const row = cur.portal.fetch(-1);
            if (Array.isArray(row)) return row.length > 0 ? row[0] : null;
            return row === undefined ? null : row;
          }
          if (m === 'FORWARD' || m === 'BACKWARD') {
            const dir = (m === 'BACKWARD') ? -1 : 1;
            const n = (count === 'ALL') ? 1000000 : (count !== undefined ? Math.trunc(Number(count)) : 1);
            if (n === 1 && dir === 1) {
              const row = cur.portal.fetch();
              return row === undefined ? null : row;
            }
            const rows = cur.portal.fetch(dir * n);
            if (!rows) return null;
            if (Array.isArray(rows)) return rows.length > 0 ? rows[rows.length - 1] : null;
            return rows;
          }
          if (m === 'RELATIVE') {
            const n = Math.trunc(Number(count));
            if (n === 1) {
              const row = cur.portal.fetch();
              return row === undefined ? null : row;
            }
            if (n === -1) {
              const row = cur.portal.fetch(-1);
              if (Array.isArray(row)) return row.length > 0 ? row[0] : null;
              return row === undefined ? null : row;
            }
            if (n > 1) cur.portal.move(n - 1);
            else if (n < -1) cur.portal.move(n + 1);
            else return null;
            const row = cur.portal.fetch(n > 0 ? 1 : -1);
            return Array.isArray(row) ? (row[0] || null) : (row || null);
          }
          const row = cur.portal.fetch();
          return row === undefined ? null : row;
        },
        moveCursor: function(cur, mode, count) {
          if (!cur || !cur.portal) {
            throw rt.makeError('24000', 'cursor is not open');
          }
          const m = (mode || 'NEXT').toUpperCase();
          let n = 1;
          if (m === 'PRIOR') n = -1;
          else if (m === 'BACKWARD') n = -(count !== undefined ? Math.trunc(Number(count)) : 1);
          else if (m === 'FORWARD' || m === 'RELATIVE') n = (count !== undefined ? Math.trunc(Number(count)) : 1);
          cur.portal.move(n);
          return true;
        },
        closeCursor: function(cur) {
          if (!cur || !cur.portal) {
            throw rt.makeError('24000', 'cursor is not open');
          }
          try {
            cur.portal.close();
          } finally {
            cur.portal = null;
            if (cur.plan) {
              try { cur.plan.free(); } catch (e) {}
              cur.plan = null;
            }
          }
        },
        callBuiltin: function(fnName, args) {
          switch (fnName) {
            case 'lower':
              return (args[0] === null || args[0] === undefined) ? null : String(args[0]).toLowerCase();
            case 'upper':
              return (args[0] === null || args[0] === undefined) ? null : String(args[0]).toUpperCase();
            case 'length':
            case 'char_length':
            case 'character_length':
              return (args[0] === null || args[0] === undefined) ? null : String(args[0]).length;
            case 'btrim':
            case 'trim':
              return (args[0] === null || args[0] === undefined) ? null : String(args[0]).trim();
            case 'ltrim':
              return (args[0] === null || args[0] === undefined) ? null : String(args[0]).replace(/^\s+/, '');
            case 'rtrim':
              return (args[0] === null || args[0] === undefined) ? null : String(args[0]).replace(/\s+$/, '');
            case 'abs':
              if (args[0] === null || args[0] === undefined) return null;
              if (typeof args[0] === 'bigint') return rt.normBigInt(args[0] < 0n ? -args[0] : args[0]);
              return Math.abs(rt.toNum(args[0]));
            case 'ceil':
            case 'ceiling':
              return (args[0] === null || args[0] === undefined) ? null : Math.ceil(rt.toNum(args[0]));
            case 'floor':
              return (args[0] === null || args[0] === undefined) ? null : Math.floor(rt.toNum(args[0]));
            case 'sign':
              if (args[0] === null || args[0] === undefined) return null;
              if (typeof args[0] === 'bigint') return args[0] < 0n ? -1 : (args[0] > 0n ? 1 : 0);
              return Math.sign(rt.toNum(args[0]));
            case 'sqrt':
              return (args[0] === null || args[0] === undefined) ? null : Math.sqrt(rt.toNum(args[0]));
            case 'round':
              if (args[0] === null || args[0] === undefined) return null;
              if (args.length > 1 && args[1] !== undefined) {
                if (args[1] === null) return null;
                const f = Math.pow(10, Math.trunc(rt.toNum(args[1])));
                return Math.round(rt.toNum(args[0]) * f) / f;
              }
              return Math.round(rt.toNum(args[0]));
            case 'trunc':
              if (args[0] === null || args[0] === undefined) return null;
              if (args.length > 1 && args[1] !== undefined) {
                if (args[1] === null) return null;
                const f = Math.pow(10, Math.trunc(rt.toNum(args[1])));
                return Math.trunc(rt.toNum(args[0]) * f) / f;
              }
              return Math.trunc(rt.toNum(args[0]));
            case 'mod':
              return rt.mod(args[0], args[1]);
            case 'power':
            case 'pow':
              return rt.pow(args[0], args[1]);
            case 'array_length': {
              const a = args[0];
              const d = args[1] !== undefined ? Math.trunc(rt.toNum(args[1])) : 1;
              if (!Array.isArray(a) || a.length === 0 || d === null) return null;
              let cur = a;
              for (let i = 1; i < d; i++) {
                if (!Array.isArray(cur) || cur.length === 0) return null;
                cur = cur[0];
              }
              return Array.isArray(cur) && cur.length > 0 ? cur.length : null;
            }
            case 'cardinality': {
              const a = args[0];
              if (a === null || a === undefined) return null;
              if (!Array.isArray(a)) return 0;
              return rt.flattenForeach(a, 0).length;
            }
            default:
              return undefined;
          }
        }
      };
      globalThis.__plpgsql_v8_rt = rt;
      return rt;
    }

    function tokenize(src) {
      const tokens = [];
      const n = src.length;
      let i = 0;
      let line = 1;

      function advance(count) {
        for (let k = 0; k < count; k++) {
          if (src[i + k] === '\n') line++;
        }
        i += count;
      }

      while (i < n) {
        const ch = src[i];
        if (ch === ' ' || ch === '\t' || ch === '\r' || ch === '\n') {
          advance(1);
          continue;
        }
        if (ch === '-' && i + 1 < n && src[i + 1] === '-') {
          while (i < n && src[i] !== '\n') i++;
          continue;
        }
        if (ch === '/' && i + 1 < n && src[i + 1] === '*') {
          let depth = 1;
          const startLine = line;
          advance(2);
          while (i < n && depth > 0) {
            if (src[i] === '/' && i + 1 < n && src[i + 1] === '*') {
              depth++;
              advance(2);
            } else if (src[i] === '*' && i + 1 < n && src[i + 1] === '/') {
              depth--;
              advance(2);
            } else {
              advance(1);
            }
          }
          if (depth > 0) {
            const err = new Error('unterminated /* comment at or near line ' + startLine);
            err.sqlerrcode = '42601';
            throw err;
          }
          continue;
        }
        if (ch === '\x23') {
          const start = i;
          while (i < n && src[i] !== '\n') i++;
          tokens.push({ type: 'directive', value: src.slice(start, i).trim(), upper: '', raw: src.slice(start, i), pos: start, end: i, line: line });
          continue;
        }
        if (ch === '$') {
          const rest = src.slice(i);
          const mParam = rest.match(/^\$(\d+)\b/);
          if (mParam) {
            const raw = mParam[0];
            const start = i;
            advance(raw.length);
            tokens.push({ type: 'param', value: raw, upper: raw, raw: raw, pos: start, end: i, line: line });
            continue;
          }
          const mTag = rest.match(new RegExp('^\\$([A-Za-z_\\x80-\\uffff][A-Za-z0-9_\\x80-\\uffff]*)?\\$'));
          if (mTag) {
            const tag = mTag[0];
            const start = i;
            const startLine = line;
            advance(tag.length);
            const closeIdx = src.indexOf(tag, i);
            if (closeIdx === -1) {
              const err = new Error('unterminated dollar-quoted string at or near "' + tag + '" at line ' + startLine);
              err.sqlerrcode = '42601';
              throw err;
            }
            const content = src.slice(i, closeIdx);
            advance(closeIdx + tag.length - i);
            tokens.push({ type: 'string', strVal: content, value: null, upper: '', raw: src.slice(start, i), pos: start, end: i, line: startLine });
            continue;
          }
        }
        if ((ch === 'E' || ch === 'e') && i + 1 < n && src[i + 1] === "'") {
          const start = i;
          const startLine = line;
          advance(2);
          let val = '';
          let closed = false;
          while (i < n) {
            if (src[i] === '\\' && i + 1 < n) {
              const next = src[i + 1];
              if (next === 'n') val += '\n';
              else if (next === 't') val += '\t';
              else if (next === 'r') val += '\r';
              else if (next === 'b') val += '\b';
              else if (next === 'f') val += '\f';
              else val += next;
              advance(2);
            } else if (src[i] === "'") {
              if (i + 1 < n && src[i + 1] === "'") {
                val += "'";
                advance(2);
              } else {
                advance(1);
                closed = true;
                break;
              }
            } else {
              val += src[i];
              advance(1);
            }
          }
          if (!closed) {
            const err = new Error('unterminated quoted string at or near line ' + startLine);
            err.sqlerrcode = '42601';
            throw err;
          }
          tokens.push({ type: 'string', strVal: val, value: null, upper: '', raw: src.slice(start, i), pos: start, end: i, line: startLine });
          continue;
        }
        if (ch === "'") {
          const start = i;
          const startLine = line;
          advance(1);
          let val = '';
          let closed = false;
          while (i < n) {
            if (src[i] === "'") {
              if (i + 1 < n && src[i + 1] === "'") {
                val += "'";
                advance(2);
              } else {
                advance(1);
                closed = true;
                break;
              }
            } else {
              val += src[i];
              advance(1);
            }
          }
          if (!closed) {
            const err = new Error('unterminated quoted string at or near line ' + startLine);
            err.sqlerrcode = '42601';
            throw err;
          }
          tokens.push({ type: 'string', strVal: val, value: null, upper: '', raw: src.slice(start, i), pos: start, end: i, line: startLine });
          continue;
        }
        if (ch === '"') {
          const start = i;
          const startLine = line;
          advance(1);
          let val = '';
          let closed = false;
          while (i < n) {
            if (src[i] === '"') {
              if (i + 1 < n && src[i + 1] === '"') {
                val += '"';
                advance(2);
              } else {
                advance(1);
                closed = true;
                break;
              }
            } else {
              val += src[i];
              advance(1);
            }
          }
          if (!closed) {
            const err = new Error('unterminated quoted identifier at or near line ' + startLine);
            err.sqlerrcode = '42601';
            throw err;
          }
          tokens.push({ type: 'ident', quoted: true, value: val, upper: val.toUpperCase(), raw: src.slice(start, i), pos: start, end: i, line: startLine });
          continue;
        }
        if ((ch >= '0' && ch <= '9') || (ch === '.' && i + 1 < n && src[i + 1] >= '0' && src[i + 1] <= '9')) {
          const start = i;
          while (i < n && src[i] >= '0' && src[i] <= '9') i++;
          let isFloat = false;
          if (i < n && src[i] === '.' && !(i + 1 < n && src[i + 1] === '.')) {
            isFloat = true;
            i++;
            while (i < n && src[i] >= '0' && src[i] <= '9') i++;
          }
          if (i < n && (src[i] === 'e' || src[i] === 'E')) {
            isFloat = true;
            i++;
            if (i < n && (src[i] === '+' || src[i] === '-')) i++;
            while (i < n && src[i] >= '0' && src[i] <= '9') i++;
          }
          const raw = src.slice(start, i);
          tokens.push({ type: 'number', isFloat: isFloat, value: raw, upper: raw, raw: raw, pos: start, end: i, line: line });
          continue;
        }
        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch === '_' || ch >= '\x80') {
          const start = i;
          while (i < n) {
            const c = src[i];
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c === '_' || c >= '\x80') {
              i++;
            } else {
              break;
            }
          }
          const raw = src.slice(start, i);
          tokens.push({ type: 'ident', quoted: false, value: raw.toLowerCase(), upper: raw.toUpperCase(), raw: raw, pos: start, end: i, line: line });
          continue;
        }
        const two = src.slice(i, i + 2);
        if (two === ':=' || two === '<<' || two === '>>' || two === '..' || two === '::' || two === '<=' || two === '>=' || two === '<>' || two === '!=' || two === '||') {
          const start = i;
          advance(2);
          tokens.push({ type: 'op', value: two, upper: two, raw: two, pos: start, end: i, line: line });
          continue;
        }
        const start = i;
        advance(1);
        tokens.push({ type: 'punct', value: ch, upper: ch, raw: ch, pos: start, end: i, line: line });
      }
      return tokens;
    }

    function compilePlpgsql(src, meta) {
      const rt = ensureRuntime();
      const pg = rt.pg();
      if (typeof src !== 'string') {
        const err = new Error('PL/pgSQL source must be a string');
        err.sqlerrcode = '42601';
        throw err;
      }

      let procInfo = {
        proname: (meta && meta.proname) ? String(meta.proname) : null,
        fn_oid: (meta && meta.fn_oid) ? Number(meta.fn_oid) : 0,
        proretset: false,
        rettype_sql: 'void',
        rettype_typtype: 'p',
        is_trigger: (meta && meta.rettype_oid === 2279) || false,
        is_proc: false,
        inArgs: [],
        outArgs: [],
        tableArgs: []
      };

      if (procInfo.fn_oid > 0) {
        try {
          const rows = pg.execute(
            "SELECT p.proname, p.proretset, p.prorettype::oid AS prorettype, " +
            "pg_catalog.format_type(p.prorettype, NULL) AS rettype_sql, " +
            "t.typtype AS rettype_typtype, " +
            "ARRAY(SELECT pg_catalog.format_type(u, NULL) FROM unnest(p.proargtypes) u) AS in_arg_types, " +
            "CASE WHEN p.proallargtypes IS NOT NULL THEN ARRAY(SELECT pg_catalog.format_type(u, NULL) FROM unnest(p.proallargtypes) u) ELSE NULL END AS all_arg_types, " +
            "p.proargmodes::text[] AS proargmodes, " +
            "p.proargnames AS proargnames, " +
            "p.prokind AS prokind " +
            "FROM pg_catalog.pg_proc p " +
            "LEFT JOIN pg_catalog.pg_type t ON t.oid = p.prorettype " +
            "WHERE p.oid = $1",
            [procInfo.fn_oid]
          );
          if (rows && rows.length > 0) {
            const r = rows[0];
            procInfo.proname = r.proname || procInfo.proname;
            procInfo.proretset = Boolean(r.proretset);
            procInfo.rettype_sql = r.rettype_sql || 'void';
            procInfo.rettype_typtype = r.rettype_typtype || 'b';
            procInfo.is_trigger = (r.rettype_sql === 'trigger' || Number(r.prorettype) === 2279);
            procInfo.is_proc = (r.prokind === 'p');
            const modes = r.proargmodes;
            const names = r.proargnames || [];
            const allTypes = r.all_arg_types || r.in_arg_types || [];
            if (!modes) {
              const inTypes = r.in_arg_types || [];
              for (let a = 0; a < inTypes.length; a++) {
                procInfo.inArgs.push({
                  inIndex: a,
                  posParam: '$' + (a + 1),
                  name: (names[a] && names[a].length > 0) ? names[a].toLowerCase() : null,
                  sqlType: inTypes[a]
                });
              }
            } else {
              let inIdx = 0;
              for (let a = 0; a < modes.length; a++) {
                const mode = modes[a];
                const argName = (names[a] && names[a].length > 0) ? names[a].toLowerCase() : null;
                const argType = allTypes[a] || 'text';
                if (mode === 'i' || mode === 'b' || mode === 'v') {
                  const entry = {
                    inIndex: inIdx,
                    posParam: '$' + (inIdx + 1),
                    name: argName,
                    sqlType: argType,
                    isInOut: (mode === 'b')
                  };
                  procInfo.inArgs.push(entry);
                  if (mode === 'b') {
                    procInfo.outArgs.push({
                      name: argName || ('$' + (inIdx + 1)),
                      sqlType: argType,
                      isInOut: true,
                      inIndex: inIdx
                    });
                  }
                  inIdx++;
                } else if (mode === 'o') {
                  procInfo.outArgs.push({
                    name: argName || ('_out_' + a),
                    sqlType: argType,
                    isInOut: false
                  });
                } else if (mode === 't') {
                  procInfo.tableArgs.push({
                    name: argName || ('_col_' + a),
                    sqlType: argType
                  });
                }
              }
            }
          }
        } catch (e) {
          void 0;
        }
      } else if (meta && Array.isArray(meta.argtype_oids)) {
        for (let a = 0; a < meta.argtype_oids.length; a++) {
          procInfo.inArgs.push({
            inIndex: a,
            posParam: '$' + (a + 1),
            name: (meta.argnames && meta.argnames[a]) ? String(meta.argnames[a]).toLowerCase() : null,
            sqlType: null
          });
        }
      }

      const tokens = tokenize(src);
      let pos = 0;
      let varCounter = 0;
      const scopeStack = [];
      const loopStack = [];
      let subtranDepth = 0;

      function syntaxError(msg, tok) {
        const t = tok || tokens[pos] || tokens[tokens.length - 1];
        const loc = t ? (' at or near "' + t.raw + '" (line ' + t.line + ')') : ' at end of input';
        const err = new Error('PL/pgSQL syntax error: ' + msg + loc);
        err.sqlerrcode = '42601';
        err.code = '42601';
        throw err;
      }

      function peek(offset) {
        return tokens[pos + (offset || 0)] || null;
      }

      function next() {
        return tokens[pos++] || null;
      }

      function matchKeyword(kw) {
        const t = peek();
        if (t && t.type === 'ident' && !t.quoted && t.upper === kw) {
          pos++;
          return t;
        }
        return null;
      }

      function expectKeyword(kw) {
        const t = matchKeyword(kw);
        if (!t) syntaxError('expected "' + kw + '"');
        return t;
      }

      function matchVal(v) {
        const t = peek();
        if (t && t.value === v) {
          pos++;
          return t;
        }
        return null;
      }

      function expectVal(v) {
        const t = matchVal(v);
        if (!t) syntaxError('expected "' + v + '"');
        return t;
      }

      function pushScope(label) {
        const frame = { label: label ? label.toLowerCase() : null, vars: Object.create(null) };
        scopeStack.push(frame);
        return frame;
      }

      function popScope() {
        scopeStack.pop();
      }

      function lookupVar(name) {
        const key = name.toLowerCase();
        for (let i = scopeStack.length - 1; i >= 0; i--) {
          if (scopeStack[i].vars[key]) return scopeStack[i].vars[key];
        }
        return null;
      }

      function lookupQualifiedVar(label, name) {
        const lkey = label.toLowerCase();
        const nkey = name.toLowerCase();
        for (let i = scopeStack.length - 1; i >= 0; i--) {
          if (scopeStack[i].label === lkey && scopeStack[i].vars[nkey]) {
            return scopeStack[i].vars[nkey];
          }
        }
        return null;
      }

      function isPolymorphicOrPseudoType(sqlType) {
        if (!sqlType) return true;
        const t = sqlType.toLowerCase().trim();
        return (
          t === 'record' ||
          t === 'trigger' ||
          t === 'void' ||
          t === 'refcursor' ||
          t === 'cursor' ||
          t === 'any' ||
          t === 'anyelement' ||
          t === 'anyarray' ||
          t === 'anynonarray' ||
          t === 'anyenum' ||
          t === 'anyrange' ||
          t === 'anymultirange' ||
          t === 'anycompatible' ||
          t === 'anycompatiblearray' ||
          t === 'anycompatiblenonarray' ||
          t === 'anycompatiblerange' ||
          t === 'internal' ||
          t === 'language_handler'
        );
      }

      function isCompositeOrRecordVar(v) {
        if (!v) return false;
        if (v.kind === 'record' || v.kind === 'rowtype' || v.kind === 'trigger_tuple') return true;
        return false;
      }

      function isIntType(sqlType) {
        if (!sqlType) return false;
        const t = sqlType.toLowerCase().trim();
        return (t === 'int' || t === 'int2' || t === 'int4' || t === 'int8' || t === 'integer' || t === 'smallint' || t === 'bigint' || t === 'serial' || t === 'bigserial' || t === 'oid');
      }

      const rootScope = pushScope(procInfo.proname);
      const initLines = [];

      rootScope.vars['found'] = {
        jsName: '__found',
        sqlType: 'boolean',
        kind: 'scalar',
        constant: false,
        notNull: false
      };
      rootScope.vars['sqlstate'] = {
        jsName: '__sqlstate',
        sqlType: 'text',
        kind: 'scalar',
        constant: true,
        notNull: false
      };
      rootScope.vars['sqlerrm'] = {
        jsName: '__sqlerrm',
        sqlType: 'text',
        kind: 'scalar',
        constant: true,
        notNull: false
      };

      if (procInfo.is_trigger) {
        initLines.push("let __tg_new = (typeof NEW !== 'undefined' && NEW !== undefined) ? NEW : null;");
        initLines.push("let __tg_old = (typeof OLD !== 'undefined' && OLD !== undefined) ? OLD : null;");
        initLines.push("let __tg_name = (typeof TG_NAME !== 'undefined') ? TG_NAME : null;");
        initLines.push("let __tg_when = (typeof TG_WHEN !== 'undefined') ? TG_WHEN : null;");
        initLines.push("let __tg_level = (typeof TG_LEVEL !== 'undefined') ? TG_LEVEL : null;");
        initLines.push("let __tg_op = (typeof TG_OP !== 'undefined') ? TG_OP : null;");
        initLines.push("let __tg_relid = (typeof TG_RELID !== 'undefined') ? TG_RELID : null;");
        initLines.push("let __tg_table_name = (typeof TG_TABLE_NAME !== 'undefined') ? TG_TABLE_NAME : null;");
        initLines.push("let __tg_table_schema = (typeof TG_TABLE_SCHEMA !== 'undefined') ? TG_TABLE_SCHEMA : null;");
        initLines.push("let __tg_relname = __tg_table_name;");
        initLines.push("let __tg_argv = (typeof TG_ARGV !== 'undefined' && Array.isArray(TG_ARGV)) ? TG_ARGV.slice() : [];");
        initLines.push("Object.defineProperty(__tg_argv, '__zeroIndexed', { value: true, enumerable: false });");
        initLines.push("let __tg_nargs = __tg_argv.length;");

        rootScope.vars['new'] = { jsName: '__tg_new', sqlType: 'record', kind: 'trigger_tuple', constant: false, notNull: false };
        rootScope.vars['old'] = { jsName: '__tg_old', sqlType: 'record', kind: 'trigger_tuple', constant: false, notNull: false };
        rootScope.vars['tg_name'] = { jsName: '__tg_name', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_when'] = { jsName: '__tg_when', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_level'] = { jsName: '__tg_level', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_op'] = { jsName: '__tg_op', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_relid'] = { jsName: '__tg_relid', sqlType: 'oid', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_table_name'] = { jsName: '__tg_table_name', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_relname'] = { jsName: '__tg_relname', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_table_schema'] = { jsName: '__tg_table_schema', sqlType: 'text', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_nargs'] = { jsName: '__tg_nargs', sqlType: 'int4', kind: 'scalar', constant: true, notNull: false };
        rootScope.vars['tg_argv'] = { jsName: '__tg_argv', sqlType: 'text[]', kind: 'scalar', constant: true, notNull: false, zeroIndexed: true };
      } else {
        for (let i = 0; i < procInfo.inArgs.length; i++) {
          const arg = procInfo.inArgs[i];
          const jsName = '__arg_' + (i + 1);
          initLines.push('let ' + jsName + ' = (arguments[' + arg.inIndex + '] === undefined) ? null : arguments[' + arg.inIndex + '];');
          let argKind = 'scalar';
          if (arg.sqlType === 'record') {
            argKind = 'record';
          } else if (arg.sqlType && !isPolymorphicOrPseudoType(arg.sqlType)) {
            try {
              const r = pg.execute("SELECT typtype FROM pg_catalog.pg_type WHERE oid = pg_catalog.to_regtype($1)", [arg.sqlType]);
              if (r && r.length > 0 && r[0].typtype === 'c') argKind = 'rowtype';
            } catch (e) {}
          }
          const vDesc = {
            jsName: jsName,
            sqlType: arg.sqlType || null,
            kind: argKind,
            constant: false,
            notNull: false
          };
          rootScope.vars[arg.posParam] = vDesc;
          if (arg.name) {
            rootScope.vars[arg.name] = vDesc;
          }
          if (arg.isInOut) {
            for (let j = 0; j < procInfo.outArgs.length; j++) {
              if (procInfo.outArgs[j].isInOut && procInfo.outArgs[j].inIndex === arg.inIndex) {
                procInfo.outArgs[j].jsName = jsName;
              }
            }
          }
        }
        for (let i = 0; i < procInfo.outArgs.length; i++) {
          const outArg = procInfo.outArgs[i];
          if (!outArg.isInOut) {
            const jsName = '__out_' + (i + 1) + '_' + outArg.name.replace(/[^a-zA-Z0-9_]/g, '_');
            initLines.push('let ' + jsName + ' = null;');
            outArg.jsName = jsName;
            rootScope.vars[outArg.name] = {
              jsName: jsName,
              sqlType: outArg.sqlType,
              kind: (outArg.sqlType === 'record') ? 'record' : 'scalar',
              constant: false,
              notNull: false
            };
          }
        }
        for (let i = 0; i < procInfo.tableArgs.length; i++) {
          const tArg = procInfo.tableArgs[i];
          const jsName = '__tbl_' + (i + 1) + '_' + tArg.name.replace(/[^a-zA-Z0-9_]/g, '_');
          initLines.push('let ' + jsName + ' = null;');
          tArg.jsName = jsName;
          rootScope.vars[tArg.name] = {
            jsName: jsName,
            sqlType: tArg.sqlType,
            kind: 'scalar',
            constant: false,
            notNull: false
          };
        }
      }

      const isScalarSrf = procInfo.proretset && procInfo.tableArgs.length <= 1 && procInfo.outArgs.length <= 1 && procInfo.rettype_typtype !== 'c' && procInfo.rettype_sql !== 'record';
      let outColNames = null;
      if (procInfo.tableArgs.length > 0 && !isScalarSrf) {
        outColNames = procInfo.tableArgs.map(function(t) { return t.name; });
      } else if (procInfo.outArgs.length > 0 && !isScalarSrf) {
        outColNames = procInfo.outArgs.map(function(o) { return o.name; });
      }
      const outColNamesJson = JSON.stringify(outColNames);

      function buildDefaultReturnExpr() {
        if (procInfo.proretset) return 'undefined';
        if (procInfo.outArgs.length === 1 && procInfo.rettype_sql !== 'record') {
          return procInfo.outArgs[0].jsName;
        }
        if (procInfo.outArgs.length >= 1) {
          const props = procInfo.outArgs.map(function(o) {
            return JSON.stringify(o.name) + ': ' + o.jsName;
          });
          return '{ ' + props.join(', ') + ' }';
        }
        if (procInfo.rettype_sql === 'void' || procInfo.is_proc) return 'undefined';
        return 'null';
      }

      function buildReturnNextDefaultExpr() {
        if (procInfo.tableArgs.length === 1 && isScalarSrf) {
          return procInfo.tableArgs[0].jsName;
        }
        if (procInfo.tableArgs.length >= 1) {
          const props = procInfo.tableArgs.map(function(t) {
            return JSON.stringify(t.name) + ': ' + t.jsName;
          });
          return '{ ' + props.join(', ') + ' }';
        }
        if (procInfo.outArgs.length === 1 && isScalarSrf) {
          return procInfo.outArgs[0].jsName;
        }
        if (procInfo.outArgs.length >= 1) {
          const props = procInfo.outArgs.map(function(o) {
            return JSON.stringify(o.name) + ': ' + o.jsName;
          });
          return '{ ' + props.join(', ') + ' }';
        }
        return 'null';
      }

      const SQL_ONLY_KEYWORDS = {
        SELECT: 1, FROM: 1, WHERE: 1, EXISTS: 1, INTERVAL: 1, EXTRACT: 1,
        CURRENT_DATE: 1, CURRENT_TIME: 1, CURRENT_TIMESTAMP: 1, LOCALTIME: 1,
        LOCALTIMESTAMP: 1, CURRENT_USER: 1, SESSION_USER: 1, CURRENT_SCHEMA: 1,
        CURRENT_DATABASE: 1, CURRENT_CATALOG: 1, CURRENT_ROLE: 1,
        ROW: 1, OVER: 1, FILTER: 1, WITHIN: 1, SIMILAR: 1, SYMMETRIC: 1, ASYMMETRIC: 1,
        ANY: 1, SOME: 1, ALL: 1, COLLATE: 1
      };

      const PURE_CAST_TYPES = {
        int: 1, int2: 1, int4: 1, int8: 1, integer: 1, smallint: 1, bigint: 1, oid: 1,
        float4: 1, float8: 1, real: 1, 'double precision': 1, numeric: 1, decimal: 1,
        bool: 1, boolean: 1, text: 1, varchar: 1, 'character varying': 1, char: 1, character: 1, bpchar: 1,
        json: 1, jsonb: 1
      };

      function rewriteSqlTokensWithParams(tokSlice, extraScopeMap) {
        if (!tokSlice || tokSlice.length === 0) {
          return { sql: '', params: [] };
        }
        const firstTok = tokSlice[0];
        const lastTok = tokSlice[tokSlice.length - 1];
        const baseOffset = firstTok.pos;
        const rawSql = src.slice(firstTok.pos, lastTok.end);
        const replacements = [];
        const params = [];

        function resolveName(name) {
          const k = name.toLowerCase();
          if (extraScopeMap && extraScopeMap[k]) return extraScopeMap[k];
          return lookupVar(k);
        }

        function addParam(jsExpr, sqlType) {
          params.push(jsExpr);
          const idx = params.length;
          if (sqlType && !isPolymorphicOrPseudoType(sqlType)) {
            return '($' + idx + '::' + sqlType + ')';
          }
          return '$' + idx;
        }

        let inInsertColList = false;
        let insertTargetSeen = false;
        let conflictTargetSeen = false;
        let inConflictColList = false;
        let inUpdateSetClause = false;
        let expectSetCol = false;
        let inSetColList = false;
        let parenDepth = 0;

        for (let k = 0; k < tokSlice.length; k++) {
          const t = tokSlice[k];
          const prev = k > 0 ? tokSlice[k - 1] : null;
          const nextTok = k + 1 < tokSlice.length ? tokSlice[k + 1] : null;

          if (t.value === '(') {
            if (prev && prev.type === 'ident') {
              let closeIdx = -1;
              let allIdentOrComma = true;
              for (let m = k + 1; m < tokSlice.length; m++) {
                if (tokSlice[m].value === ')') {
                  closeIdx = m;
                  break;
                }
                if (tokSlice[m].type !== 'ident' && tokSlice[m].value !== ',') {
                  allIdentOrComma = false;
                  break;
                }
              }
              if (closeIdx !== -1 && allIdentOrComma && closeIdx + 2 < tokSlice.length) {
                const afterClose = tokSlice[closeIdx + 1];
                const afterAs = tokSlice[closeIdx + 2];
                if (
                  afterClose.type === 'ident' && !afterClose.quoted && afterClose.upper === 'AS' &&
                  (afterAs.value === '(' || (afterAs.type === 'ident' && !afterAs.quoted && (afterAs.upper === 'MATERIALIZED' || afterAs.upper === 'NOT')))
                ) {
                  k = closeIdx;
                  continue;
                }
              }
            }
            if (insertTargetSeen && parenDepth === 0) {
              inInsertColList = true;
              insertTargetSeen = false;
            } else if (conflictTargetSeen && parenDepth === 0) {
              inConflictColList = true;
              conflictTargetSeen = false;
            } else if (inUpdateSetClause && expectSetCol && parenDepth === 0) {
              inSetColList = true;
            }
            parenDepth++;
            continue;
          }
          if (t.value === ')') {
            parenDepth = Math.max(0, parenDepth - 1);
            if (parenDepth === 0) {
              if (inInsertColList) inInsertColList = false;
              if (inConflictColList) inConflictColList = false;
              if (inSetColList) inSetColList = false;
            }
            continue;
          }

          if (parenDepth === 0 && t.type === 'ident' && !t.quoted) {
            if (t.upper === 'INTO' && prev && prev.upper === 'INSERT') {
              insertTargetSeen = true;
              continue;
            }
            if (insertTargetSeen && (t.upper === 'VALUES' || t.upper === 'SELECT' || t.upper === 'DEFAULT')) {
              insertTargetSeen = false;
            }
            if (t.upper === 'CONFLICT' && prev && prev.upper === 'ON') {
              conflictTargetSeen = true;
              continue;
            }
            if (conflictTargetSeen && (t.upper === 'DO' || t.upper === 'ON')) {
              conflictTargetSeen = false;
            }
            if (t.upper === 'SET' && prev && prev.upper !== 'RETURNS') {
              inUpdateSetClause = true;
              expectSetCol = true;
              continue;
            }
            if (inUpdateSetClause && (t.upper === 'WHERE' || t.upper === 'FROM' || t.upper === 'RETURNING')) {
              inUpdateSetClause = false;
              expectSetCol = false;
            }
          }

          if (inUpdateSetClause && parenDepth === 0) {
            if (t.value === ',') {
              expectSetCol = true;
              continue;
            }
            if (t.value === '=') {
              expectSetCol = false;
              continue;
            }
          }

          if ((inInsertColList || inConflictColList || inSetColList) && parenDepth === 1) {
            continue;
          }

          if (inUpdateSetClause && expectSetCol && parenDepth === 0 && t.type === 'ident') {
            if (nextTok && nextTok.value === '[') {
              expectSetCol = false;
            }
            continue;
          }

          if (t.type === 'param') {
            const v = resolveName(t.value);
            if (v) {
              const rep = addParam(v.jsName, v.sqlType);
              replacements.push({ start: t.pos - baseOffset, end: t.end - baseOffset, text: rep });
            }
            continue;
          }

          if (t.type === 'ident') {
            if (prev && (prev.value === '.' || prev.value === '::')) {
              continue;
            }
            if (nextTok && nextTok.value === '(') {
              continue;
            }
            if (prev && prev.type === 'ident' && !prev.quoted) {
              const pu = prev.upper;
              if (
                pu === 'FROM' || pu === 'JOIN' || pu === 'INTO' || pu === 'UPDATE' ||
                pu === 'TABLE' || pu === 'TRUNCATE' || pu === 'AS' || pu === 'TYPE' ||
                pu === 'SCHEMA' || pu === 'INDEX' || pu === 'SEQUENCE' || pu === 'VIEW' ||
                pu === 'TRIGGER' || pu === 'FUNCTION' || pu === 'PROCEDURE' || pu === 'EXTRACT'
              ) {
                continue;
              }
            }

            if (nextTok && nextTok.value === '.' && k + 2 < tokSlice.length && tokSlice[k + 2].type === 'ident') {
              const second = tokSlice[k + 2];
              const qv = lookupQualifiedVar(t.value, second.value);
              if (qv) {
                if (k + 4 < tokSlice.length && tokSlice[k + 3].value === '.' && tokSlice[k + 4].type === 'ident' && isCompositeOrRecordVar(qv)) {
                  const third = tokSlice[k + 4];
                  const rep = addParam('(' + qv.jsName + ' == null ? null : ' + qv.jsName + '[' + JSON.stringify(third.value) + '])', null);
                  replacements.push({ start: t.pos - baseOffset, end: third.end - baseOffset, text: rep });
                  k += 4;
                  continue;
                }
                const rep = addParam(qv.jsName, qv.sqlType);
                replacements.push({ start: t.pos - baseOffset, end: second.end - baseOffset, text: rep });
                k += 2;
                continue;
              }
              const rv = resolveName(t.value);
              if (rv && isCompositeOrRecordVar(rv)) {
                const fieldType = (rv.fieldTypes && rv.fieldTypes[second.value]) ? rv.fieldTypes[second.value] : null;
                const rep = addParam('(' + rv.jsName + ' == null ? null : ' + rv.jsName + '[' + JSON.stringify(second.value) + '])', fieldType);
                replacements.push({ start: t.pos - baseOffset, end: second.end - baseOffset, text: rep });
                k += 2;
                continue;
              }
              k += 2;
              continue;
            }

            const v = resolveName(t.value);
            if (v && v.kind !== 'cursor') {
              if (v.zeroIndexed && nextTok && nextTok.value === '[') {
                let bDepth = 1;
                let closeIdx = -1;
                for (let m = k + 2; m < tokSlice.length; m++) {
                  if (tokSlice[m].value === '[') bDepth++;
                  else if (tokSlice[m].value === ']') {
                    bDepth--;
                    if (bDepth === 0) {
                      closeIdx = m;
                      break;
                    }
                  }
                }
                if (closeIdx !== -1) {
                  const idxSlice = tokSlice.slice(k + 2, closeIdx);
                  const idxCode = compileExpr(idxSlice).code;
                  const elemType = (v.sqlType && v.sqlType.endsWith('[]')) ? v.sqlType.slice(0, -2) : 'text';
                  const rep = addParam('__rt.getElem(' + v.jsName + ', ' + idxCode + ')', elemType);
                  replacements.push({ start: t.pos - baseOffset, end: tokSlice[closeIdx].end - baseOffset, text: rep });
                  k = closeIdx;
                  continue;
                }
              }
              const rep = addParam(v.jsName, v.sqlType);
              replacements.push({ start: t.pos - baseOffset, end: t.end - baseOffset, text: rep });
            }
          }
        }

        let outSql = '';
        let lastIdx = 0;
        for (let r = 0; r < replacements.length; r++) {
          outSql += rawSql.slice(lastIdx, replacements[r].start) + replacements[r].text;
          lastIdx = replacements[r].end;
        }
        outSql += rawSql.slice(lastIdx);
        return { sql: outSql, params: params };
      }

      function compileExpr(tokSlice) {
        if (!tokSlice || tokSlice.length === 0) {
          syntaxError('empty expression');
        }

        for (let i = 0; i < tokSlice.length; i++) {
          const t = tokSlice[i];
          if (t.type === 'ident' && !t.quoted && SQL_ONLY_KEYWORDS[t.upper]) {
            if (i > 0 && tokSlice[i - 1].value === '.') continue;
            const rw = rewriteSqlTokensWithParams(tokSlice, null);
            return {
              code: '__rt.evalSql(' + JSON.stringify('SELECT (' + rw.sql + ') AS __val') + ', [' + rw.params.join(', ') + '])',
              type: null
            };
          }
        }

        let ep = 0;

        function ePeek(off) {
          return tokSlice[ep + (off || 0)] || null;
        }
        function eNext() {
          return tokSlice[ep++] || null;
        }
        function eMatchKw(kw) {
          const t = ePeek();
          if (t && t.type === 'ident' && !t.quoted && t.upper === kw) {
            ep++;
            return t;
          }
          return null;
        }
        function eMatchVal(v) {
          const t = ePeek();
          if (t && t.value === v) {
            ep++;
            return t;
          }
          return null;
        }

        function parseOr() {
          let left = parseAnd();
          while (eMatchKw('OR')) {
            const right = parseAnd();
            left = { code: '__rt.or(' + left.code + ', ' + right.code + ')', type: 'boolean' };
          }
          return left;
        }

        function parseAnd() {
          let left = parseNot();
          while (eMatchKw('AND')) {
            const right = parseNot();
            left = { code: '__rt.and(' + left.code + ', ' + right.code + ')', type: 'boolean' };
          }
          return left;
        }

        function parseNot() {
          if (eMatchKw('NOT')) {
            const sub = parseNot();
            return { code: '__rt.not(' + sub.code + ')', type: 'boolean' };
          }
          return parseComparison();
        }

        function parseComparison() {
          let left = parseAddSub();
          while (ep < tokSlice.length) {
            if (eMatchKw('IS')) {
              const isNot = Boolean(eMatchKw('NOT'));
              if (eMatchKw('NULL')) {
                left = {
                  code: isNot ? '(' + left.code + ' !== null && ' + left.code + ' !== undefined)' : '(' + left.code + ' === null || ' + left.code + ' === undefined)',
                  type: 'boolean'
                };
                continue;
              }
              if (eMatchKw('TRUE')) {
                left = {
                  code: isNot ? '(!__rt.truthy(' + left.code + '))' : '__rt.truthy(' + left.code + ')',
                  type: 'boolean'
                };
                continue;
              }
              if (eMatchKw('FALSE')) {
                left = {
                  code: isNot ? '(__rt.toBool(' + left.code + ') !== false)' : '(__rt.toBool(' + left.code + ') === false)',
                  type: 'boolean'
                };
                continue;
              }
              if (eMatchKw('UNKNOWN')) {
                left = {
                  code: isNot ? '(__rt.toBool(' + left.code + ') !== null)' : '(__rt.toBool(' + left.code + ') === null)',
                  type: 'boolean'
                };
                continue;
              }
              if (eMatchKw('DISTINCT')) {
                if (!eMatchKw('FROM')) throw new Error('fallback');
                const right = parseAddSub();
                const df = '__rt.isDistinctFrom(' + left.code + ', ' + right.code + ')';
                left = { code: isNot ? '(!' + df + ')' : df, type: 'boolean' };
                continue;
              }
              throw new Error('fallback');
            }

            const saveEp = ep;
            const negated = Boolean(eMatchKw('NOT'));
            if (eMatchKw('BETWEEN')) {
              const lo = parseAddSub();
              if (!eMatchKw('AND')) throw new Error('fallback');
              const hi = parseAddSub();
              const bCode = '__rt.between(' + left.code + ', ' + lo.code + ', ' + hi.code + ')';
              left = { code: negated ? '__rt.not(' + bCode + ')' : bCode, type: 'boolean' };
              continue;
            }
            if (eMatchKw('IN')) {
              if (!eMatchVal('(')) throw new Error('fallback');
              const items = [];
              if (!eMatchVal(')')) {
                while (true) {
                  items.push(parseOr().code);
                  if (eMatchVal(',')) continue;
                  if (eMatchVal(')')) break;
                  throw new Error('fallback');
                }
              }
              const inCode = '__rt.inList(' + left.code + ', [' + items.join(', ') + '])';
              left = { code: negated ? '__rt.not(' + inCode + ')' : inCode, type: 'boolean' };
              continue;
            }
            if (eMatchKw('LIKE') || eMatchKw('ILIKE')) {
              const isIlike = (tokSlice[ep - 1].upper === 'ILIKE');
              const pat = parseAddSub();
              const lCode = '__rt.like(' + left.code + ', ' + pat.code + ', ' + (isIlike ? 'true' : 'false') + ')';
              left = { code: negated ? '__rt.not(' + lCode + ')' : lCode, type: 'boolean' };
              continue;
            }
            if (negated) {
              ep = saveEp;
            }

            const t = ePeek();
            if (t && (t.value === '=' || t.value === '<>' || t.value === '!=' || t.value === '<' || t.value === '<=' || t.value === '>' || t.value === '>=')) {
              eNext();
              const right = parseAddSub();
              const fn = (t.value === '=') ? 'eq'
                : (t.value === '<>' || t.value === '!=') ? 'ne'
                : (t.value === '<') ? 'lt'
                : (t.value === '<=') ? 'le'
                : (t.value === '>') ? 'gt'
                : 'ge';
              left = { code: '__rt.' + fn + '(' + left.code + ', ' + right.code + ')', type: 'boolean' };
              continue;
            }
            break;
          }
          return left;
        }

        function parseAddSub() {
          let left = parseMulDiv();
          while (ep < tokSlice.length) {
            const t = ePeek();
            if (t && (t.value === '+' || t.value === '-' || t.value === '||')) {
              eNext();
              const right = parseMulDiv();
              if (t.value === '||') {
                left = { code: '__rt.concat(' + left.code + ', ' + right.code + ')', type: 'text' };
              } else {
                const fn = (t.value === '+') ? 'add' : 'sub';
                const resType = (isIntType(left.type) && isIntType(right.type)) ? 'int4' : 'numeric';
                left = { code: '__rt.' + fn + '(' + left.code + ', ' + right.code + ')', type: resType };
              }
            } else {
              break;
            }
          }
          return left;
        }

        function parseMulDiv() {
          let left = parsePow();
          while (ep < tokSlice.length) {
            const t = ePeek();
            if (t && (t.value === '*' || t.value === '/' || t.value === '%')) {
              eNext();
              const right = parsePow();
              if (t.value === '/') {
                if (isIntType(left.type) && isIntType(right.type)) {
                  left = { code: '__rt.idiv(' + left.code + ', ' + right.code + ')', type: 'int4' };
                } else {
                  left = { code: '__rt.div(' + left.code + ', ' + right.code + ')', type: 'numeric' };
                }
              } else if (t.value === '*') {
                const resType = (isIntType(left.type) && isIntType(right.type)) ? 'int4' : 'numeric';
                left = { code: '__rt.mul(' + left.code + ', ' + right.code + ')', type: resType };
              } else {
                left = { code: '__rt.mod(' + left.code + ', ' + right.code + ')', type: 'int4' };
              }
            } else {
              break;
            }
          }
          return left;
        }

        function parsePow() {
          let left = parseUnary();
          while (ep < tokSlice.length) {
            const t = ePeek();
            if (t && t.value === '^') {
              eNext();
              const right = parseUnary();
              left = { code: '__rt.pow(' + left.code + ', ' + right.code + ')', type: 'numeric' };
            } else {
              break;
            }
          }
          return left;
        }

        function parseUnary() {
          const t = ePeek();
          if (t && t.value === '+') {
            eNext();
            const sub = parseUnary();
            return { code: '__rt.uplus(' + sub.code + ')', type: sub.type };
          }
          if (t && t.value === '-') {
            eNext();
            if (ePeek() && ePeek().type === 'number' && (!ePeek(1) || (ePeek(1).value !== '::' && ePeek(1).value !== '^'))) {
              const numTok = eNext();
              if (!numTok.isFloat && /^[0-9]+$/.test(numTok.value) && numTok.value.length >= 10) {
                try {
                  const bi = -BigInt(numTok.value);
                  if (bi >= -9223372036854775808n && bi <= 9223372036854775807n && (bi < -2147483648n || bi > 2147483647n)) {
                    return { code: '(' + bi.toString() + 'n)', type: 'int8' };
                  }
                } catch (e) {}
              }
              return { code: '(-' + numTok.value + ')', type: numTok.isFloat ? 'numeric' : 'int4' };
            }
            const sub = parseUnary();
            return { code: '__rt.uminus(' + sub.code + ')', type: sub.type };
          }
          return parsePostfix();
        }

        function parseTypeNameInExpr() {
          const parts = [];
          while (ep < tokSlice.length) {
            const t = ePeek();
            if (!t) break;
            if (t.type === 'ident') {
              parts.push(t.value);
              eNext();
              if (ePeek() && ePeek().value === '(') {
                let p = '(';
                eNext();
                while (ep < tokSlice.length && ePeek().value !== ')') {
                  p += eNext().raw;
                }
                if (eMatchVal(')')) p += ')';
                parts[parts.length - 1] += p;
              }
              while (ePeek() && ePeek().value === '[' && ePeek(1) && ePeek(1).value === ']') {
                eNext();
                eNext();
                parts[parts.length - 1] += '[]';
              }
              if (parts.length === 1 && (parts[0] === 'double' || parts[0] === 'character' || parts[0] === 'timestamp' || parts[0] === 'time')) {
                continue;
              }
              break;
            } else {
              break;
            }
          }
          return parts.join(' ');
        }

        function parsePostfix() {
          let base = parsePrimary();
          while (ep < tokSlice.length) {
            const t = ePeek();
            if (t && t.value === '[') {
              eNext();
              const firstIdx = parseOr();
              if (eMatchVal(':')) {
                const secondIdx = parseOr();
                if (!eMatchVal(']')) throw new Error('fallback');
                base = { code: '__rt.getSlice(' + base.code + ', ' + firstIdx.code + ', ' + secondIdx.code + ')', type: base.type };
              } else {
                if (!eMatchVal(']')) throw new Error('fallback');
                const elemType = (base.type && base.type.endsWith('[]')) ? base.type.slice(0, -2) : null;
                base = { code: '__rt.getElem(' + base.code + ', ' + firstIdx.code + ')', type: elemType };
              }
              continue;
            }
            if (t && t.value === '::') {
              eNext();
              const castType = parseTypeNameInExpr();
              if (!castType) throw new Error('fallback');
              const baseCast = castType.replace(/\([^)]*\)/, '').trim().toLowerCase();
              const isArr = baseCast.endsWith('[]');
              const coreType = isArr ? baseCast.slice(0, -2) : baseCast;
              if (!PURE_CAST_TYPES[coreType]) {
                throw new Error('fallback');
              }
              base = { code: '__rt.coerce(' + base.code + ', ' + JSON.stringify(castType) + ', false)', type: castType };
              continue;
            }
            if (t && t.value === '.') {
              eNext();
              const fTok = eNext();
              if (!fTok || fTok.type !== 'ident') throw new Error('fallback');
              base = {
                code: '(' + base.code + ' == null ? null : (' + base.code + '[' + JSON.stringify(fTok.value) + '] === undefined ? null : ' + base.code + '[' + JSON.stringify(fTok.value) + ']))',
                type: null
              };
              continue;
            }
            break;
          }
          return base;
        }

        function parsePrimary() {
          const t = ePeek();
          if (!t) throw new Error('fallback');

          if (eMatchVal('(')) {
            const inner = parseOr();
            if (!eMatchVal(')')) throw new Error('fallback');
            return { code: '(' + inner.code + ')', type: inner.type };
          }

          if (t.type === 'number') {
            eNext();
            if (!t.isFloat && /^[0-9]+$/.test(t.value) && t.value.length >= 10) {
              try {
                const bi = BigInt(t.value);
                if (bi >= -9223372036854775808n && bi <= 9223372036854775807n && (bi < -2147483648n || bi > 2147483647n)) {
                  return { code: t.value + 'n', type: 'int8' };
                }
              } catch (e) {}
            }
            return { code: t.value, type: t.isFloat ? 'numeric' : 'int4' };
          }

          if (t.type === 'string') {
            eNext();
            return { code: JSON.stringify(t.strVal), type: 'text' };
          }

          if (t.type === 'param') {
            eNext();
            const v = lookupVar(t.value);
            if (!v) throw new Error('fallback');
            return { code: v.jsName, type: v.sqlType };
          }

          if (t.type === 'ident') {
            if (!t.quoted) {
              if (t.upper === 'NULL') {
                eNext();
                return { code: 'null', type: null };
              }
              if (t.upper === 'TRUE') {
                eNext();
                return { code: 'true', type: 'boolean' };
              }
              if (t.upper === 'FALSE') {
                eNext();
                return { code: 'false', type: 'boolean' };
              }
              if (t.upper === 'CAST' && ePeek(1) && ePeek(1).value === '(') {
                eNext();
                eNext();
                const valExpr = parseOr();
                if (!eMatchKw('AS')) throw new Error('fallback');
                const castType = parseTypeNameInExpr();
                if (!eMatchVal(')')) throw new Error('fallback');
                const baseCast = castType.replace(/\([^)]*\)/, '').trim().toLowerCase();
                const coreType = baseCast.endsWith('[]') ? baseCast.slice(0, -2) : baseCast;
                if (!PURE_CAST_TYPES[coreType]) throw new Error('fallback');
                return { code: '__rt.coerce(' + valExpr.code + ', ' + JSON.stringify(castType) + ', false)', type: castType };
              }
              if (t.upper === 'ARRAY' && ePeek(1) && ePeek(1).value === '[') {
                eNext();
                function parseArrayLiteral() {
                  eMatchVal('[');
                  const elems = [];
                  let elemType = null;
                  if (!eMatchVal(']')) {
                    while (true) {
                      if (ePeek() && ePeek().value === '[') {
                        const sub = parseArrayLiteral();
                        elems.push(sub.code);
                        elemType = sub.type;
                      } else {
                        const el = parseOr();
                        elems.push(el.code);
                        if (!elemType && el.type) elemType = el.type;
                      }
                      if (eMatchVal(',')) continue;
                      if (eMatchVal(']')) break;
                      throw new Error('fallback');
                    }
                  }
                  return { code: '[' + elems.join(', ') + ']', type: elemType ? (elemType + '[]') : 'text[]' };
                }
                return parseArrayLiteral();
              }
              if (t.upper === 'CASE') {
                eNext();
                let subject = null;
                if (!ePeek() || ePeek().type !== 'ident' || ePeek().quoted || ePeek().upper !== 'WHEN') {
                  subject = parseOr();
                }
                const branches = [];
                while (eMatchKw('WHEN')) {
                  const wExpr = parseOr();
                  if (!eMatchKw('THEN')) throw new Error('fallback');
                  const tExpr = parseOr();
                  branches.push({ w: wExpr, t: tExpr });
                }
                if (branches.length === 0) throw new Error('fallback');
                let elseExpr = { code: 'null', type: null };
                if (eMatchKw('ELSE')) {
                  elseExpr = parseOr();
                }
                if (!eMatchKw('END')) throw new Error('fallback');
                const resType = (branches[0] && branches[0].t.type) || elseExpr.type;
                if (subject) {
                  let code = '(function(__c) { return ';
                  for (let b = 0; b < branches.length; b++) {
                    code += '__rt.truthy(__rt.eq(__c, ' + branches[b].w.code + ')) ? (' + branches[b].t.code + ') : ';
                  }
                  code += '(' + elseExpr.code + '); })(' + subject.code + ')';
                  return { code: code, type: resType };
                } else {
                  let code = '(';
                  for (let b = 0; b < branches.length; b++) {
                    code += '__rt.truthy(' + branches[b].w.code + ') ? (' + branches[b].t.code + ') : ';
                  }
                  code += '(' + elseExpr.code + '))';
                  return { code: code, type: resType };
                }
              }
            }

            if (ePeek(1) && ePeek(1).value === '(') {
              const fnName = t.value.toLowerCase();
              eNext();
              eNext();
              const args = [];
              if (!eMatchVal(')')) {
                while (true) {
                  args.push(parseOr());
                  if (eMatchVal(',')) continue;
                  if (eMatchVal(')')) break;
                  throw new Error('fallback');
                }
              }
              const argCodes = args.map(function(a) { return a.code; });
              if (fnName === 'coalesce') {
                return { code: '__rt.coalesce([' + argCodes.join(', ') + '])', type: args[0] ? args[0].type : null };
              }
              if (fnName === 'nullif' && argCodes.length === 2) {
                return { code: '__rt.nullif(' + argCodes[0] + ', ' + argCodes[1] + ')', type: args[0].type };
              }
              if (fnName === 'greatest') {
                return { code: '__rt.greatest([' + argCodes.join(', ') + '])', type: args[0] ? args[0].type : null };
              }
              if (fnName === 'least') {
                return { code: '__rt.least([' + argCodes.join(', ') + '])', type: args[0] ? args[0].type : null };
              }
              const builtinCheck = rt.callBuiltin(fnName, []);
              if (builtinCheck !== undefined) {
                const retType = (fnName === 'lower' || fnName === 'upper' || fnName === 'btrim' || fnName === 'trim' || fnName === 'ltrim' || fnName === 'rtrim') ? 'text'
                  : (fnName === 'length' || fnName === 'char_length' || fnName === 'character_length' || fnName === 'array_length' || fnName === 'cardinality') ? 'int4'
                  : 'numeric';
                return { code: '__rt.callBuiltin(' + JSON.stringify(fnName) + ', [' + argCodes.join(', ') + '])', type: retType };
              }
              throw new Error('fallback');
            }

            if (ePeek(1) && ePeek(1).value === '.' && ePeek(2) && ePeek(2).type === 'ident') {
              const qv = lookupQualifiedVar(t.value, ePeek(2).value);
              if (qv) {
                eNext();
                eNext();
                eNext();
                return { code: qv.jsName, type: qv.sqlType };
              }
            }

            const v = lookupVar(t.value);
            if (v) {
              eNext();
              return { code: v.jsName, type: v.sqlType };
            }
          }

          throw new Error('fallback');
        }

        try {
          const parsed = parseOr();
          if (ep === tokSlice.length) {
            return parsed;
          }
        } catch (e) {
          void 0;
        }

        const rw = rewriteSqlTokensWithParams(tokSlice, null);
        return {
          code: '__rt.evalSql(' + JSON.stringify('SELECT (' + rw.sql + ') AS __val') + ', [' + rw.params.join(', ') + '])',
          type: null
        };
      }

      function collectUntil(stopFn) {
        const slice = [];
        let parenDepth = 0;
        let caseDepth = 0;
        while (pos < tokens.length) {
          const t = peek();
          if (parenDepth === 0 && caseDepth === 0 && stopFn(t)) {
            break;
          }
          if (t.value === '(' || t.value === '[') {
            parenDepth++;
          } else if (t.value === ')' || t.value === ']') {
            if (parenDepth > 0) parenDepth--;
          } else if (t.type === 'ident' && !t.quoted) {
            if (t.upper === 'CASE') {
              caseDepth++;
            } else if (t.upper === 'END' && caseDepth > 0) {
              caseDepth--;
            }
          }
          slice.push(next());
        }
        return slice;
      }

      function parseTargetLValue(tokSlice) {
        if (!tokSlice || tokSlice.length === 0) syntaxError('invalid assignment target');
        let idx = 0;
        if (tokSlice[0].type !== 'ident' && tokSlice[0].type !== 'param') {
          syntaxError('invalid assignment target', tokSlice[0]);
        }
        let v = null;
        if (tokSlice.length >= 3 && tokSlice[1].value === '.' && tokSlice[2].type === 'ident') {
          const qv = lookupQualifiedVar(tokSlice[0].value, tokSlice[2].value);
          if (qv) {
            v = qv;
            idx = 3;
          }
        }
        if (!v) {
          v = lookupVar(tokSlice[0].value);
          idx = 1;
        }
        if (!v) {
          syntaxError('"' + tokSlice[0].raw + '" is not a known variable', tokSlice[0]);
        }
        if (v.constant) {
          syntaxError('variable "' + tokSlice[0].raw + '" is declared CONSTANT', tokSlice[0]);
        }
        if (idx === tokSlice.length) {
          return {
            kind: 'var',
            varInfo: v,
            assignCode: function(rhsCode) {
              if (v.kind === 'scalar' && v.sqlType) {
                return v.jsName + ' = __rt.coerce(' + rhsCode + ', ' + JSON.stringify(v.sqlType) + ', ' + (v.notNull ? 'true' : 'false') + ', ' + JSON.stringify(tokSlice[0].value) + ');';
              }
              if (v.notNull) {
                return v.jsName + ' = __rt.coerce(' + rhsCode + ', null, true, ' + JSON.stringify(tokSlice[0].value) + ');';
              }
              return v.jsName + ' = ' + rhsCode + ';';
            }
          };
        }
        if (tokSlice[idx].value === '.' && idx + 2 === tokSlice.length && tokSlice[idx + 1].type === 'ident') {
          const fieldName = tokSlice[idx + 1].value;
          const fieldType = (v.fieldTypes && v.fieldTypes[fieldName]) ? v.fieldTypes[fieldName] : null;
          return {
            kind: 'field',
            varInfo: v,
            fieldName: fieldName,
            assignCode: function(rhsCode) {
              const coerced = fieldType ? '__rt.coerce(' + rhsCode + ', ' + JSON.stringify(fieldType) + ', false)' : rhsCode;
              return v.jsName + ' = __rt.setField(' + v.jsName + ', ' + JSON.stringify(fieldName) + ', ' + coerced + ');';
            }
          };
        }
        if (tokSlice[idx].value === '[' && tokSlice[tokSlice.length - 1].value === ']') {
          const inner = tokSlice.slice(idx + 1, tokSlice.length - 1);
          let colonIdx = -1;
          let pDepth = 0;
          for (let k = 0; k < inner.length; k++) {
            if (inner[k].value === '(' || inner[k].value === '[') pDepth++;
            else if (inner[k].value === ')' || inner[k].value === ']') pDepth--;
            else if (pDepth === 0 && inner[k].value === ':') {
              colonIdx = k;
              break;
            }
          }
          const elemType = (v.sqlType && v.sqlType.endsWith('[]')) ? v.sqlType.slice(0, -2) : null;
          if (colonIdx !== -1) {
            const loExpr = compileExpr(inner.slice(0, colonIdx)).code;
            const hiExpr = compileExpr(inner.slice(colonIdx + 1)).code;
            return {
              kind: 'slice',
              varInfo: v,
              assignCode: function(rhsCode) {
                return v.jsName + ' = __rt.setSlice(' + v.jsName + ', ' + loExpr + ', ' + hiExpr + ', ' + rhsCode + ');';
              }
            };
          } else {
            const idxExpr = compileExpr(inner).code;
            return {
              kind: 'elem',
              varInfo: v,
              assignCode: function(rhsCode) {
                const coerced = elemType ? '__rt.coerce(' + rhsCode + ', ' + JSON.stringify(elemType) + ', false)' : rhsCode;
                return v.jsName + ' = __rt.setElem(' + v.jsName + ', ' + idxExpr + ', ' + coerced + ');';
              }
            };
          }
        }
        syntaxError('invalid assignment target', tokSlice[0]);
      }

      function emitRowToTargets(rowExpr, targetLValues) {
        if (targetLValues.length === 1 && isCompositeOrRecordVar(targetLValues[0].varInfo) && targetLValues[0].kind === 'var') {
          const v = targetLValues[0].varInfo;
          if (v.kind === 'rowtype' && v.fieldNames && v.fieldNames.length > 0) {
            return 'if (' + rowExpr + ' == null) { ' + v.jsName + ' = null; } else { ' +
              'const __rk = Object.keys(' + rowExpr + '); ' +
              'const __ro = {}; ' +
              JSON.stringify(v.fieldNames) + '.forEach(function(__fn, __fi) { ' +
              '  __ro[__fn] = (' + rowExpr + '[__fn] !== undefined) ? ' + rowExpr + '[__fn] : (__fi < __rk.length ? ' + rowExpr + '[__rk[__fi]] : null); ' +
              '}); ' + v.jsName + ' = __ro; }';
          }
          return v.jsName + ' = (' + rowExpr + ' == null ? null : Object.assign({}, ' + rowExpr + '));';
        }
        let code = '{ const __rk = (' + rowExpr + ' != null) ? Object.keys(' + rowExpr + ') : []; ';
        for (let i = 0; i < targetLValues.length; i++) {
          const valExpr = '(' + rowExpr + ' != null && ' + i + ' < __rk.length) ? ' + rowExpr + '[__rk[' + i + ']] : null';
          code += targetLValues[i].assignCode(valExpr) + ' ';
        }
        code += '}';
        return code;
      }

      function parseDeclareSection(scopeFrame, outLines) {
        while (pos < tokens.length) {
          if (peek().type === 'directive') {
            next();
            continue;
          }
          if (peek().type === 'ident' && !peek().quoted && peek().upper === 'BEGIN') {
            break;
          }
          if (peek().type === 'ident' && !peek().quoted && peek().upper === 'DECLARE') {
            next();
            continue;
          }
          const declSlice = collectUntil(function(t) { return t.value === ';'; });
          expectVal(';');
          if (declSlice.length === 0) continue;

          const varTok = declSlice[0];
          if (varTok.type !== 'ident') {
            syntaxError('expected variable name in DECLARE', varTok);
          }
          const varName = varTok.value;
          const jsName = '__v' + (++varCounter) + '_' + varName.replace(/[^a-zA-Z0-9_]/g, '_');

          if (declSlice.length >= 4 && declSlice[1].upper === 'ALIAS' && declSlice[2].upper === 'FOR') {
            const targetTok = declSlice[3];
            const targetVar = lookupVar(targetTok.value);
            if (!targetVar) {
              syntaxError('variable "' + targetTok.raw + '" does not exist for ALIAS', targetTok);
            }
            scopeFrame.vars[varName] = targetVar;
            continue;
          }

          let cursorKwIdx = -1;
          for (let k = 1; k < declSlice.length; k++) {
            if (declSlice[k].type === 'ident' && !declSlice[k].quoted && declSlice[k].upper === 'CURSOR') {
              cursorKwIdx = k;
              break;
            }
          }
          if (cursorKwIdx !== -1) {
            let pIdx = cursorKwIdx + 1;
            const curParams = [];
            if (pIdx < declSlice.length && declSlice[pIdx].value === '(') {
              pIdx++;
              while (pIdx < declSlice.length && declSlice[pIdx].value !== ')') {
                if (declSlice[pIdx].value === ',') { pIdx++; continue; }
                const pNameTok = declSlice[pIdx++];
                const pTypeParts = [];
                while (pIdx < declSlice.length && declSlice[pIdx].value !== ',' && declSlice[pIdx].value !== ')') {
                  pTypeParts.push(declSlice[pIdx++].raw);
                }
                curParams.push({ name: pNameTok.value.toLowerCase(), sqlType: pTypeParts.join(' ') });
              }
              if (pIdx < declSlice.length && declSlice[pIdx].value === ')') pIdx++;
            }
            if (pIdx < declSlice.length && (declSlice[pIdx].upper === 'FOR' || declSlice[pIdx].upper === 'IS')) {
              pIdx++;
            } else {
              syntaxError('expected FOR or IS in CURSOR declaration', declSlice[pIdx]);
            }
            const queryTokens = declSlice.slice(pIdx);
            scopeFrame.vars[varName] = {
              jsName: jsName,
              sqlType: 'refcursor',
              kind: 'cursor',
              cursorParams: curParams,
              queryTokens: queryTokens,
              constant: false,
              notNull: false
            };
            outLines.push('let ' + jsName + ' = null;');
            continue;
          }

          let dIdx = 1;
          let isConstant = false;
          if (dIdx < declSlice.length && declSlice[dIdx].upper === 'CONSTANT') {
            isConstant = true;
            dIdx++;
          }

          let assignIdx = -1;
          let pDepth = 0;
          for (let k = dIdx; k < declSlice.length; k++) {
            if (declSlice[k].value === '(' || declSlice[k].value === '[') pDepth++;
            else if (declSlice[k].value === ')' || declSlice[k].value === ']') pDepth--;
            else if (pDepth === 0 && (declSlice[k].value === ':=' || declSlice[k].value === '=' || declSlice[k].upper === 'DEFAULT')) {
              assignIdx = k;
              break;
            }
          }

          const typeAttrSlice = (assignIdx !== -1) ? declSlice.slice(dIdx, assignIdx) : declSlice.slice(dIdx);
          const defaultExprSlice = (assignIdx !== -1) ? declSlice.slice(assignIdx + 1) : null;

          let notNull = false;
          let typeEnd = typeAttrSlice.length;
          if (typeEnd >= 2 && typeAttrSlice[typeEnd - 2].upper === 'NOT' && typeAttrSlice[typeEnd - 1].upper === 'NULL') {
            notNull = true;
            typeEnd -= 2;
          }
          if (typeEnd >= 2 && typeAttrSlice[typeEnd - 2].upper === 'COLLATE') {
            typeEnd -= 2;
          }
          const rawTypeSlice = typeAttrSlice.slice(0, typeEnd);
          if (rawTypeSlice.length === 0) {
            syntaxError('missing data type in declaration of "' + varTok.raw + '"', varTok);
          }

          let sqlType = '';
          let varKind = 'scalar';
          let fieldNames = null;
          let fieldTypes = null;

          const rawTypeStr = src.slice(rawTypeSlice[0].pos, rawTypeSlice[rawTypeSlice.length - 1].end).trim();
          const upperTypeStr = rawTypeStr.toUpperCase();

          if (upperTypeStr === 'RECORD') {
            sqlType = 'record';
            varKind = 'record';
          } else if (upperTypeStr === 'REFCURSOR') {
            sqlType = 'refcursor';
            varKind = 'cursor';
          } else if (/%ROWTYPE$/i.test(rawTypeStr)) {
            const relName = rawTypeStr.replace(/%ROWTYPE$/i, '').trim();
            sqlType = relName;
            varKind = 'rowtype';
            try {
              const attRows = pg.execute(
                "SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod) AS atttype " +
                "FROM pg_catalog.pg_attribute a " +
                "WHERE a.attrelid = pg_catalog.to_regclass($1) AND a.attnum > 0 AND NOT a.attisdropped " +
                "ORDER BY a.attnum",
                [relName]
              );
              if (attRows && attRows.length > 0) {
                fieldNames = [];
                fieldTypes = Object.create(null);
                for (let r = 0; r < attRows.length; r++) {
                  fieldNames.push(attRows[r].attname);
                  fieldTypes[attRows[r].attname.toLowerCase()] = attRows[r].atttype;
                }
              }
            } catch (e) {}
          } else if (/%TYPE$/i.test(rawTypeStr)) {
            const refStr = rawTypeStr.replace(/%TYPE$/i, '').trim();
            const refVar = lookupVar(refStr);
            if (refVar && refVar.sqlType) {
              sqlType = refVar.sqlType;
              varKind = refVar.kind;
            } else {
              const dotIdx = refStr.lastIndexOf('.');
              if (dotIdx !== -1) {
                const relPart = refStr.slice(0, dotIdx);
                const colPart = refStr.slice(dotIdx + 1).replace(/^"|"$/g, '');
                const relVar = lookupVar(relPart);
                if (relVar && relVar.fieldTypes && relVar.fieldTypes[colPart.toLowerCase()]) {
                  sqlType = relVar.fieldTypes[colPart.toLowerCase()];
                } else {
                  try {
                    const r = pg.execute(
                      "SELECT pg_catalog.format_type(a.atttypid, a.atttypmod) AS atttype " +
                      "FROM pg_catalog.pg_attribute a " +
                      "WHERE a.attrelid = pg_catalog.to_regclass($1) AND lower(a.attname) = lower($2) AND a.attnum > 0 AND NOT a.attisdropped",
                      [relPart, colPart]
                    );
                    if (r && r.length > 0) sqlType = r[0].atttype;
                  } catch (e) {}
                }
              }
              if (!sqlType) sqlType = 'text';
            }
          } else {
            sqlType = rawTypeStr.replace(/\s+/g, ' ');
            try {
              const r = pg.execute(
                "SELECT t.typtype, t.typrelid::oid AS typrelid " +
                "FROM pg_catalog.pg_type t WHERE t.oid = pg_catalog.to_regtype($1)",
                [sqlType]
              );
              if (r && r.length > 0 && r[0].typtype === 'c') {
                varKind = 'rowtype';
                const attRows = pg.execute(
                  "SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod) AS atttype " +
                  "FROM pg_catalog.pg_attribute a " +
                  "WHERE a.attrelid = $1 AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum",
                  [r[0].typrelid]
                );
                if (attRows && attRows.length > 0) {
                  fieldNames = [];
                  fieldTypes = Object.create(null);
                  for (let a = 0; a < attRows.length; a++) {
                    fieldNames.push(attRows[a].attname);
                    fieldTypes[attRows[a].attname.toLowerCase()] = attRows[a].atttype;
                  }
                }
              }
            } catch (e) {}
          }

          if (notNull && !defaultExprSlice) {
            const err = new Error('variable "' + varTok.raw + '" declared NOT NULL must have a default');
            err.sqlerrcode = '42601';
            err.code = '42601';
            throw err;
          }

          let initExprCode = 'null';
          if (defaultExprSlice) {
            const compiledDef = compileExpr(defaultExprSlice);
            if (varKind === 'scalar') {
              initExprCode = '__rt.coerce(' + compiledDef.code + ', ' + JSON.stringify(sqlType) + ', ' + (notNull ? 'true' : 'false') + ', ' + JSON.stringify(varName) + ')';
            } else {
              initExprCode = compiledDef.code;
            }
          } else if (varKind === 'rowtype' && fieldNames && fieldNames.length > 0) {
            const nullProps = fieldNames.map(function(fn) { return JSON.stringify(fn) + ': null'; });
            initExprCode = '{ ' + nullProps.join(', ') + ' }';
          }

          outLines.push('let ' + jsName + ' = ' + initExprCode + ';');
          scopeFrame.vars[varName] = {
            jsName: jsName,
            sqlType: sqlType,
            kind: varKind,
            fieldNames: fieldNames,
            fieldTypes: fieldTypes,
            constant: isConstant,
            notNull: notNull
          };
        }
      }

      function emitCtrlUnwindCheck() {
        let code = 'if (__ctrl) { ';
        for (let i = loopStack.length - 1; i >= 0; i--) {
          const lp = loopStack[i];
          if (lp.subtranDepth !== subtranDepth) continue;
          code += 'if (__ctrl.type === "exit" && __ctrl.jsLabel === ' + JSON.stringify(lp.jsLabel) + ') { __ctrl = null; break ' + lp.jsLabel + '; } ';
          if (lp.isLoop) {
            code += 'if (__ctrl.type === "continue" && __ctrl.jsLabel === ' + JSON.stringify(lp.jsLabel) + ') { __ctrl = null; continue ' + lp.jsLabel + '; } ';
          }
        }
        if (subtranDepth > 0) {
          code += 'return; }';
        } else {
          code += 'if (__ctrl.type === "return") return __ctrl.value; }';
        }
        return code;
      }

      function parseStmtList(stopKeywords) {
        const lines = [];
        while (pos < tokens.length) {
          const t = peek();
          if (!t) break;
          if (t.type === 'directive') {
            next();
            continue;
          }
          if (t.type === 'ident' && !t.quoted && stopKeywords[t.upper]) {
            break;
          }
          const stmtCode = parseOneStmt();
          if (stmtCode) lines.push(stmtCode);
        }
        return lines.join('\n');
      }

      function parseBlock(blockLabel) {
        let lbl = blockLabel || null;
        if (!lbl && peek() && peek().value === '<<') {
          next();
          const lTok = next();
          if (!lTok || lTok.type !== 'ident') syntaxError('expected label name after <<');
          expectVal('>>');
          lbl = lTok.value;
        }

        const scopeFrame = pushScope(lbl);
        const declLines = [];
        while (peek() && peek().type === 'directive') next();
        if (matchKeyword('DECLARE')) {
          parseDeclareSection(scopeFrame, declLines);
        }
        expectKeyword('BEGIN');

        const jsBlockLabel = '__blk_' + (++varCounter);
        loopStack.push({ label: lbl ? lbl.toLowerCase() : '__none__', jsLabel: jsBlockLabel, isLoop: false, subtranDepth: subtranDepth });

        let hasException = false;
        const openStack = [];
        for (let k = pos; k < tokens.length; k++) {
          const tk = tokens[k];
          if (tk.type === 'ident' && !tk.quoted) {
            if (tk.upper === 'BEGIN') {
              openStack.push('BEGIN');
            } else if (tk.upper === 'CASE') {
              openStack.push('CASE');
            } else if (tk.upper === 'END') {
              const nextTk = tokens[k + 1];
              const nextUpper = (nextTk && nextTk.type === 'ident' && !nextTk.quoted) ? nextTk.upper : '';
              if (nextUpper === 'IF' || nextUpper === 'LOOP') {
                k++;
              } else if (nextUpper === 'CASE') {
                k++;
                if (openStack.length > 0 && openStack[openStack.length - 1] === 'CASE') {
                  openStack.pop();
                }
              } else {
                if (openStack.length === 0) break;
                openStack.pop();
              }
            } else if (tk.upper === 'EXCEPTION' && openStack.length === 0) {
              const prevTk = k > pos ? tokens[k - 1] : null;
              const isRaiseException = (prevTk && prevTk.type === 'ident' && !prevTk.quoted && prevTk.upper === 'RAISE');
              if (!isRaiseException) {
                let m = k + 1;
                while (m < tokens.length && tokens[m].type === 'directive') m++;
                const afterExc = tokens[m];
                if (afterExc && afterExc.type === 'ident' && !afterExc.quoted && afterExc.upper === 'WHEN') {
                  hasException = true;
                  break;
                }
              }
            }
          }
        }

        let bodyCode = '';
        if (hasException) {
          subtranDepth++;
          const tryBody = parseStmtList({ EXCEPTION: 1, END: 1 });
          subtranDepth--;
          expectKeyword('EXCEPTION');
          const whenBranches = [];
          while (matchKeyword('WHEN')) {
            const conds = [];
            while (true) {
              if (matchKeyword('SQLSTATE')) {
                const sTok = next();
                if (!sTok || sTok.type !== 'string' || sTok.strVal.length !== 5) {
                  syntaxError('expected 5-character SQLSTATE string', sTok);
                }
                conds.push(sTok.strVal.toUpperCase());
              } else {
                const cTok = next();
                if (!cTok || cTok.type !== 'ident') syntaxError('expected condition name after WHEN', cTok);
                conds.push(cTok.value);
              }
              if (matchKeyword('OR')) continue;
              break;
            }
            expectKeyword('THEN');
            const handlerBody = parseStmtList({ WHEN: 1, END: 1 });
            whenBranches.push({ conds: conds, body: handlerBody });
          }

          let catchCode = 'const __prev_err = __cur_err, __prev_state = __sqlstate, __prev_errm = __sqlerrm, __prev_detail = __err_detail, __prev_hint = __err_hint, __prev_ctx = __err_context, __prev_schema = __err_schema, __prev_table = __err_table, __prev_col = __err_column, __prev_dtype = __err_datatype, __prev_constr = __err_constraint;\n';
          catchCode += '__cur_err = __err;\n';
          catchCode += '__sqlstate = __rt.extractSqlState(__err);\n';
          catchCode += '__sqlerrm = String(__err && __err.message !== undefined ? __err.message : __err);\n';
          catchCode += '__err_detail = String((__err && __err.detail) || "");\n';
          catchCode += '__err_hint = String((__err && __err.hint) || "");\n';
          catchCode += '__err_context = String((__err && (__err.context || __err.stack)) || "");\n';
          catchCode += '__err_schema = String((__err && __err.schema_name) || "");\n';
          catchCode += '__err_table = String((__err && __err.table_name) || "");\n';
          catchCode += '__err_column = String((__err && __err.column_name) || "");\n';
          catchCode += '__err_datatype = String((__err && __err.datatype_name) || "");\n';
          catchCode += '__err_constraint = String((__err && __err.constraint_name) || "");\n';
          catchCode += 'try {\n';
          for (let w = 0; w < whenBranches.length; w++) {
            const wb = whenBranches[w];
            catchCode += (w === 0 ? 'if (' : 'else if (') + '__rt.matchException(__err, ' + JSON.stringify(wb.conds) + ')) {\n' + wb.body + '\n}\n';
          }
          catchCode += 'else { throw __err; }\n';
          catchCode += '} finally {\n__cur_err = __prev_err; __sqlstate = __prev_state; __sqlerrm = __prev_errm; __err_detail = __prev_detail; __err_hint = __prev_hint; __err_context = __prev_ctx; __err_schema = __prev_schema; __err_table = __prev_table; __err_column = __prev_col; __err_datatype = __prev_dtype; __err_constraint = __prev_constr;\n}';

          bodyCode = 'try {\n__pg.subtransaction(function() {\n' + tryBody + '\n});\n} catch (__err) {\n' + catchCode + '\n}\n' + emitCtrlUnwindCheck();
        } else {
          bodyCode = parseStmtList({ END: 1 });
        }

        expectKeyword('END');
        if (peek() && peek().type === 'ident' && peek().value !== ';') {
          const endLbl = next();
          if (lbl && endLbl.value.toLowerCase() !== lbl.toLowerCase()) {
            syntaxError('end label "' + endLbl.raw + '" does not match block label "' + lbl + '"', endLbl);
          }
        }
        matchVal(';');

        loopStack.pop();
        popScope();

        return jsBlockLabel + ': {\n' + declLines.join('\n') + (declLines.length > 0 ? '\n' : '') + bodyCode + '\n}';
      }

      function parseOneStmt() {
        while (peek() && peek().type === 'directive') next();
        let stmtLabel = null;
        if (peek() && peek().value === '<<') {
          next();
          const lTok = next();
          if (!lTok || lTok.type !== 'ident') syntaxError('expected label name after <<');
          expectVal('>>');
          stmtLabel = lTok.value;
        }

        const t = peek();
        if (!t) return '';
        if (t.value === ';') {
          next();
          return '';
        }

        if (t.type === 'ident' && !t.quoted) {
          switch (t.upper) {
            case 'DECLARE':
            case 'BEGIN':
              return parseBlock(stmtLabel);
            case 'IF':
              return parseIfStmt();
            case 'CASE':
              return parseCaseStmt();
            case 'LOOP':
              return parseLoopStmt(stmtLabel);
            case 'WHILE':
              return parseWhileStmt(stmtLabel);
            case 'FOR':
              return parseForStmt(stmtLabel);
            case 'FOREACH':
              return parseForeachStmt(stmtLabel);
            case 'EXIT':
              return parseExitContinStmt(false);
            case 'CONTINUE':
              return parseExitContinStmt(true);
            case 'RETURN':
              return parseReturnStmt();
            case 'RAISE':
              return parseRaiseStmt();
            case 'ASSERT':
              return parseAssertStmt();
            case 'PERFORM':
              return parsePerformStmt();
            case 'EXECUTE':
              return parseExecuteStmt();
            case 'GET':
              return parseGetDiagnosticsStmt();
            case 'OPEN':
              return parseOpenStmt();
            case 'FETCH':
              return parseFetchStmt();
            case 'MOVE':
              return parseMoveStmt();
            case 'CLOSE':
              return parseCloseStmt();
            case 'NULL':
              if (peek(1) && peek(1).value === ';') {
                next();
                next();
                return '/* NULL */';
              }
              break;
            case 'COMMIT':
              if (peek(1) && peek(1).value === ';') {
                next();
                next();
                return '__pg.execute("COMMIT");';
              }
              break;
            case 'ROLLBACK':
              if (peek(1) && peek(1).value === ';') {
                next();
                next();
                return '__pg.execute("ROLLBACK");';
              }
              break;
          }
        }

        const stmtTokens = collectUntil(function(tk) { return tk.value === ';'; });
        expectVal(';');
        if (stmtTokens.length === 0) return '';

        const firstUpper = (stmtTokens[0].type === 'ident' && !stmtTokens[0].quoted) ? stmtTokens[0].upper : '';
        const isDefinitelySql = (
          firstUpper === 'SELECT' || firstUpper === 'WITH' || firstUpper === 'INSERT' ||
          firstUpper === 'UPDATE' || firstUpper === 'DELETE' || firstUpper === 'VALUES' ||
          firstUpper === 'CREATE' || firstUpper === 'DROP' || firstUpper === 'ALTER' ||
          firstUpper === 'TRUNCATE' || firstUpper === 'GRANT' || firstUpper === 'REVOKE' ||
          firstUpper === 'LOCK' || firstUpper === 'NOTIFY' || firstUpper === 'LISTEN' ||
          firstUpper === 'UNLISTEN' || firstUpper === 'ANALYZE' || firstUpper === 'VACUUM' ||
          firstUpper === 'CALL' || firstUpper === 'DO' || firstUpper === 'RESET' ||
          firstUpper === 'SHOW'
        );

        if (!isDefinitelySql) {
          let assignPos = -1;
          let pDepth = 0;
          for (let k = 0; k < stmtTokens.length; k++) {
            const tk = stmtTokens[k];
            if (tk.value === '(' || tk.value === '[') pDepth++;
            else if (tk.value === ')' || tk.value === ']') pDepth--;
            else if (pDepth === 0 && (tk.value === ':=' || tk.value === '=')) {
              assignPos = k;
              break;
            }
          }
          if (assignPos > 0) {
            const lhsRoot = stmtTokens[0];
            const isTargetInScope = Boolean(
              lookupVar(lhsRoot.value) ||
              (stmtTokens.length >= 3 && stmtTokens[1].value === '.' && lookupQualifiedVar(lhsRoot.value, stmtTokens[2].value))
            );
            if (stmtTokens[assignPos].value === ':=' || isTargetInScope) {
              const target = parseTargetLValue(stmtTokens.slice(0, assignPos));
              const rhs = compileExpr(stmtTokens.slice(assignPos + 1));
              return target.assignCode(rhs.code);
            }
          }
        }

        return compileStaticSqlStmt(stmtTokens);
      }

      function parseIfStmt() {
        expectKeyword('IF');
        const condSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'THEN'; });
        expectKeyword('THEN');
        const thenBody = parseStmtList({ ELSIF: 1, ELSEIF: 1, ELSE: 1, END: 1 });
        let code = 'if (__rt.truthy(' + compileExpr(condSlice).code + ')) {\n' + thenBody + '\n}';
        while (matchKeyword('ELSIF') || matchKeyword('ELSEIF')) {
          const eCondSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'THEN'; });
          expectKeyword('THEN');
          const eBody = parseStmtList({ ELSIF: 1, ELSEIF: 1, ELSE: 1, END: 1 });
          code += ' else if (__rt.truthy(' + compileExpr(eCondSlice).code + ')) {\n' + eBody + '\n}';
        }
        if (matchKeyword('ELSE')) {
          const elseBody = parseStmtList({ END: 1 });
          code += ' else {\n' + elseBody + '\n}';
        }
        expectKeyword('END');
        expectKeyword('IF');
        expectVal(';');
        return code;
      }

      function parseCaseStmt() {
        expectKeyword('CASE');
        let subjectCode = null;
        if (!peek() || peek().upper !== 'WHEN') {
          const subjSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'WHEN'; });
          subjectCode = compileExpr(subjSlice).code;
        }
        const subjVar = subjectCode ? ('__case_' + (++varCounter)) : null;
        let code = subjectCode ? ('{\nconst ' + subjVar + ' = ' + subjectCode + ';\n') : '{\n';
        let first = true;
        while (matchKeyword('WHEN')) {
          const whenExprs = [];
          while (true) {
            const wSlice = collectUntil(function(t) {
              return t.value === ',' || (t.type === 'ident' && !t.quoted && t.upper === 'THEN');
            });
            const wCode = compileExpr(wSlice).code;
            if (subjVar) {
              whenExprs.push('__rt.truthy(__rt.eq(' + subjVar + ', ' + wCode + '))');
            } else {
              whenExprs.push('__rt.truthy(' + wCode + ')');
            }
            if (matchVal(',')) continue;
            break;
          }
          expectKeyword('THEN');
          const wBody = parseStmtList({ WHEN: 1, ELSE: 1, END: 1 });
          code += (first ? 'if (' : ' else if (') + whenExprs.join(' || ') + ') {\n' + wBody + '\n}';
          first = false;
        }
        if (matchKeyword('ELSE')) {
          const elseBody = parseStmtList({ END: 1 });
          code += ' else {\n' + elseBody + '\n}';
        } else {
          code += ' else {\n  throw __rt.makeError("20000", "case not found");\n}';
        }
        expectKeyword('END');
        expectKeyword('CASE');
        expectVal(';');
        code += '\n}';
        return code;
      }

      function parseLoopStmt(label) {
        expectKeyword('LOOP');
        const jsLabel = '__lp_' + (++varCounter);
        loopStack.push({ label: label ? label.toLowerCase() : null, jsLabel: jsLabel, isLoop: true, subtranDepth: subtranDepth });
        const body = parseStmtList({ END: 1 });
        expectKeyword('END');
        expectKeyword('LOOP');
        if (peek() && peek().type === 'ident' && peek().value !== ';') {
          const endLbl = next();
          if (label && endLbl.value.toLowerCase() !== label.toLowerCase()) {
            syntaxError('end label "' + endLbl.raw + '" does not match loop label "' + label + '"', endLbl);
          }
        }
        expectVal(';');
        loopStack.pop();
        return jsLabel + ': while (true) {\n' + body + '\n}';
      }

      function parseWhileStmt(label) {
        expectKeyword('WHILE');
        const condSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'LOOP'; });
        expectKeyword('LOOP');
        const jsLabel = '__lp_' + (++varCounter);
        loopStack.push({ label: label ? label.toLowerCase() : null, jsLabel: jsLabel, isLoop: true, subtranDepth: subtranDepth });
        const body = parseStmtList({ END: 1 });
        expectKeyword('END');
        expectKeyword('LOOP');
        if (peek() && peek().type === 'ident' && peek().value !== ';') {
          next();
        }
        expectVal(';');
        loopStack.pop();
        return jsLabel + ': while (__rt.truthy(' + compileExpr(condSlice).code + ')) {\n' + body + '\n}';
      }

      function parseForStmt(label) {
        expectKeyword('FOR');
        const targetSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'IN'; });
        expectKeyword('IN');

        const headerSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'LOOP'; });
        expectKeyword('LOOP');

        let dotDotIdx = -1;
        let pDepth = 0;
        for (let k = 0; k < headerSlice.length; k++) {
          if (headerSlice[k].value === '(' || headerSlice[k].value === '[') pDepth++;
          else if (headerSlice[k].value === ')' || headerSlice[k].value === ']') pDepth--;
          else if (pDepth === 0 && headerSlice[k].value === '..') {
            dotDotIdx = k;
            break;
          }
        }

        const jsLabel = '__lp_' + (++varCounter);

        if (dotDotIdx !== -1) {
          let hStart = 0;
          let isReverse = false;
          if (headerSlice[0] && headerSlice[0].type === 'ident' && !headerSlice[0].quoted && headerSlice[0].upper === 'REVERSE') {
            isReverse = true;
            hStart = 1;
          }
          const lowerSlice = headerSlice.slice(hStart, dotDotIdx);
          const afterDots = headerSlice.slice(dotDotIdx + 1);
          let byIdx = -1;
          pDepth = 0;
          for (let k = 0; k < afterDots.length; k++) {
            if (afterDots[k].value === '(' || afterDots[k].value === '[') pDepth++;
            else if (afterDots[k].value === ')' || afterDots[k].value === ']') pDepth--;
            else if (pDepth === 0 && afterDots[k].type === 'ident' && !afterDots[k].quoted && afterDots[k].upper === 'BY') {
              byIdx = k;
              break;
            }
          }
          const upperSlice = (byIdx !== -1) ? afterDots.slice(0, byIdx) : afterDots;
          const stepSlice = (byIdx !== -1) ? afterDots.slice(byIdx + 1) : null;

          const lowerCode = compileExpr(lowerSlice).code;
          const upperCode = compileExpr(upperSlice).code;
          const stepCode = stepSlice ? compileExpr(stepSlice).code : '1';

          const varName = targetSlice[0].value;
          const forScope = pushScope(label);
          const loopVarJs = '__for_' + (++varCounter) + '_' + varName.replace(/[^a-zA-Z0-9_]/g, '_');
          forScope.vars[varName] = {
            jsName: loopVarJs,
            sqlType: 'int4',
            kind: 'scalar',
            constant: false,
            notNull: false
          };

          loopStack.push({ label: label ? label.toLowerCase() : null, jsLabel: jsLabel, isLoop: true, subtranDepth: subtranDepth });
          const body = parseStmtList({ END: 1 });
          expectKeyword('END');
          expectKeyword('LOOP');
          if (peek() && peek().type === 'ident' && peek().value !== ';') next();
          expectVal(';');
          loopStack.pop();
          popScope();

          const bnd1 = '__b1_' + varCounter;
          const bnd2 = '__b2_' + varCounter;
          const stp = '__stp_' + varCounter;
          const fiVar = '__fi_' + varCounter;
          const cmpOp = isReverse ? '>=' : '<=';
          const stepOp = isReverse ? '-=' : '+=';

          return '{\n' +
            'const ' + bnd1 + ' = __rt.coerce(' + lowerCode + ', "int4", true, "FOR bound");\n' +
            'const ' + bnd2 + ' = __rt.coerce(' + upperCode + ', "int4", true, "FOR bound");\n' +
            'const ' + stp + ' = __rt.coerce(' + stepCode + ', "int4", true, "FOR step");\n' +
            'if (' + stp + ' <= 0) throw __rt.makeError("22023", "step size must be greater than zero");\n' +
            'let ' + fiVar + ' = false;\n' +
            'let ' + loopVarJs + ' = ' + bnd1 + ';\n' +
            jsLabel + ': for (; ' + loopVarJs + ' ' + cmpOp + ' ' + bnd2 + '; ' + loopVarJs + ' ' + stepOp + ' ' + stp + ') {\n' +
            '  ' + fiVar + ' = true;\n' +
            body + '\n}\n' +
            '__found = ' + fiVar + ';\n}';
        }

        const targetParts = [];
        let curPart = [];
        for (let k = 0; k < targetSlice.length; k++) {
          if (targetSlice[k].value === ',') {
            targetParts.push(curPart);
            curPart = [];
          } else {
            curPart.push(targetSlice[k]);
          }
        }
        if (curPart.length > 0) targetParts.push(curPart);

        const forScope = pushScope(label);
        let implicitDeclLine = '';
        if (targetParts.length === 1 && targetParts[0].length === 1 && !lookupVar(targetParts[0][0].value)) {
          const impName = targetParts[0][0].value;
          const impJs = '__rec_' + (++varCounter) + '_' + impName.replace(/[^a-zA-Z0-9_]/g, '_');
          implicitDeclLine = 'let ' + impJs + ' = null;\n';
          forScope.vars[impName] = {
            jsName: impJs,
            sqlType: 'record',
            kind: 'record',
            constant: false,
            notNull: false
          };
        }
        const targetLValues = targetParts.map(function(tp) { return parseTargetLValue(tp); });

        if (headerSlice.length >= 1 && headerSlice[0].type === 'ident' && lookupVar(headerSlice[0].value) && lookupVar(headerSlice[0].value).kind === 'cursor') {
          const curVar = lookupVar(headerSlice[0].value);
          const argExprs = [];
          if (headerSlice.length > 1 && headerSlice[1].value === '(') {
            const innerArgs = headerSlice.slice(2, headerSlice.length - 1);
            let curArg = [];
            let pD = 0;
            for (let k = 0; k < innerArgs.length; k++) {
              if (innerArgs[k].value === '(' || innerArgs[k].value === '[') pD++;
              else if (innerArgs[k].value === ')' || innerArgs[k].value === ']') pD--;
              else if (pD === 0 && innerArgs[k].value === ',') {
                argExprs.push(compileExpr(curArg).code);
                curArg = [];
                continue;
              }
              curArg.push(innerArgs[k]);
            }
            if (curArg.length > 0) argExprs.push(compileExpr(curArg).code);
          }

          loopStack.push({ label: label ? label.toLowerCase() : null, jsLabel: jsLabel, isLoop: true, subtranDepth: subtranDepth });
          const body = parseStmtList({ END: 1 });
          expectKeyword('END');
          expectKeyword('LOOP');
          if (peek() && peek().type === 'ident' && peek().value !== ';') next();
          expectVal(';');
          loopStack.pop();
          popScope();

          const extraScope = Object.create(null);
          if (curVar.cursorParams) {
            for (let p = 0; p < curVar.cursorParams.length; p++) {
              extraScope[curVar.cursorParams[p].name] = {
                jsName: (argExprs[p] !== undefined ? argExprs[p] : 'null'),
                sqlType: curVar.cursorParams[p].sqlType,
                kind: 'scalar'
              };
            }
          }
          const rw = rewriteSqlTokensWithParams(curVar.queryTokens, extraScope);
          const iterVar = '__it_' + varCounter;
          const rowVar = '__row_' + varCounter;
          return '{\n' + implicitDeclLine +
            curVar.jsName + ' = __rt.openCursor(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + ']);\n' +
            'let ' + iterVar + ' = false;\n' +
            'try {\n' +
            jsLabel + ': while (true) {\n' +
            '  const ' + rowVar + ' = __rt.fetchCursor(' + curVar.jsName + ', "NEXT", 1);\n' +
            '  if (' + rowVar + ' == null) break;\n' +
            '  ' + iterVar + ' = true;\n' +
            '  __found = true;\n' +
            '  ' + emitRowToTargets(rowVar, targetLValues) + '\n' +
            body + '\n}\n' +
            '} finally {\n' +
            '  if (' + curVar.jsName + ' && ' + curVar.jsName + '.portal) { try { __rt.closeCursor(' + curVar.jsName + '); } catch (_) {} }\n' +
            '}\n' +
            '__found = ' + iterVar + ';\n}';
        }

        let rowsExpr = '';
        if (headerSlice.length >= 1 && headerSlice[0].type === 'ident' && !headerSlice[0].quoted && headerSlice[0].upper === 'EXECUTE') {
          const rest = headerSlice.slice(1);
          let usingIdx = -1;
          pDepth = 0;
          for (let k = 0; k < rest.length; k++) {
            if (rest[k].value === '(' || rest[k].value === '[') pDepth++;
            else if (rest[k].value === ')' || rest[k].value === ']') pDepth--;
            else if (pDepth === 0 && rest[k].type === 'ident' && !rest[k].quoted && rest[k].upper === 'USING') {
              usingIdx = k;
              break;
            }
          }
          const dynQueryCode = compileExpr(usingIdx !== -1 ? rest.slice(0, usingIdx) : rest).code;
          const usingArgs = [];
          if (usingIdx !== -1) {
            const uSlice = rest.slice(usingIdx + 1);
            let curU = [];
            pDepth = 0;
            for (let k = 0; k < uSlice.length; k++) {
              if (uSlice[k].value === '(' || uSlice[k].value === '[') pDepth++;
              else if (uSlice[k].value === ')' || uSlice[k].value === ']') pDepth--;
              else if (pDepth === 0 && uSlice[k].value === ',') {
                usingArgs.push(compileExpr(curU).code);
                curU = [];
                continue;
              }
              curU.push(uSlice[k]);
            }
            if (curU.length > 0) usingArgs.push(compileExpr(curU).code);
          }
          rowsExpr = '__pg.execute(' + dynQueryCode + ', [' + usingArgs.join(', ') + '])';
        } else {
          const rw = rewriteSqlTokensWithParams(headerSlice, null);
          rowsExpr = '__pg.execute(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + '])';
        }

        loopStack.push({ label: label ? label.toLowerCase() : null, jsLabel: jsLabel, isLoop: true, subtranDepth: subtranDepth });
        const body = parseStmtList({ END: 1 });
        expectKeyword('END');
        expectKeyword('LOOP');
        if (peek() && peek().type === 'ident' && peek().value !== ';') next();
        expectVal(';');
        loopStack.pop();
        popScope();

        const rowsVar = '__rows_' + varCounter;
        const idxVar = '__idx_' + varCounter;
        const rowVar = '__row_' + varCounter;

        return '{\n' + implicitDeclLine +
          'const ' + rowsVar + ' = ' + rowsExpr + ' || [];\n' +
          '__found = false;\n' +
          jsLabel + ': for (let ' + idxVar + ' = 0; ' + idxVar + ' < ' + rowsVar + '.length; ' + idxVar + '++) {\n' +
          '  const ' + rowVar + ' = ' + rowsVar + '[' + idxVar + '];\n' +
          '  __found = true;\n' +
          '  ' + emitRowToTargets(rowVar, targetLValues) + '\n' +
          body + '\n}\n' +
          '__found = (' + rowsVar + '.length > 0);\n}';
      }

      function parseForeachStmt(label) {
        expectKeyword('FOREACH');
        const targetSlice = [];
        while (pos < tokens.length) {
          const t = peek();
          if (t.type === 'ident' && !t.quoted && (t.upper === 'SLICE' || t.upper === 'IN')) break;
          targetSlice.push(next());
        }
        let sliceDim = 0;
        if (matchKeyword('SLICE')) {
          const numTok = next();
          if (!numTok || numTok.type !== 'number') syntaxError('expected integer constant after SLICE', numTok);
          sliceDim = parseInt(numTok.value, 10);
        }
        expectKeyword('IN');
        expectKeyword('ARRAY');
        const arrExprSlice = collectUntil(function(t) { return t.type === 'ident' && !t.quoted && t.upper === 'LOOP'; });
        expectKeyword('LOOP');

        const targetLVal = parseTargetLValue(targetSlice);
        const arrExprCode = compileExpr(arrExprSlice).code;
        const jsLabel = '__lp_' + (++varCounter);

        loopStack.push({ label: label ? label.toLowerCase() : null, jsLabel: jsLabel, isLoop: true, subtranDepth: subtranDepth });
        const body = parseStmtList({ END: 1 });
        expectKeyword('END');
        expectKeyword('LOOP');
        if (peek() && peek().type === 'ident' && peek().value !== ';') next();
        expectVal(';');
        loopStack.pop();

        const itemsVar = '__arr_' + varCounter;
        const idxVar = '__i_' + varCounter;

        return '{\n' +
          'const ' + itemsVar + ' = __rt.flattenForeach(' + arrExprCode + ', ' + sliceDim + ');\n' +
          '__found = false;\n' +
          jsLabel + ': for (let ' + idxVar + ' = 0; ' + idxVar + ' < ' + itemsVar + '.length; ' + idxVar + '++) {\n' +
          '  __found = true;\n' +
          '  ' + targetLVal.assignCode(itemsVar + '[' + idxVar + ']') + '\n' +
          body + '\n}\n' +
          '__found = (' + itemsVar + '.length > 0);\n}';
      }

      function parseExitContinStmt(isContinue) {
        expectKeyword(isContinue ? 'CONTINUE' : 'EXIT');
        let targetLabel = null;
        if (peek() && peek().type === 'ident' && (peek().quoted || peek().upper !== 'WHEN') && peek().value !== ';') {
          targetLabel = next().value.toLowerCase();
        }
        let whenCondCode = null;
        if (matchKeyword('WHEN')) {
          const condSlice = collectUntil(function(t) { return t.value === ';'; });
          whenCondCode = compileExpr(condSlice).code;
        }
        expectVal(';');

        let targetEntry = null;
        for (let i = loopStack.length - 1; i >= 0; i--) {
          if (isContinue && !loopStack[i].isLoop) continue;
          if (!targetLabel) {
            if (loopStack[i].isLoop) {
              targetEntry = loopStack[i];
              break;
            }
          } else if (loopStack[i].label === targetLabel) {
            targetEntry = loopStack[i];
            break;
          }
        }
        if (!targetEntry) {
          syntaxError((isContinue ? 'CONTINUE' : 'EXIT') + (targetLabel ? (' label "' + targetLabel + '"') : '') + ' cannot be used outside a loop');
        }

        let actionCode = '';
        if (subtranDepth > targetEntry.subtranDepth) {
          actionCode = '__ctrl = { type: ' + JSON.stringify(isContinue ? 'continue' : 'exit') + ', jsLabel: ' + JSON.stringify(targetEntry.jsLabel) + ' }; return;';
        } else {
          actionCode = (isContinue ? 'continue ' : 'break ') + targetEntry.jsLabel + ';';
        }
        if (whenCondCode) {
          return 'if (__rt.truthy(' + whenCondCode + ')) { ' + actionCode + ' }';
        }
        return actionCode;
      }

      function parseReturnStmt() {
        expectKeyword('RETURN');
        if (matchKeyword('NEXT')) {
          const exprSlice = collectUntil(function(t) { return t.value === ';'; });
          expectVal(';');
          const valCode = (exprSlice.length > 0) ? compileExpr(exprSlice).code : buildReturnNextDefaultExpr();
          return '__rt.returnNext(' + valCode + ', ' + (isScalarSrf ? 'true' : 'false') + ', ' + outColNamesJson + ');';
        }
        if (matchKeyword('QUERY')) {
          if (matchKeyword('EXECUTE')) {
            const rest = collectUntil(function(t) { return t.value === ';'; });
            expectVal(';');
            let usingIdx = -1;
            let pD = 0;
            for (let k = 0; k < rest.length; k++) {
              if (rest[k].value === '(' || rest[k].value === '[') pD++;
              else if (rest[k].value === ')' || rest[k].value === ']') pD--;
              else if (pD === 0 && rest[k].type === 'ident' && !rest[k].quoted && rest[k].upper === 'USING') {
                usingIdx = k;
                break;
              }
            }
            const dynCode = compileExpr(usingIdx !== -1 ? rest.slice(0, usingIdx) : rest).code;
            const uArgs = [];
            if (usingIdx !== -1) {
              const uSlice = rest.slice(usingIdx + 1);
              let cur = [];
              pD = 0;
              for (let k = 0; k < uSlice.length; k++) {
                if (uSlice[k].value === '(' || uSlice[k].value === '[') pD++;
                else if (uSlice[k].value === ')' || uSlice[k].value === ']') pD--;
                else if (pD === 0 && uSlice[k].value === ',') {
                  uArgs.push(compileExpr(cur).code);
                  cur = [];
                  continue;
                }
                cur.push(uSlice[k]);
              }
              if (cur.length > 0) uArgs.push(compileExpr(cur).code);
            }
            const rqVar = '__rq_' + (++varCounter);
            return '{ const ' + rqVar + ' = __rt.returnQuery(' + dynCode + ', [' + uArgs.join(', ') + '], ' + (isScalarSrf ? 'true' : 'false') + ', ' + outColNamesJson + '); ' +
              '__last_row_count = ' + rqVar + '; __found = (' + rqVar + ' > 0); }';
          } else {
            const qSlice = collectUntil(function(t) { return t.value === ';'; });
            expectVal(';');
            const rw = rewriteSqlTokensWithParams(qSlice, null);
            const rqVar = '__rq_' + (++varCounter);
            return '{ const ' + rqVar + ' = __rt.returnQuery(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + '], ' + (isScalarSrf ? 'true' : 'false') + ', ' + outColNamesJson + '); ' +
              '__last_row_count = ' + rqVar + '; __found = (' + rqVar + ' > 0); }';
          }
        }

        const exprSlice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');
        let retValCode = '';
        if (exprSlice.length === 0) {
          retValCode = buildDefaultReturnExpr();
        } else {
          const compiled = compileExpr(exprSlice);
          if (!procInfo.is_trigger && !procInfo.proretset && procInfo.rettype_typtype === 'b' && procInfo.rettype_sql !== 'void') {
            retValCode = '__rt.coerce(' + compiled.code + ', ' + JSON.stringify(procInfo.rettype_sql) + ', false)';
          } else {
            retValCode = compiled.code;
          }
        }
        if (subtranDepth > 0) {
          return '__ctrl = { type: "return", value: ' + retValCode + ' }; return;';
        }
        return (retValCode === 'undefined') ? 'return;' : ('return ' + retValCode + ';');
      }

      function parseRaiseStmt() {
        expectKeyword('RAISE');
        if (matchVal(';')) {
          return 'if (!__cur_err) throw __rt.makeError("P0001", "RAISE without parameters cannot be used outside an exception handler"); throw __cur_err;';
        }
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');

        let idx = 0;
        let level = 'EXCEPTION';
        if (idx < slice.length && slice[idx].type === 'ident' && !slice[idx].quoted) {
          const u = slice[idx].upper;
          if (u === 'DEBUG' || u === 'LOG' || u === 'INFO' || u === 'NOTICE' || u === 'WARNING' || u === 'EXCEPTION') {
            level = u;
            idx++;
          }
        }

        let usingIdx = -1;
        let pDepth = 0;
        for (let k = idx; k < slice.length; k++) {
          if (slice[k].value === '(' || slice[k].value === '[') pDepth++;
          else if (slice[k].value === ')' || slice[k].value === ']') pDepth--;
          else if (pDepth === 0 && slice[k].type === 'ident' && !slice[k].quoted && slice[k].upper === 'USING') {
            usingIdx = k;
            break;
          }
        }

        const mainPart = (usingIdx !== -1) ? slice.slice(idx, usingIdx) : slice.slice(idx);
        const usingPart = (usingIdx !== -1) ? slice.slice(usingIdx + 1) : null;

        let codeOrCond = null;
        let fmtExprCode = 'null';
        const fmtArgs = [];

        if (mainPart.length > 0) {
          let mIdx = 0;
          if (mainPart[0].type === 'ident' && !mainPart[0].quoted && mainPart[0].upper === 'SQLSTATE') {
            if (!mainPart[1] || mainPart[1].type !== 'string') syntaxError('expected SQLSTATE string literal', mainPart[1]);
            codeOrCond = mainPart[1].strVal;
            mIdx = 2;
            if (mIdx < mainPart.length && mainPart[mIdx].value === ',') mIdx++;
          } else if (mainPart[0].type === 'ident' && !lookupVar(mainPart[0].value) && (mainPart.length === 1 || mainPart[1].value === ',')) {
            codeOrCond = mainPart[0].value;
            mIdx = 1;
            if (mIdx < mainPart.length && mainPart[mIdx].value === ',') mIdx++;
          }

          if (mIdx < mainPart.length) {
            const parts = [];
            let cur = [];
            pDepth = 0;
            for (let k = mIdx; k < mainPart.length; k++) {
              if (mainPart[k].value === '(' || mainPart[k].value === '[') pDepth++;
              else if (mainPart[k].value === ')' || mainPart[k].value === ']') pDepth--;
              else if (pDepth === 0 && mainPart[k].value === ',') {
                parts.push(cur);
                cur = [];
                continue;
              }
              cur.push(mainPart[k]);
            }
            if (cur.length > 0) parts.push(cur);
            if (parts.length > 0) {
              fmtExprCode = compileExpr(parts[0]).code;
              for (let a = 1; a < parts.length; a++) {
                fmtArgs.push(compileExpr(parts[a]).code);
              }
            }
          }
        }

        let optsCode = 'null';
        if (usingPart && usingPart.length > 0) {
          const optProps = [];
          const items = [];
          let cur = [];
          pDepth = 0;
          for (let k = 0; k < usingPart.length; k++) {
            if (usingPart[k].value === '(' || usingPart[k].value === '[') pDepth++;
            else if (usingPart[k].value === ')' || usingPart[k].value === ']') pDepth--;
            else if (pDepth === 0 && usingPart[k].value === ',') {
              items.push(cur);
              cur = [];
              continue;
            }
            cur.push(usingPart[k]);
          }
          if (cur.length > 0) items.push(cur);
          for (let it = 0; it < items.length; it++) {
            const item = items[it];
            if (item.length < 3 || (item[1].value !== '=' && item[1].value !== ':=')) {
              syntaxError('invalid RAISE USING option', item[0]);
            }
            let optName = item[0].value.toLowerCase();
            if (optName === 'column_name') optName = 'column';
            else if (optName === 'constraint_name') optName = 'constraint';
            else if (optName === 'pg_datatype_name') optName = 'datatype';
            else if (optName === 'table_name') optName = 'table';
            else if (optName === 'schema_name') optName = 'schema';
            const optValCode = compileExpr(item.slice(2)).code;
            optProps.push(JSON.stringify(optName) + ': ' + optValCode);
          }
          optsCode = '{ ' + optProps.join(', ') + ' }';
        }

        return '__rt.doRaise(' + JSON.stringify(level) + ', ' + JSON.stringify(codeOrCond) + ', ' + fmtExprCode + ', [' + fmtArgs.join(', ') + '], ' + optsCode + ');';
      }

      function parseAssertStmt() {
        expectKeyword('ASSERT');
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');
        let commaIdx = -1;
        let pDepth = 0;
        for (let k = 0; k < slice.length; k++) {
          if (slice[k].value === '(' || slice[k].value === '[') pDepth++;
          else if (slice[k].value === ')' || slice[k].value === ']') pDepth--;
          else if (pDepth === 0 && slice[k].value === ',') {
            commaIdx = k;
            break;
          }
        }
        const condCode = compileExpr(commaIdx !== -1 ? slice.slice(0, commaIdx) : slice).code;
        const msgCode = (commaIdx !== -1) ? compileExpr(slice.slice(commaIdx + 1)).code : '"assertion failed"';
        return 'if (!__rt.truthy(' + condCode + ')) { throw __rt.makeError("P0004", ' + msgCode + ' || "assertion failed"); }';
      }

      function parsePerformStmt() {
        expectKeyword('PERFORM');
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');
        const rw = rewriteSqlTokensWithParams(slice, null);
        const resVar = '__pf_' + (++varCounter);
        return '{ const ' + resVar + ' = __pg.execute(' + JSON.stringify('SELECT ' + rw.sql) + ', [' + rw.params.join(', ') + ']); ' +
          '__last_row_count = Array.isArray(' + resVar + ') ? ' + resVar + '.length : (typeof ' + resVar + ' === "number" ? ' + resVar + ' : 0); ' +
          '__found = (__last_row_count > 0); }';
      }

      function parseExecuteStmt() {
        expectKeyword('EXECUTE');
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');

        let intoIdx = -1;
        let usingIdx = -1;
        let pDepth = 0;
        for (let k = 0; k < slice.length; k++) {
          if (slice[k].value === '(' || slice[k].value === '[') pDepth++;
          else if (slice[k].value === ')' || slice[k].value === ']') pDepth--;
          else if (pDepth === 0 && slice[k].type === 'ident' && !slice[k].quoted) {
            if (slice[k].upper === 'INTO' && intoIdx === -1) intoIdx = k;
            else if (slice[k].upper === 'USING' && usingIdx === -1) usingIdx = k;
          }
        }

        let queryEnd = slice.length;
        if (intoIdx !== -1 && intoIdx < queryEnd) queryEnd = intoIdx;
        if (usingIdx !== -1 && usingIdx < queryEnd) queryEnd = usingIdx;

        const queryCode = compileExpr(slice.slice(0, queryEnd)).code;

        let isStrict = false;
        let targetLValues = null;
        if (intoIdx !== -1) {
          const intoEnd = (usingIdx !== -1 && usingIdx > intoIdx) ? usingIdx : slice.length;
          let intoSlice = slice.slice(intoIdx + 1, intoEnd);
          if (intoSlice.length > 0 && intoSlice[0].type === 'ident' && !intoSlice[0].quoted && intoSlice[0].upper === 'STRICT') {
            isStrict = true;
            intoSlice = intoSlice.slice(1);
          }
          const tParts = [];
          let cur = [];
          for (let k = 0; k < intoSlice.length; k++) {
            if (intoSlice[k].value === ',') {
              tParts.push(cur);
              cur = [];
            } else {
              cur.push(intoSlice[k]);
            }
          }
          if (cur.length > 0) tParts.push(cur);
          targetLValues = tParts.map(function(tp) { return parseTargetLValue(tp); });
        }

        const usingArgs = [];
        if (usingIdx !== -1) {
          const usingEnd = (intoIdx !== -1 && intoIdx > usingIdx) ? intoIdx : slice.length;
          const uSlice = slice.slice(usingIdx + 1, usingEnd);
          let cur = [];
          pDepth = 0;
          for (let k = 0; k < uSlice.length; k++) {
            if (uSlice[k].value === '(' || uSlice[k].value === '[') pDepth++;
            else if (uSlice[k].value === ')' || uSlice[k].value === ']') pDepth--;
            else if (pDepth === 0 && uSlice[k].value === ',') {
              usingArgs.push(compileExpr(cur).code);
              cur = [];
              continue;
            }
            cur.push(uSlice[k]);
          }
          if (cur.length > 0) usingArgs.push(compileExpr(cur).code);
        }

        const qVar = '__dq_' + (++varCounter);
        const rVar = '__dr_' + varCounter;
        let code = '{\nconst ' + qVar + ' = ' + queryCode + ';\n' +
          'if (' + qVar + ' === null || ' + qVar + ' === undefined) throw __rt.makeError("22004", "query string argument of EXECUTE is null");\n' +
          'const ' + rVar + ' = __pg.execute(String(' + qVar + '), [' + usingArgs.join(', ') + ']);\n';

        if (targetLValues) {
          code += 'const __rows = Array.isArray(' + rVar + ') ? ' + rVar + ' : [];\n';
          if (isStrict) {
            code += 'if (__rows.length === 0) throw __rt.makeError("P0002", "query returned no rows");\n';
            code += 'if (__rows.length > 1) throw __rt.makeError("P0003", "query returned more than one row");\n';
          }
          code += '__found = (__rows.length > 0);\n';
          code += '__last_row_count = (__rows.length > 0 ? 1 : 0);\n';
          code += emitRowToTargets('(__rows.length > 0 ? __rows[0] : null)', targetLValues) + '\n';
        } else {
          code += '__last_row_count = typeof ' + rVar + ' === "number" ? ' + rVar + ' : (Array.isArray(' + rVar + ') ? ' + rVar + '.length : 0);\n';
          code += '__found = (__last_row_count > 0);\n';
        }
        code += '}';
        return code;
      }

      function parseGetDiagnosticsStmt() {
        expectKeyword('GET');
        const isStacked = Boolean(matchKeyword('STACKED'));
        if (!isStacked) matchKeyword('CURRENT');
        expectKeyword('DIAGNOSTICS');
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');

        const items = [];
        let cur = [];
        for (let k = 0; k < slice.length; k++) {
          if (slice[k].value === ',') {
            items.push(cur);
            cur = [];
          } else {
            cur.push(slice[k]);
          }
        }
        if (cur.length > 0) items.push(cur);

        const lines = [];
        if (isStacked) {
          lines.push('if (!__cur_err) throw __rt.makeError("0Z002", "GET STACKED DIAGNOSTICS cannot be used outside an exception handler");');
        }
        for (let i = 0; i < items.length; i++) {
          const it = items[i];
          let eqIdx = -1;
          for (let k = 0; k < it.length; k++) {
            if (it[k].value === '=' || it[k].value === ':=') {
              eqIdx = k;
              break;
            }
          }
          if (eqIdx === -1 || eqIdx + 1 >= it.length) syntaxError('invalid GET DIAGNOSTICS item', it[0]);
          const target = parseTargetLValue(it.slice(0, eqIdx));
          const diagKind = it[eqIdx + 1].upper;
          let valExpr = 'null';
          if (isStacked) {
            if (diagKind === 'RETURNED_SQLSTATE') valExpr = '__sqlstate';
            else if (diagKind === 'MESSAGE_TEXT') valExpr = '__sqlerrm';
            else if (diagKind === 'PG_EXCEPTION_DETAIL') valExpr = '__err_detail';
            else if (diagKind === 'PG_EXCEPTION_HINT') valExpr = '__err_hint';
            else if (diagKind === 'PG_EXCEPTION_CONTEXT') valExpr = '__err_context';
            else if (diagKind === 'SCHEMA_NAME') valExpr = '__err_schema';
            else if (diagKind === 'TABLE_NAME') valExpr = '__err_table';
            else if (diagKind === 'COLUMN_NAME') valExpr = '__err_column';
            else if (diagKind === 'PG_DATATYPE_NAME') valExpr = '__err_datatype';
            else if (diagKind === 'CONSTRAINT_NAME') valExpr = '__err_constraint';
            else syntaxError('unrecognized GET STACKED DIAGNOSTICS item "' + it[eqIdx + 1].raw + '"', it[eqIdx + 1]);
          } else {
            if (diagKind === 'ROW_COUNT') valExpr = '__last_row_count';
            else if (diagKind === 'PG_CONTEXT') valExpr = JSON.stringify('PL/pgSQL function ' + (procInfo.proname || 'inline_code_block'));
            else if (diagKind === 'PG_ROUTINE_OID') valExpr = String(procInfo.fn_oid || null);
            else syntaxError('unrecognized GET DIAGNOSTICS item "' + it[eqIdx + 1].raw + '"', it[eqIdx + 1]);
          }
          lines.push(target.assignCode(valExpr));
        }
        return lines.join('\n');
      }

      function parseOpenStmt() {
        expectKeyword('OPEN');
        const curTok = next();
        const curVar = curTok ? lookupVar(curTok.value) : null;
        if (!curVar || curVar.kind !== 'cursor') {
          syntaxError('"' + (curTok ? curTok.raw : '') + '" is not a cursor variable', curTok);
        }
        if (matchKeyword('FOR')) {
          if (matchKeyword('EXECUTE')) {
            const rest = collectUntil(function(t) { return t.value === ';'; });
            expectVal(';');
            let usingIdx = -1;
            let pD = 0;
            for (let k = 0; k < rest.length; k++) {
              if (rest[k].value === '(' || rest[k].value === '[') pD++;
              else if (rest[k].value === ')' || rest[k].value === ']') pD--;
              else if (pD === 0 && rest[k].type === 'ident' && !rest[k].quoted && rest[k].upper === 'USING') {
                usingIdx = k;
                break;
              }
            }
            const dynCode = compileExpr(usingIdx !== -1 ? rest.slice(0, usingIdx) : rest).code;
            const uArgs = [];
            if (usingIdx !== -1) {
              const uSlice = rest.slice(usingIdx + 1);
              let cur = [];
              pD = 0;
              for (let k = 0; k < uSlice.length; k++) {
                if (uSlice[k].value === '(' || uSlice[k].value === '[') pD++;
                else if (uSlice[k].value === ')' || uSlice[k].value === ']') pD--;
                else if (pD === 0 && uSlice[k].value === ',') {
                  uArgs.push(compileExpr(cur).code);
                  cur = [];
                  continue;
                }
                cur.push(uSlice[k]);
              }
              if (cur.length > 0) uArgs.push(compileExpr(cur).code);
            }
            return curVar.jsName + ' = __rt.openCursor(' + dynCode + ', [' + uArgs.join(', ') + ']);';
          } else {
            const qSlice = collectUntil(function(t) { return t.value === ';'; });
            expectVal(';');
            const rw = rewriteSqlTokensWithParams(qSlice, null);
            return curVar.jsName + ' = __rt.openCursor(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + ']);';
          }
        }

        const argExprs = [];
        if (matchVal('(')) {
          const argSlice = collectUntil(function(t) { return t.value === ')'; });
          expectVal(')');
          let cur = [];
          let pD = 0;
          for (let k = 0; k < argSlice.length; k++) {
            if (argSlice[k].value === '(' || argSlice[k].value === '[') pD++;
            else if (argSlice[k].value === ')' || argSlice[k].value === ']') pD--;
            else if (pD === 0 && argSlice[k].value === ',') {
              argExprs.push(compileExpr(cur).code);
              cur = [];
              continue;
            }
            cur.push(argSlice[k]);
          }
          if (cur.length > 0) argExprs.push(compileExpr(cur).code);
        }
        expectVal(';');
        const extraScope = Object.create(null);
        if (curVar.cursorParams) {
          for (let p = 0; p < curVar.cursorParams.length; p++) {
            extraScope[curVar.cursorParams[p].name] = {
              jsName: (argExprs[p] !== undefined ? argExprs[p] : 'null'),
              sqlType: curVar.cursorParams[p].sqlType,
              kind: 'scalar'
            };
          }
        }
        const rw = rewriteSqlTokensWithParams(curVar.queryTokens, extraScope);
        return curVar.jsName + ' = __rt.openCursor(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + ']);';
      }

      function parseFetchStmt() {
        expectKeyword('FETCH');
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');
        let intoIdx = -1;
        for (let k = 0; k < slice.length; k++) {
          if (slice[k].type === 'ident' && !slice[k].quoted && slice[k].upper === 'INTO') {
            intoIdx = k;
            break;
          }
        }
        if (intoIdx === -1) syntaxError('expected INTO in FETCH statement', slice[0]);
        const head = slice.slice(0, intoIdx);
        const tail = slice.slice(intoIdx + 1);

        let mode = 'NEXT';
        let countExpr = '1';
        const curTok = head[head.length - 1];
        const curVar = curTok ? lookupVar(curTok.value) : null;
        if (!curVar) syntaxError('unknown cursor "' + (curTok ? curTok.raw : '') + '"', curTok);

        if (head.length > 1) {
          const dirTok = head[0];
          const u = dirTok.upper;
          if (u === 'NEXT' || u === 'PRIOR' || u === 'FIRST' || u === 'LAST') {
            mode = u;
          } else if (u === 'FORWARD' || u === 'BACKWARD' || u === 'RELATIVE' || u === 'ABSOLUTE') {
            mode = u;
            let countEnd = head.length - 1;
            if (countEnd > 1 && head[countEnd - 1].type === 'ident' && !head[countEnd - 1].quoted &&
                (head[countEnd - 1].upper === 'FROM' || head[countEnd - 1].upper === 'IN')) {
              countEnd--;
            }
            const countSlice = head.slice(1, countEnd);
            if (countSlice.length > 0) {
              countExpr = (countSlice.length === 1 && countSlice[0].upper === 'ALL') ? '"ALL"' : compileExpr(countSlice).code;
            }
          }
        }

        const tParts = [];
        let cur = [];
        for (let k = 0; k < tail.length; k++) {
          if (tail[k].value === ',') {
            tParts.push(cur);
            cur = [];
          } else {
            cur.push(tail[k]);
          }
        }
        if (cur.length > 0) tParts.push(cur);
        const targetLValues = tParts.map(function(tp) { return parseTargetLValue(tp); });

        const fVar = '__fr_' + (++varCounter);
        return '{\nconst ' + fVar + ' = __rt.fetchCursor(' + curVar.jsName + ', ' + JSON.stringify(mode) + ', ' + countExpr + ');\n' +
          '__found = (' + fVar + ' != null);\n' +
          '__last_row_count = (' + fVar + ' != null ? 1 : 0);\n' +
          emitRowToTargets(fVar, targetLValues) + '\n}';
      }

      function parseMoveStmt() {
        expectKeyword('MOVE');
        const slice = collectUntil(function(t) { return t.value === ';'; });
        expectVal(';');
        const curTok = slice[slice.length - 1];
        const curVar = curTok ? lookupVar(curTok.value) : null;
        if (!curVar) syntaxError('unknown cursor "' + (curTok ? curTok.raw : '') + '"', curTok);
        let mode = 'NEXT';
        let countExpr = '1';
        if (slice.length > 1) {
          const u = slice[0].upper;
          if (u === 'NEXT' || u === 'PRIOR' || u === 'FORWARD' || u === 'BACKWARD' || u === 'RELATIVE' || u === 'ABSOLUTE') {
            mode = u;
            let countEnd = slice.length - 1;
            if (countEnd > 1 && slice[countEnd - 1].type === 'ident' && !slice[countEnd - 1].quoted &&
                (slice[countEnd - 1].upper === 'FROM' || slice[countEnd - 1].upper === 'IN')) {
              countEnd--;
            }
            const countSlice = slice.slice(1, countEnd);
            if (countSlice.length > 0) {
              countExpr = (countSlice.length === 1 && countSlice[0].upper === 'ALL') ? '"ALL"' : compileExpr(countSlice).code;
            }
          }
        }
        return '__found = __rt.moveCursor(' + curVar.jsName + ', ' + JSON.stringify(mode) + ', ' + countExpr + '); __last_row_count = (__found ? 1 : 0);';
      }

      function parseCloseStmt() {
        expectKeyword('CLOSE');
        const curTok = next();
        const curVar = curTok ? lookupVar(curTok.value) : null;
        if (!curVar) syntaxError('unknown cursor "' + (curTok ? curTok.raw : '') + '"', curTok);
        expectVal(';');
        return '__rt.closeCursor(' + curVar.jsName + ');';
      }

      function compileStaticSqlStmt(stmtTokens) {
        const STOP_INTO_KW = {
          FROM: 1, WHERE: 1, GROUP: 1, HAVING: 1, WINDOW: 1, UNION: 1,
          INTERSECT: 1, EXCEPT: 1, ORDER: 1, LIMIT: 1, OFFSET: 1, FETCH: 1, FOR: 1
        };

        let intoStart = -1;
        let intoEnd = -1;
        let isStrict = false;
        const targetSlices = [];

        let pDepth = 0;
        let cDepth = 0;
        for (let k = 0; k < stmtTokens.length; k++) {
          const tk = stmtTokens[k];
          if (tk.value === '(' || tk.value === '[') pDepth++;
          else if (tk.value === ')' || tk.value === ']') { if (pDepth > 0) pDepth--; }
          else if (tk.type === 'ident' && !tk.quoted) {
            if (tk.upper === 'CASE') cDepth++;
            else if (tk.upper === 'END' && cDepth > 0) cDepth--;
            else if (pDepth === 0 && cDepth === 0 && tk.upper === 'INTO') {
              const prev = k > 0 ? stmtTokens[k - 1] : null;
              if (prev && prev.type === 'ident' && !prev.quoted && (prev.upper === 'INSERT' || prev.upper === 'MERGE')) {
                continue;
              }
              intoStart = k;
              let j = k + 1;
              if (j < stmtTokens.length && stmtTokens[j].type === 'ident' && !stmtTokens[j].quoted && stmtTokens[j].upper === 'STRICT') {
                isStrict = true;
                j++;
              }
              let curTarget = [];
              while (j < stmtTokens.length) {
                const tj = stmtTokens[j];
                if (tj.type === 'ident' && !tj.quoted && STOP_INTO_KW[tj.upper]) {
                  break;
                }
                if (tj.value === ',') {
                  if (curTarget.length > 0) targetSlices.push(curTarget);
                  curTarget = [];
                } else {
                  curTarget.push(tj);
                }
                j++;
              }
              if (curTarget.length > 0) targetSlices.push(curTarget);
              intoEnd = j;
              break;
            }
          }
        }

        if (intoStart !== -1 && targetSlices.length > 0) {
          const targetLValues = targetSlices.map(function(ts) { return parseTargetLValue(ts); });
          const beforeSlice = stmtTokens.slice(0, intoStart);
          const afterSlice = stmtTokens.slice(intoEnd);
          const combinedSlice = beforeSlice.concat(afterSlice);

          let rw;
          if (afterSlice.length > 0 && beforeSlice.length > 0) {
            const rw1 = rewriteSqlTokensWithParams(beforeSlice, null);
            const rw2 = rewriteSqlTokensWithParams(afterSlice, null);
            let shiftedSql2 = rw2.sql;
            if (rw1.params.length > 0 && rw2.params.length > 0) {
              shiftedSql2 = rw2.sql.replace(/\$(\d+)/g, function(_, d) {
                return '$' + (parseInt(d, 10) + rw1.params.length);
              });
            }
            rw = { sql: rw1.sql + ' ' + shiftedSql2, params: rw1.params.concat(rw2.params) };
          } else {
            rw = rewriteSqlTokensWithParams(combinedSlice, null);
          }

          const rVar = '__sr_' + (++varCounter);
          let code = '{\nconst ' + rVar + ' = __pg.execute(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + ']);\n' +
            'const __rows = Array.isArray(' + rVar + ') ? ' + rVar + ' : [];\n';
          if (isStrict) {
            code += 'if (__rows.length === 0) throw __rt.makeError("P0002", "query returned no rows");\n';
            code += 'if (__rows.length > 1) throw __rt.makeError("P0003", "query returned more than one row");\n';
          }
          code += '__found = (__rows.length > 0);\n';
          code += '__last_row_count = (__rows.length > 0 ? 1 : 0);\n';
          code += emitRowToTargets('(__rows.length > 0 ? __rows[0] : null)', targetLValues) + '\n}';
          return code;
        }

        const rw = rewriteSqlTokensWithParams(stmtTokens, null);
        const rVar = '__sx_' + (++varCounter);
        return '{\nconst ' + rVar + ' = __pg.execute(' + JSON.stringify(rw.sql) + ', [' + rw.params.join(', ') + ']);\n' +
          '__last_row_count = typeof ' + rVar + ' === "number" ? ' + rVar + ' : (Array.isArray(' + rVar + ') ? ' + rVar + '.length : 0);\n' +
          '__found = (__last_row_count > 0);\n}';
      }

      while (peek() && peek().type === 'directive') next();
      const topBlockCode = parseBlock(null);
      const defaultRet = buildDefaultReturnExpr();

      const fullJs = [
        'const __pg = (typeof plv8 !== "undefined") ? plv8 : pljs;',
        'const __rt = globalThis.__plpgsql_v8_rt;',
        'let __found = false;',
        'let __last_row_count = 0;',
        'let __ctrl = null;',
        'let __cur_err = null;',
        'let __sqlstate = "00000";',
        'let __sqlerrm = "";',
        'let __err_detail = "";',
        'let __err_hint = "";',
        'let __err_context = "";',
        'let __err_schema = "";',
        'let __err_table = "";',
        'let __err_column = "";',
        'let __err_datatype = "";',
        'let __err_constraint = "";'
      ].concat(initLines).concat([
        topBlockCode,
        (defaultRet === 'undefined') ? 'return;' : ('return ' + defaultRet + ';')
      ]).join('\n');

      return fullJs;
    }

    return compilePlpgsql;
  })();
}
return globalThis.__plpgsql_v8_compile(arguments[0], arguments[1]);
$plpgsql_v8_Compiler$ LANGUAGE plv8;
REVOKE ALL ON FUNCTION plv8_plpgsql_handler() FROM PUBLIC;

DO $plpgsql_v8_schema_helper$
BEGIN
  IF pg_catalog.to_regnamespace('plv8') IS NOT NULL AND pg_catalog.has_schema_privilege('plv8', 'CREATE') THEN
    EXECUTE $ddl$
      CREATE OR REPLACE FUNCTION plv8.compile_plpgsql(src text, meta jsonb DEFAULT NULL)
      RETURNS text AS
      $plpgsql_v8_CompileHelper$
        const __pg = (typeof plv8 !== 'undefined') ? plv8 : pljs;
        if (typeof globalThis.__plpgsql_v8_compile !== 'function') {
          const rows = __pg.execute("SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = 'plv8_plpgsql_handler()'::regprocedure");
          const initFn = new Function(rows[0].prosrc);
          initFn.call(globalThis, 'BEGIN RETURN; END;', {});
        }
        return globalThis.__plpgsql_v8_compile(src, meta || {});
      $plpgsql_v8_CompileHelper$ LANGUAGE plv8;
      REVOKE ALL ON FUNCTION plv8.compile_plpgsql(text, jsonb) FROM PUBLIC;
    $ddl$;
  END IF;
END;
$plpgsql_v8_schema_helper$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION compile_plpgsql(src text, meta jsonb DEFAULT NULL)
RETURNS text AS
$plpgsql_v8_CompileHelper_Unqual$
  const __pg = (typeof plv8 !== 'undefined') ? plv8 : pljs;
  if (typeof globalThis.__plpgsql_v8_compile !== 'function') {
    const rows = __pg.execute("SELECT prosrc FROM pg_catalog.pg_proc WHERE oid = 'plv8_plpgsql_handler()'::regprocedure");
    const initFn = new Function(rows[0].prosrc);
    initFn.call(globalThis, 'BEGIN RETURN; END;', {});
  }
  return globalThis.__plpgsql_v8_compile(src, meta || {});
$plpgsql_v8_CompileHelper_Unqual$ LANGUAGE plv8;
REVOKE ALL ON FUNCTION compile_plpgsql(text, jsonb) FROM PUBLIC;

CREATE OR REPLACE TRUSTED LANGUAGE pl_pgsql_v8
	HANDLER plv8_plpgsql_handler
	INLINE plv8_inline_handler
	VALIDATOR plv8_call_validator;

CREATE OR REPLACE TRUSTED LANGUAGE plpgsql_v8
	HANDLER plv8_plpgsql_handler
	INLINE plv8_inline_handler
	VALIDATOR plv8_call_validator;

CREATE OR REPLACE TRUSTED LANGUAGE "pl/pgsql+v8"
	HANDLER plv8_plpgsql_handler
	INLINE plv8_inline_handler
	VALIDATOR plv8_call_validator;
$tle_pkg_pl_pgsql_v8$
);
