BEGIN READ ONLY;
SET LOCAL statement_timeout = '10s';
SELECT coalesce(json_agg(t ORDER BY t.name), '[]'::json) FROM (
  SELECT n.nspname || '.' || c.relname AS name, n.nspname AS "schema", c.relname AS "table",
    coalesce((SELECT json_agg(json_build_object(
      'name', a.attname, 'type', pg_catalog.format_type(a.atttypid, a.atttypmod),
      'nullable', NOT a.attnotnull,
      'pk', EXISTS (SELECT 1 FROM pg_catalog.pg_constraint k WHERE k.conrelid=c.oid AND k.contype='p' AND a.attnum=ANY(k.conkey))
    ) ORDER BY a.attnum) FROM pg_catalog.pg_attribute a
      WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped), '[]'::json) AS columns,
    coalesce((SELECT json_agg(json_build_object(
      'column', src.attname, 'target_table', tn.nspname || '.' || tc.relname, 'target_column', dst.attname
    ) ORDER BY k.oid, keys.pos)
      FROM pg_catalog.pg_constraint k
      CROSS JOIN LATERAL generate_subscripts(k.conkey, 1) keys(pos)
      JOIN pg_catalog.pg_class tc ON tc.oid=k.confrelid
      JOIN pg_catalog.pg_namespace tn ON tn.oid=tc.relnamespace
      JOIN pg_catalog.pg_attribute src ON src.attrelid=c.oid AND src.attnum=k.conkey[keys.pos]
      JOIN pg_catalog.pg_attribute dst ON dst.attrelid=tc.oid AND dst.attnum=k.confkey[keys.pos]
      WHERE k.conrelid=c.oid AND k.contype='f'), '[]'::json) AS foreign_keys
  FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relkind IN ('r', 'p') AND n.nspname NOT IN ('pg_catalog', 'information_schema')
    AND n.nspname !~ '^pg_toast' AND n.nspname !~ '^pg_temp'
    AND (pg_catalog.has_table_privilege(c.oid, 'SELECT') OR pg_catalog.has_any_column_privilege(c.oid, 'SELECT'))
) t;
ROLLBACK;
