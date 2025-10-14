// ใช้ Postgres แทน better-sqlite3
import { Pool } from "pg";

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,        // postgresql://... ?sslmode=require
  ssl: { rejectUnauthorized: false },                // จำเป็นกับ Neon/ผู้ให้บริการที่บังคับ SSL
});

// helper query
export const q = (text, params) => pool.query(text, params);

// ใช้เรียกในทรานแซกชัน (ถ้าจำเป็น)
export const tx = async (fn) => {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (e) {
    await client.query("ROLLBACK");
    throw e;
  } finally {
    client.release();
  }
};

// รัน migration (สร้างตาราง/ดัชนี) – เทียบเคียงสคีมาเดิมของคุณ
export async function migrate() {
  await q(`
    CREATE TABLE IF NOT EXISTS rooms (
      id TEXT PRIMARY KEY,
      creator_name   TEXT,
      creator_socket TEXT,
      creator_key    TEXT,
      creator_user_id TEXT,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      room_id   TEXT NOT NULL,
      started_at TIMESTAMPTZ DEFAULT now(),
      ended_at   TIMESTAMPTZ
    );

    CREATE TABLE IF NOT EXISTS quizzes (
      id TEXT PRIMARY KEY,
      room_id   TEXT NOT NULL,
      session_id TEXT NOT NULL,
      question   TEXT NOT NULL,
      options    TEXT NOT NULL,        -- เก็บ JSON string ตามของเดิม (ถ้าจะสวย เปลี่ยนเป็น JSONB ได้)
      correct_index INTEGER,
      created_by TEXT,
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS responses (
      id TEXT PRIMARY KEY,
      quiz_id    TEXT NOT NULL,
      session_id TEXT NOT NULL,
      user_id    TEXT NOT NULL,
      display_name TEXT,
      answer_index INTEGER NOT NULL,
      is_correct  BOOLEAN,             -- เดิมเป็น INTEGER; ใน Postgres ใช้ BOOLEAN จะเหมาะกว่า
      created_at TIMESTAMPTZ DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_quiz_room_session
      ON quizzes(room_id, session_id, created_at);

    CREATE INDEX IF NOT EXISTS idx_resp_session
      ON responses(session_id);

    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ DEFAULT now()
    );
  `);
}

export default { q, tx, migrate };
