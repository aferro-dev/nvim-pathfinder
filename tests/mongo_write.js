const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync('scripts/mongo_write.js', 'utf8');
function run(input, current, matched = 1) {
  let action;
  const collection = {
    findOne: () => current,
    replaceOne(filter, replacement, options) {
      assert.deepEqual(filter.$expr.$eq[1].$literal, current);
      assert.equal(options.upsert, false);
      action = 'update';
      return { matchedCount: matched };
    },
    deleteOne(filter) { assert.equal(filter._id, current._id); action = 'delete'; return { deletedCount: matched }; }
  };
  vm.runInNewContext(source, {
    require: () => ({ readFileSync: () => JSON.stringify(input) }),
    EJSON: { parse: JSON.parse, serialize: value => value },
    db: { getCollection: () => collection }
  });
  return action;
}
const original = { _id: 'one', nested: { a: 1, b: 2 } };
assert.equal(run({ table: 't', original, replacement: { ...original, value: 3 } }, { nested: { b: 2, a: 1 }, _id: 'one' }), 'update');
assert.equal(run({ table: 't', original }, original), 'delete');
assert.throws(() => run({ table: 't', original }, { ...original, changed: true }), /changed/);
assert.throws(() => run({ table: 't', original }, original, 0), /changed/);
assert.throws(() => run({ table: 't', original, replacement: { _id: 'two' } }, original), /Cannot change/);
console.log('MongoDB mutation conflict, identity and operation contracts passed');
