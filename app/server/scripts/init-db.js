import 'dotenv/config';
import db, { migrate } from '../db.js';
migrate();
console.log('Database ready at', process.env.DATABASE_PATH || './data/app.sqlite');
