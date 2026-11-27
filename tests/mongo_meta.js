const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('scripts/mongo_meta.js', 'utf8');
const names = new Set(['users']);
let output;
const target = {
  getName: () => 'selected',
  getCollectionInfos(filter, nameOnly, authorized) {
    assert.equal(nameOnly, true); assert.equal(authorized, true);
    return [...names].map(name => ({ name, type: 'collection' }));
  },
  createCollection(name) { assert(!names.has(name)); names.add(name); return { ok: 1 }; },
  getCollection(name) { return {
    renameCollection(replacement, overwrite) { assert.equal(overwrite, false); assert(!names.has(replacement)); names.delete(name); names.add(replacement); return { ok: 1 }; },
    drop() { return names.delete(name); },
    getIndexes() { return [{ name: '_id_', key: { _id: 1 } }]; },
  }; },
};
function run(action, extra = {}) {
  const input = { action, database: 'selected', ...extra };
  vm.runInNewContext(source, {
    require(name) { assert.equal(name, 'fs'); return { readFileSync: () => JSON.stringify(input) }; },
    db: { getSiblingDB(name) {
      if (name === 'admin') return { runCommand(command) {
        assert.equal(command.authorizedDatabases, true); assert.equal(command.nameOnly, true);
        return { ok: 1, databases: [{ name: 'selected' }, { name: 'another' }] };
      } };
      assert.equal(name, 'selected'); return target;
    } },
    EJSON: { stringify: JSON.stringify }, print(value) { output = JSON.parse(value); },
  });
  return output;
}
assert.deepEqual(run('databases').map(item => item.name), ['another', 'selected']);
assert.equal(run('collections')[0].name, 'users');
const unusual = 'orders";throw new Error("injection");';
run('create', { name: unusual });
assert(names.has(unusual));
run('rename', { name: unusual, replacement: 'orders' });
assert(names.has('orders') && !names.has(unusual));
assert.equal(run('info', { name: 'orders' }).indexes[0].name, '_id_');
run('drop', { name: 'orders' });
assert(!names.has('orders'));
console.log('MongoDB metadata script: authorized lists, create, safe rename, drop, indexes and literal names passed');
