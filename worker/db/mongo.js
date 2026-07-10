const { MongoClient } = require('mongodb');

const mongoUri = process.env.MONGO_URI || 'mongodb://localhost:27017';
const dbName = process.env.MONGO_DB || 'supercent';
const collectionName = process.env.MONGO_COLLECTION || 'logs';

const client = new MongoClient(mongoUri);

let collection;

const connectMongo = async () => {
    if (collection) {
        return collection;
    }

    await client.connect();

    const db = client.db(dbName);
    collection = db.collection(collectionName);

    console.log(`Connected to MongoDB: ${dbName}.${collectionName}`);

    return collection;
};

const insertLog = async (logData) => {
    const logsCollection = await connectMongo();

    const document = {
        ...logData,
        storedAt: new Date()
    };

    const result = await logsCollection.insertOne(document);

    return result;
    };

  const closeMongo = async () => {
    await client.close();
  };

module.exports = {
    connectMongo,
    insertLog,
    closeMongo
};
