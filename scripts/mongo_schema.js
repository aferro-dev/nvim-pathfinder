// Bound inference to the first 50 documents; report BSON types, never values.
const schema = db.getCollectionNames().filter(name => !name.startsWith('system.')).sort().map(name => {
  const collection = db.getCollection(name);
  const sample = collection.aggregate([
    { $limit: 50 },
    { $facet: {
      count: [{ $count: 'n' }],
      fields: [
        { $project: { fields: { $objectToArray: '$$ROOT' } } },
        { $unwind: '$fields' },
        { $group: { _id: '$fields.k', types: { $addToSet: { $type: '$fields.v' } } } },
        { $sort: { _id: 1 } }
      ]
    } }
  ], { maxTimeMS: 3000 }).toArray()[0];
  return {
    name,
    sample_size: sample.count.length ? sample.count[0].n : 0,
    columns: sample.fields.map(field => ({ name: field._id, type: field.types.sort().join(' | ') })),
    indexes: collection.getIndexes().map(index => ({
      name: index.name, unique: !!index.unique,
      keys: Object.entries(index.key).map(([key, value]) => key + ': ' + value).join(', ')
    })),
    foreign_keys: []
  };
});
print(JSON.stringify(schema));
