// Input is JSON on stdin; names never become executable JavaScript.
const input = JSON.parse(require('fs').readFileSync(0, 'utf8'));
const target = db.getSiblingDB(input.database || db.getName());
let result;
switch (input.action) {
  case 'databases': {
    const response = db.getSiblingDB('admin').runCommand({ listDatabases: 1, nameOnly: true, authorizedDatabases: true });
    if (!response.ok) throw new Error(response.errmsg || 'Cannot list databases');
    result = response.databases.map(item => ({ name: item.name })).sort((a, b) => a.name.localeCompare(b.name));
    break;
  }
  case 'collections':
    result = target.getCollectionInfos({}, true, true).filter(item => !item.name.startsWith('system.'))
      .map(item => ({ name: item.name, type: item.type || 'collection', columns: [], foreign_keys: [] }))
      .sort((a, b) => a.name.localeCompare(b.name));
    break;
  case 'create': result = target.createCollection(input.name); break;
  case 'rename': result = target.getCollection(input.name).renameCollection(input.replacement, false); break;
  case 'drop': result = { dropped: target.getCollection(input.name).drop() }; break;
  case 'info':
    result = { database: target.getName(), collection: input.name, indexes: target.getCollection(input.name).getIndexes() };
    break;
  default: throw new Error('Unsupported MongoDB metadata action');
}
print(EJSON.stringify(result, null, 0, { relaxed: true }));
