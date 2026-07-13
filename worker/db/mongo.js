const { MongoClient } = require('mongodb');

// 접속 정보는 환경변수로 주입(docker-compose에서 설정). 없으면 로컬 기본값 사용.
const mongoUri = process.env.MONGO_URI || 'mongodb://localhost:27017';
const dbName = process.env.MONGO_DB || 'supercent';
const collectionName = process.env.MONGO_COLLECTION || 'logs';

const client = new MongoClient(mongoUri);

// 한 번 연결한 컬렉션을 재사용하기 위한 캐시.
let collection;

// MongoDB 연결(최초 1회만 실제 connect, 이후에는 캐시된 컬렉션 반환).
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

// 로그 1건을 저장한다. 저장 시각(storedAt)을 추가로 기록해 수신↔적재 지연을 추적할 수 있게 한다.
const insertLog = async (logData) => {
    const logsCollection = await connectMongo();

    const document = {
        ...logData,
        storedAt: new Date()
    };

    const result = await logsCollection.insertOne(document);

    return result;
};

// graceful shutdown 시 커넥션 정리.
const closeMongo = async () => {
    await client.close();
};

module.exports = {
    connectMongo,
    insertLog,
    closeMongo
};
