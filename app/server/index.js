import 'dotenv/config';
import express from 'express';
import http from 'http';
import cors from 'cors';
import { Server } from 'socket.io';
import { v4 as uuidv4 } from 'uuid';
import db, { migrate } from './db.js';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

const app = express();
app.set('trust proxy', 1);
const ORIGIN = (process.env.ORIGIN || 'http://localhost:5173').split(',');
app.use(cors({ origin: (origin, cb)=>{
  if (!origin) return cb(null, true);
  if (ORIGIN.includes('*') || ORIGIN.includes(origin)) return cb(null, true);
  // allow trycloudflare subdomains if ORIGIN has 'trycloudflare'
  if (ORIGIN.find(o=>o.includes('trycloudflare') && origin.endsWith('trycloudflare.com'))) return cb(null, true);
  return cb(new Error('Not allowed by CORS: ' + origin));
}, credentials: true }));
app.use(express.json());

migrate();

const server = http.createServer(app);
const io = new Server(server, { cors: { origin: ORIGIN.includes('*') ? '*' : ORIGIN, credentials: true } });

const JWT_SECRET = process.env.JWT_SECRET || 'devsecret_change_me';

function issueToken(user){ return jwt.sign({ uid: user.id, username: user.username }, JWT_SECRET, { expiresIn: '7d' }); }
function authMiddleware(req, res, next){
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'UNAUTH' });
  try{
    const payload = jwt.verify(token, JWT_SECRET);
    req.user = payload;
    next();
  } catch(e){
    return res.status(401).json({ error: 'BAD_TOKEN' });
  }
}


// room and name tracking
const roomsMap = new Map(); // roomId -> Set<socketId>
const nameMap = new Map();  // socketId -> displayName

const joinRoom = (roomId, sid) => { if (!roomsMap.has(roomId)) roomsMap.set(roomId, new Set()); roomsMap.get(roomId).add(sid); };
const leaveRoom = (roomId, sid) => {
  const set = roomsMap.get(roomId);
  if (!set) return;
  set.delete(sid);
  if (set.size === 0) roomsMap.delete(roomId);
};
const peersIn = (roomId) => Array.from(roomsMap.get(roomId) || []);

function ensureSession(roomId) {
  const existing = db.prepare('SELECT id FROM sessions WHERE room_id = ? AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1').get(roomId);
  if (existing) return existing.id;
  const id = uuidv4();
  db.prepare('INSERT INTO sessions (id, room_id) VALUES (?, ?)').run(id, roomId);
  return id;
}

io.on('connection', (socket) => {
  let currentRoom = null;
  let displayName = 'Guest';

  socket.on('join', ({ roomId, name }) => {
    displayName = name || 'Guest';
    nameMap.set(socket.id, displayName);
    currentRoom = roomId;
    socket.join(roomId);
    joinRoom(roomId, socket.id);

    const info = db.prepare('SELECT id, creator_name, creator_socket FROM rooms WHERE id = ?').get(roomId);
    if (!info) {
      db.prepare('INSERT INTO rooms (id, creator_name, creator_socket) VALUES (?, ?, ?)').run(roomId, null, null);
    } else {
      if (info.creator_name && !info.creator_socket && info.creator_name === displayName) {
        db.prepare('UPDATE rooms SET creator_socket = ? WHERE id = ?').run(socket.id, roomId);
      }
    }
    ensureSession(roomId);

    const others = peersIn(roomId).filter(id => id !== socket.id).map(id => ({ id, name: nameMap.get(id) || 'Guest' }));
    socket.emit('peers', others);
    socket.to(roomId).emit('peer-joined', { id: socket.id, name: displayName });
  });

  socket.on('signal', ({ to, data }) => io.to(to).emit('signal', { from: socket.id, data }));

  socket.on('chat', (text) => {
    if (!currentRoom) return;
    io.to(currentRoom).emit('chat', { id: socket.id, name: displayName, msg: text, ts: Date.now() });
  });

  socket.on('quiz:create', ({ roomId, question, options, correctIndex, createdBy }) => {
    // enforce: only room owner can create quizzes
    const room = db.prepare('SELECT creator_socket FROM rooms WHERE id = ?').get(roomId);
    const isOwner = room && room.creator_socket === socket.id;
    if (!isOwner) { socket.emit('quiz:denied', { reason: 'ONLY_OWNER' }); return; }
    if (!roomId || !question || !Array.isArray(options)) return;
    const sessionId = ensureSession(roomId);
    const id = uuidv4();
    db.prepare('INSERT INTO quizzes (id, room_id, session_id, question, options, correct_index, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(id, roomId, sessionId, question, JSON.stringify(options), Number.isInteger(correctIndex) ? correctIndex : null, createdBy || null);
    io.to(roomId).emit('quiz:new', { id, question, options, correctIndex });
  });

  socket.on('quiz:answer', ({ quizId, userId, displayName: dname, answerIndex }) => {
    const quiz = db.prepare('SELECT * FROM quizzes WHERE id = ?').get(quizId);
    if (!quiz) return;
    const isCorrect = quiz.correct_index == null ? null : (Number(answerIndex) === Number(quiz.correct_index) ? 1 : 0);
    const id = uuidv4();
    db.prepare('INSERT INTO responses (id, quiz_id, session_id, user_id, display_name, answer_index, is_correct) VALUES (?, ?, ?, ?, ?, ?, ?)')
      .run(id, quizId, quiz.session_id, userId, dname || null, answerIndex, isCorrect);
    io.to(quiz.room_id).emit('quiz:answered', { quizId, userId, displayName: dname, answerIndex, isCorrect });
  });

  socket.on('session:end', async ({ roomId }) => {
    if (!roomId) return;
    const room = db.prepare('SELECT creator_name, creator_socket FROM rooms WHERE id = ?').get(roomId);
    const isCreator = room && (room.creator_socket === socket.id);
    if (!isCreator) {
      socket.emit('session:end:denied', { reason: 'ONLY_CREATOR' });
      return;
    }
    const sess = db.prepare('SELECT id FROM sessions WHERE room_id = ? AND ended_at IS NULL ORDER BY started_at DESC LIMIT 1').get(roomId);
    if (sess) db.prepare('UPDATE sessions SET ended_at = CURRENT_TIMESTAMP WHERE id = ?').run(sess.id);

    const totalQuestions = db.prepare('SELECT COUNT(*) as c FROM quizzes WHERE session_id = ?').get(sess.id).c;
    const perUser = db.prepare(`
      SELECT display_name, 
             SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correctCount,
             COUNT(*) as totalAnswered
      FROM responses
      WHERE session_id = ?
      GROUP BY display_name
      ORDER BY correctCount DESC, totalAnswered DESC
    `).all(sess.id);
    const respondents = db.prepare('SELECT DISTINCT display_name FROM responses WHERE session_id = ?').all(sess.id).map(r => r.display_name || 'ไม่ทราบชื่อ');

    const payload = {
      roomId,
      sessionId: sess?.id,
      totalQuestions: Number(totalQuestions || 0),
      respondentCount: respondents.length,
      respondents,
      correctByUser: perUser
    };

    io.to(socket.id).emit('session:summary', payload);
    io.to(roomId).emit('session:ended', { forceLeave: true, payload });

    setTimeout(() => {
      io.in(roomId).socketsLeave(roomId);
    }, 300);
  });

  socket.on('disconnect', () => {
    nameMap.delete(socket.id);
    if (currentRoom) {
      leaveRoom(currentRoom, socket.id);
      socket.to(currentRoom).emit('peer-left', { id: socket.id });
    }
  });
});

// AUTH: register/login
app.post('/api/auth/register', (req,res)=>{
  const { username, password } = req.body || {};
  if (!username || !password) return res.status(400).json({ error: 'MISSING' });
  const id = uuidv4();
  const hash = bcrypt.hashSync(password, 10);
  try{
    db.prepare('INSERT INTO users (id, username, password_hash) VALUES (?, ?, ?)').run(id, username, hash);
  } catch(e){ return res.status(409).json({ error: 'USER_EXISTS' }); }
  const token = issueToken({ id, username });
  res.json({ token, user: { id, username } });
});

app.post('/api/auth/login', (req,res)=>{
  const { username, password } = req.body || {};
  const row = db.prepare('SELECT * FROM users WHERE username = ?').get(username);
  if (!row) return res.status(401).json({ error: 'INVALID' });
  const ok = bcrypt.compareSync(password, row.password_hash);
  if (!ok) return res.status(401).json({ error: 'INVALID' });
  const token = issueToken({ id: row.id, username: row.username });
  res.json({ token, user: { id: row.id, username: row.username } });
});

// REST: create room (returns creatorKey)
app.post('/api/room', authMiddleware, (req, res) => {
  const { roomId, creatorName } = req.body || {};
  const id = roomId || uuidv4().slice(0, 8);
  const existing = db.prepare('SELECT id FROM rooms WHERE id = ?').get(id);
  if (existing) return res.status(409).json({ error: 'ROOM_EXISTS' });
  const creatorKey = uuidv4();
  // ensure rooms table has creator_key; if not, still insert ignoring column via try/catch
  try {
    db.prepare('INSERT INTO rooms (id, creator_name, creator_key, creator_user_id) VALUES (?, ?, ?, ?)').run(id, creatorName || null, creatorKey, req.user.uid);
  } catch {
    db.prepare('INSERT INTO rooms (id, creator_name) VALUES (?, ?)').run(id, creatorName || null);
  }
  res.json({ roomId: id, creatorKey });
});

// REST: history for creators only via ?keys=key1,key2
app.get('/api/history', authMiddleware, (req, res) => {
  const keysParam = (req.query.keys || '').toString().trim();
  if (!keysParam) return res.json({ sessions: [] });
  const keys = keysParam.split(',').map(s => s.trim()).filter(Boolean);
  if (!keys.length) return res.json({ sessions: [] });

  // find rooms owned by these keys
  let roomIds = [];
  // add rooms owned by current user (primary auth)
  const owned = db.prepare('SELECT id FROM rooms WHERE creator_user_id = ?').all(req.user.uid);
  roomIds.push(...owned.map(r => r.id));
  for (const k of keys){
    const rows = db.prepare('SELECT id FROM rooms WHERE creator_key = ?').all(k);
    roomIds.push(...rows.map(r => r.id));
  }
  roomIds = [...new Set(roomIds)];
  if (!roomIds.length) return res.json({ sessions: [] });

  const sessions = roomIds.flatMap(rid => db.prepare(`
    SELECT s.id as sessionId, s.room_id as roomId, s.started_at, s.ended_at
    FROM sessions s WHERE s.room_id = ?
    ORDER BY s.started_at DESC
    LIMIT 100
  `).all(rid));

  const result = sessions.map(s => {
    const totalQuestions = db.prepare('SELECT COUNT(*) as c FROM quizzes WHERE session_id = ?').get(s.sessionId).c;
    const respondents = db.prepare('SELECT DISTINCT display_name FROM responses WHERE session_id = ?').all(s.sessionId).map(r => r.display_name || 'ไม่ทราบชื่อ');
    const correctByUser = db.prepare(`
      SELECT display_name, 
             SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correctCount,
             COUNT(*) as totalAnswered
      FROM responses
      WHERE session_id = ?
      GROUP BY display_name
      ORDER BY correctCount DESC, totalAnswered DESC
    `).all(s.sessionId);
    return { ...s, totalQuestions: Number(totalQuestions || 0), respondentCount: respondents.length, respondents, correctByUser };
  });

  res.json({ sessions: result });
});


// ---- Static hosting for built client (production) ----
import path from 'path';
import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const clientDist = path.join(__dirname, '../client/dist');

app.get('/health', (_req,res)=>res.json({ok:true}));
try {
  app.use(express.static(clientDist));
  // SPA fallback
  app.get('*', (req,res) => {
    if (!req.path.startsWith('/api') && !req.path.startsWith('/socket.io'))
      return res.sendFile(path.join(clientDist, 'index.html'));
    res.status(404).send('Not found');
  });
} catch {}

const PORT = process.env.PORT || 4000;
server.listen(PORT, () => console.log(`Server ready on http://localhost:${PORT}`));
