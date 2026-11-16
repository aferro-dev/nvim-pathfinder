"""Fetch one bounded page using a read-only SQLite connection."""
import json
import sqlite3
import sys
from pathlib import Path

try:
    connection = sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=ro', uri=True, timeout=5)
    connection.execute('PRAGMA query_only = ON')
    connection.row_factory = sqlite3.Row
    table = '"' + sys.argv[2].replace('"', '""') + '"'
    columns = list(connection.execute('SELECT * FROM pragma_table_xinfo(?)', (sys.argv[2],)))
    keys = sorted((row for row in columns if row['pk']), key=lambda row: row['pk'])
    order = ', '.join('"' + row['name'].replace('"', '""') + '"' for row in keys) or 'rowid'
    rows = connection.execute(f'SELECT * FROM {table} ORDER BY {order} LIMIT ? OFFSET ?',
                              (int(sys.argv[3]), int(sys.argv[4])))
    print(json.dumps([dict(row) for row in rows], default=lambda value: {'$binary': value.hex()}))
    connection.close()
except Exception:
    print('Unable to read SQLite data. Check table access and database format.', file=sys.stderr)
    sys.exit(1)
