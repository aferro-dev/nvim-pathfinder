"""Read SQLite metadata without creating or modifying the database."""
import json
import sqlite3
import sys
from pathlib import Path

try:
    path = Path(sys.argv[1]).resolve()
    connection = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=5)
    connection.execute('PRAGMA query_only = ON')
    tables = []
    for (name,) in connection.execute("SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"):
        columns = [dict(name=row[1], type=row[2] or 'ANY', nullable=not (row[3] or row[5]), pk=bool(row[5]))
                   for row in connection.execute('SELECT * FROM pragma_table_xinfo(?)', (name,))]
        foreign_keys = []
        for row in connection.execute('SELECT * FROM pragma_foreign_key_list(?)', (name,)):
            target = row[4]
            if target is None:
                keys = sorted((r for r in connection.execute('SELECT * FROM pragma_table_xinfo(?)', (row[2],)) if r[5]), key=lambda r: r[5])
                target = keys[row[1]][1] if row[1] < len(keys) else '?'
            foreign_keys.append(dict(column=row[3], target_table=row[2], target_column=target))
        tables.append(dict(name=name, columns=columns, foreign_keys=foreign_keys))
    print(json.dumps(tables))
    connection.close()
except Exception:
    print('Unable to read SQLite schema. Check the file path and database format.', file=sys.stderr)
    sys.exit(1)
