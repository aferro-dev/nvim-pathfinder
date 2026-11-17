const input = EJSON.parse(require('fs').readFileSync(0, 'utf8'), { relaxed: false });
const collection = db.getCollection(input.table);
function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, stable(value[key])]));
  }
  return value;
}
function canonical(value) {
  return JSON.stringify(stable(EJSON.serialize(value, { relaxed: false })));
}
const current = collection.findOne({ _id: input.original._id });
if (!current || canonical(current) !== canonical(input.original)) {
  throw new Error('Record changed or disappeared; reload before retrying');
}
const filter = { _id: current._id, $expr: { $eq: ['$$ROOT', { $literal: current }] } };
if (input.replacement) {
  if (canonical(input.replacement._id) !== canonical(current._id)) throw new Error('Cannot change _id');
  const result = collection.replaceOne(filter, input.replacement, { upsert: false });
  if (result.matchedCount !== 1) throw new Error('Record changed; reload before retrying');
} else {
  const result = collection.deleteOne(filter);
  if (result.deletedCount !== 1) throw new Error('Record changed; reload before retrying');
}
