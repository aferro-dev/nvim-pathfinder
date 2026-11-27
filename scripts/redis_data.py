"""Read Redis keys over RESP2 using only the Python standard library."""
import base64
import json
import socket
import ssl
import sys
from urllib.parse import unquote, urlsplit

PREVIEW = 100
STRING_LIMIT = 16384


class Redis:
    def __init__(self, url):
        parts = urlsplit(url)
        if parts.scheme not in ('redis', 'rediss') or not parts.hostname:
            raise ValueError('Use redis[s]://[[username:]password@]host[:port][/database]')
        if parts.query or parts.fragment:
            raise ValueError('Redis URL query parameters and fragments are not supported')
        database = parts.path.lstrip('/') or '0'
        if not database.isascii() or not database.isdigit():
            raise ValueError('Redis database must be a non-negative integer')
        self.socket = socket.create_connection((parts.hostname, parts.port or 6379), timeout=8)
        if parts.scheme == 'rediss':
            self.socket = ssl.create_default_context().wrap_socket(self.socket, server_hostname=parts.hostname)
        self.file = self.socket.makefile('rb')
        if parts.password is not None:
            password = unquote(parts.password)
            if parts.username:
                self.call('AUTH', unquote(parts.username), password)
            else:
                self.call('AUTH', password)
        elif parts.username:
            raise ValueError('Redis authentication requires a password')
        self.call('SELECT', database)

    def close(self):
        self.file.close()
        self.socket.close()

    def read(self):
        prefix = self.file.read(1)
        line = self.file.readline()
        if not line.endswith(b'\r\n'):
            raise ValueError('Redis closed the connection or returned an invalid response')
        line = line[:-2]
        if prefix == b'-':
            # Server errors may contain user data. Never print their payload.
            code = line.split(b' ', 1)[0].decode('ascii', errors='replace')
            known = {'NOAUTH', 'WRONGPASS', 'NOPERM', 'MOVED', 'ASK', 'WRONGTYPE'}
            raise ValueError('Redis ' + (code if code in known else 'command failed')
                             + '; check credentials, permissions and endpoint')
        if prefix == b'+':
            return line
        if prefix == b':':
            return int(line)
        if prefix == b'$':
            length = int(line)
            if length == -1:
                return None
            data = self.file.read(length)
            if len(data) != length or self.file.read(2) != b'\r\n':
                raise ValueError('Incomplete Redis response')
            return data
        if prefix == b'*':
            length = int(line)
            return None if length == -1 else [self.read() for _ in range(length)]
        raise ValueError('Unsupported Redis protocol response')

    def call(self, *args):
        encoded = [arg if isinstance(arg, bytes) else str(arg).encode('utf-8') for arg in args]
        self.socket.sendall(b'*%d\r\n' % len(encoded) + b''.join(
            b'$%d\r\n' % len(arg) + arg + b'\r\n' for arg in encoded))
        return self.read()


def readable(value):
    if isinstance(value, bytes):
        try:
            return value.decode('utf-8')
        except UnicodeDecodeError:
            return {'base64': base64.b64encode(value).decode('ascii')}
    if isinstance(value, list):
        return [readable(item) for item in value]
    return value


def record(client, key):
    kind = client.call('TYPE', key).decode('ascii')
    if kind == 'none':
        return None
    ttl = client.call('TTL', key)
    truncated = False
    if kind == 'string':
        size = client.call('STRLEN', key)
        value = client.call('GETRANGE', key, 0, STRING_LIMIT - 1)
        truncated = size > STRING_LIMIT
    elif kind == 'list':
        size = client.call('LLEN', key)
        value = client.call('LRANGE', key, 0, PREVIEW - 1)
        truncated = size > PREVIEW
    elif kind == 'hash':
        size = client.call('HLEN', key)
        cursor, pairs = client.call('HSCAN', key, 0, 'COUNT', PREVIEW)
        value = [[pairs[i], pairs[i + 1]] for i in range(0, min(len(pairs), PREVIEW * 2), 2)]
        truncated = cursor != b'0' or len(pairs) > PREVIEW * 2
    elif kind == 'set':
        size = client.call('SCARD', key)
        cursor, members = client.call('SSCAN', key, 0, 'COUNT', PREVIEW)
        value = members[:PREVIEW]
        truncated = cursor != b'0' or len(members) > PREVIEW
    elif kind == 'zset':
        size = client.call('ZCARD', key)
        pairs = client.call('ZRANGE', key, 0, PREVIEW - 1, 'WITHSCORES')
        value = [[pairs[i], pairs[i + 1]] for i in range(0, len(pairs), 2)]
        truncated = size > PREVIEW
    elif kind == 'stream':
        size = client.call('XLEN', key)
        value = client.call('XRANGE', key, '-', '+', 'COUNT', PREVIEW)
        truncated = size > PREVIEW
    else:
        size, value = None, 'Preview unavailable for this Redis type'
    # Keys may expire while browsing. Treat that as a disappearing row.
    if ttl == -2 or client.call('EXISTS', key) == 0:
        return None
    return dict(key=readable(key), type=kind, ttl=ttl, size=size,
                value=readable(value), truncated=truncated)


def rows(client, limit, offset):
    cursor, seen, result, skipped = b'0', set(), [], 0
    while True:
        cursor, keys = client.call('SCAN', cursor, 'COUNT', 100)
        for key in keys:
            if key in seen:
                continue
            seen.add(key)
            if skipped < offset:
                skipped += 1
                continue
            try:
                row = record(client, key)
            except ValueError as exc:
                # Concurrent changes in a key's type do not abort the whole page.
                if 'WRONGTYPE' in str(exc):
                    continue
                raise
            if row is not None:
                result.append(row)
                if len(result) >= limit:
                    return result
        if cursor == b'0':
            return result


def raw(value):
    if isinstance(value, str):
        return value.encode('utf-8')
    if isinstance(value, dict) and set(value) == {'base64'}:
        return base64.b64decode(value['base64'], validate=True)
    raise ValueError('Redis keys and string values must be text or a base64 object')


def write(client, payload):
    original, replacement = payload['original'], payload.get('replacement')
    if original.get('truncated') is not False:
        raise ValueError('Redis partial previews cannot be edited or deleted')
    key = raw(original['key'])
    client.call('WATCH', key)
    current = record(client, key)
    # TTL naturally decreases between reads. WATCH also catches expiry and writes
    # that occur after this comparison, before the transaction is committed.
    fields = ('key', 'type', 'size', 'value', 'truncated')
    if current is None or any(current.get(field) != original.get(field) for field in fields):
        raise ValueError('Redis key changed or disappeared; reload before retrying')
    if replacement is not None:
        if original['type'] != 'string':
            raise ValueError('Redis editing supports string values only')
        if set(replacement) != set(original) or any(
                replacement[field] != original[field] for field in original if field != 'value'):
            raise ValueError('Redis key and metadata cannot be changed; edit value only')
        value = raw(replacement['value'])
    client.call('MULTI')
    if replacement is None:
        client.call('DEL', key)
    else:
        client.call('SET', key, value, 'KEEPTTL')
    if client.call('EXEC') is None:
        raise ValueError('Redis key changed or disappeared; reload before retrying')
    return {'ok': True}


def main():
    payload = json.load(sys.stdin)
    client = Redis(payload['url'])
    try:
        if sys.argv[1] == 'schema':
            client.call('PING')
            result = [dict(name='Keys', columns=[dict(name=name, type=kind, pk=name == 'key')
                       for name, kind in [('key', 'bytes'), ('type', 'string'), ('ttl', 'seconds'),
                                          ('size', 'integer'), ('value', 'preview'), ('truncated', 'boolean')]],
                           foreign_keys=[])]
        elif sys.argv[1] == 'write':
            result = write(client, payload)
        else:
            result = rows(client, int(sys.argv[2]), int(sys.argv[3]))
        print(json.dumps(result, ensure_ascii=True))
    finally:
        client.close()


if __name__ == '__main__':
    try:
        main()
    except ValueError as exc:
        # Only our own fixed validation/command messages are exposed.
        message = str(exc)
        if not message.startswith(('Redis ', 'Use redis', 'Incomplete Redis', 'Unsupported Redis')):
            message = 'Invalid Redis URL or response'
        print(message, file=sys.stderr)
        sys.exit(1)
    except Exception:
        print('Unable to read Redis. Check the endpoint, TLS certificate and server availability.', file=sys.stderr)
        sys.exit(1)
