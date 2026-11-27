"""Redis integration; set REDIS_TEST_URL to a disposable database (defaults to DB 15)."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
repo = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('redis_data', repo / 'scripts/redis_data.py')
redis_data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(redis_data)
url = os.environ.get('REDIS_TEST_URL', 'redis://:pathfinder-test@127.0.0.1:16379/15')
client = redis_data.Redis(url)
prefix = 'pathfinder-test:'
created = []


def command(*args):
    created.append(args[1])
    return client.call(*args)


def run(mode, *args, connection=url, pattern="*", kind=None):
    return subprocess.run([sys.executable, str(repo / 'scripts/redis_data.py'), mode, *map(str, args)],
                          input=json.dumps({'url': connection, 'pattern': pattern, 'kind': kind}), capture_output=True, text=True, timeout=20)


try:
    command('SET', prefix + 'string', 'hello\nworld')
    command('HSET', prefix + 'hash', 'one', '1', 'two', '2')
    command('RPUSH', prefix + 'list', 'a', 'b')
    command('SADD', prefix + 'set', 'a', 'b')
    command('ZADD', prefix + 'zset', 1, 'a', 2, 'b')
    command('XADD', prefix + 'stream', '*', 'field', 'value')
    command('SET', prefix + 'long', 'x' * 20000)
    command('SET', b'pathfinder-test:binary\xff', b'\x00\xff')
    command('SET', prefix + 'expiring', 'soon', 'EX', 120)
    for index in range(65):
        command('SET', prefix + str(index), str(index))
    schema = run('schema')
    assert schema.returncode == 0, schema.stderr
    assert json.loads(schema.stdout)[0]['name'] == 'Keys'
    output = run('data', 200, 0)
    assert output.returncode == 0, output.stderr
    rows = json.loads(output.stdout)
    by_key = {row['key']: row for row in rows if isinstance(row['key'], str)}
    assert by_key[prefix + 'string']['value'] == 'hello\nworld'
    assert by_key[prefix + 'string']['ttl'] == -1
    assert by_key[prefix + 'list']['value'] == ['a', 'b']
    assert sorted(by_key[prefix + 'hash']['value']) == [['one', '1'], ['two', '2']]
    assert sorted(by_key[prefix + 'set']['value']) == ['a', 'b']
    assert by_key[prefix + 'zset']['value'] == [['a', '1'], ['b', '2']]
    assert by_key[prefix + 'stream']['size'] == 1
    assert by_key[prefix + 'long']['truncated'] is True
    assert len(by_key[prefix + 'long']['value']) == 16384
    assert 0 < by_key[prefix + 'expiring']['ttl'] <= 120
    assert any(isinstance(row['key'], dict) and row['value'] == {'base64': 'AP8='} for row in rows)
    filtered = json.loads(run('data', 100, 0, pattern=prefix + 's*', kind='string').stdout)
    assert [row['key'] for row in filtered] == [prefix + 'string']
    assert json.loads(run('data', 100, 0, pattern=prefix + 'missing:*').stdout) == []
    first = json.loads(run('data', 51, 0).stdout)
    second = json.loads(run('data', 51, 50).stdout)
    assert len(first) == 51 and len(second) >= 24
    assert first[50] == second[0]
    def write(original, replacement=None):
        return subprocess.run([sys.executable, str(repo / 'scripts/redis_data.py'), 'write'],
                              input=json.dumps({'url': url, 'original': original, 'replacement': replacement}),
                              capture_output=True, text=True, timeout=20)
    original = by_key[prefix + 'expiring']
    replacement = dict(original, value='updated')
    saved = write(original, replacement)
    assert saved.returncode == 0, saved.stderr
    assert client.call('GET', prefix + 'expiring') == b'updated'
    assert 0 < client.call('TTL', prefix + 'expiring') <= 120
    stale = write(original, replacement)
    assert stale.returncode != 0 and 'changed or disappeared' in stale.stderr
    assert write(by_key[prefix + 'long']).returncode != 0
    assert client.call('EXISTS', prefix + 'long') == 1
    assert write(by_key[prefix + 'hash']).returncode == 0
    assert client.call('EXISTS', prefix + 'hash') == 0
    assert write(by_key[prefix + 'list'], dict(by_key[prefix + 'list'], value=[])).returncode != 0
    binary = next(row for row in rows if isinstance(row['key'], dict))
    assert write(binary, dict(binary, value={'base64': 'AP8B'})).returncode == 0
    assert client.call('GET', b'pathfinder-test:binary\xff') == b'\x00\xff\x01'
    assert write(by_key[prefix + 'string'], dict(by_key[prefix + 'string'], key='renamed')).returncode != 0
    def mutate(mode, payload):
        return subprocess.run([sys.executable, str(repo / 'scripts/redis_data.py'), mode],
                              input=json.dumps(dict(payload, url=url)), capture_output=True, text=True, timeout=20)
    key = prefix + 'created'
    created.append(key)
    assert mutate('create', {'key': key, 'value': 'new'}).returncode == 0
    assert mutate('create', {'key': key, 'value': 'overwrite'}).returncode != 0
    assert client.call('GET', key) == b'new'
    original = redis_data.record(client, key.encode())
    assert mutate('write', {'original': original, 'action': 'expiry', 'ttl': 60}).returncode == 0
    assert 0 < client.call('TTL', key) <= 60
    assert mutate('write', {'original': original, 'action': 'expiry', 'ttl': -1}).returncode == 0
    assert client.call('TTL', key) == -1
    assert mutate('write', {'original': original, 'action': 'expiry', 'ttl': 0}).returncode != 0
    wrong = run('schema', connection=url.replace('pathfinder-test@', 'wrong-secret@'))
    assert wrong.returncode != 0 and 'WRONGPASS' in wrong.stderr
    assert 'wrong-secret' not in wrong.stderr
    bad = run('schema', connection='redis://localhost/not-a-db')
    assert bad.returncode != 0
    bad = run('schema', connection=url + '?ignored=true')
    assert bad.returncode != 0
    # TLS always uses the verified default context and the URL hostname for SNI.
    class FakeSocket:
        def makefile(self, _): return self
        def close(self): pass
    fake = FakeSocket()
    with patch.object(redis_data.socket, 'create_connection', return_value=fake), \
         patch.object(redis_data.ssl, 'create_default_context') as context, \
         patch.object(redis_data.Redis, 'call', return_value=b'OK'):
        context.return_value.wrap_socket.return_value = fake
        tls = redis_data.Redis('rediss://default:secret@redis.example:6380/2')
        context.return_value.wrap_socket.assert_called_once_with(fake, server_hostname='redis.example')
        tls.close()
    env = dict(os.environ, REDIS_TEST_URL=url, NVIM_LOG_FILE='/tmp/pathfinder-redis-test.log')
    created.append(prefix + 'ui-new')
    ui = subprocess.run(['nvim', '--headless', '-u', 'NONE', '-l', 'tests/database_connections.lua'],
                        cwd=repo, env=env, capture_output=True, text=True, timeout=20)
    assert ui.returncode == 0, ui.stdout + ui.stderr
    assert client.call('GET', prefix + 'string') == b'saved in Neovim'
    assert client.call('GET', prefix + 'ui-new') == b'created from UI'
    assert 0 < client.call('TTL', prefix + 'ui-new') <= 120
    print(ui.stdout + ui.stderr)
    print('Redis: authentication, database selection, all six types, binary values, previews, pagination, filters, creation, TTL updates, edits, deletion, conflicts, TLS configuration and UI passed')
finally:
    for key in set(created):
        client.call('DEL', key)
    client.close()
