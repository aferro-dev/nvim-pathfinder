"""Update or delete exactly one unchanged record, using bound parameters."""
import json
import sqlite3
import sys
from pathlib import Path


def identifier(name):
    return '"' + name.replace('"', '""') + '"'


def value(entry):
    if isinstance(entry, dict) and set(entry) == {'$binary'}:
        return bytes.fromhex(entry['$binary'])
    if isinstance(entry, (dict, list)):
        raise ValueError('SQLite columns require scalar values')
    return entry


try:
    data = json.load(sys.stdin)
    old, new = data['original'], data.get('replacement')
    connection = sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=rw', uri=True, timeout=5)
    with connection:
        connection.execute('BEGIN IMMEDIATE')
        columns = list(connection.execute('SELECT * FROM pragma_table_xinfo(?)', (data['table'],)))
        keys = [col[1] for col in columns if col[5]]
        if not keys or any(old.get(key) is None for key in keys):
            raise ValueError('A primary key is required')
        if new is not None and (set(new) != set(old) or any(new[key] != old[key] for key in keys)):
            raise ValueError('Keep all columns and the original primary key')
        where = ' AND '.join(identifier(key) + ' IS ?' for key in old)
        parameters = [value(entry) for entry in old.values()]
        table = identifier(data['table'])
        if new is None:
            result = connection.execute(f'DELETE FROM {table} WHERE {where}', parameters)
        else:
            changed = [key for key in old if old[key] != new[key]]
            if not changed:
                raise ValueError('No changes to save')
            assignments = ', '.join(identifier(key) + ' = ?' for key in changed)
            result = connection.execute(f'UPDATE {table} SET {assignments} WHERE {where}',
                                        [value(new[key]) for key in changed] + parameters)
        if result.rowcount != 1:
            raise ValueError('Record changed or disappeared; reload before retrying')
    connection.close()
except Exception:
    print('Write failed. Reload the record and check values, constraints and permissions.', file=sys.stderr)
    sys.exit(1)
