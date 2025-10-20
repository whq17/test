import React, { useCallback, useEffect, useRef, useState } from 'react';
import { io } from 'socket.io-client';
import { v4 as uuidv4 } from 'uuid';

const SERVER_URL = import.meta.env.VITE_SERVER_URL || window.location.origin;
function authHeaders(){ const t = sessionStorage.getItem('token'); return t ? { 'Authorization': 'Bearer ' + t } : {}; }

function useHashRoute(){
  const [route, setRoute] = useState(() => window.location.hash || '#/dashboard');
  useEffect(() => {
    const onHash = () => setRoute(window.location.hash || '#/dashboard');
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);
  const navigate = useCallback((nextHash) => {
    if (!nextHash) return;
    if (window.location.hash !== nextHash) {
      window.location.hash = nextHash;
    }
    setRoute(nextHash);
  }, []);
  return [route, navigate];
}

export default function App(){
  const [route, navigate] = useHashRoute();
  if (route.startsWith('#/room')) return <Room navigate={navigate} />;
  if (route.startsWith('#/history')) return <History navigate={navigate} />;
  if (route.startsWith('#/auth')) return <Auth navigate={navigate} />;
  return <Dashboard navigate={navigate} />;
}


function LogoutButton(){ 
  const has = !!sessionStorage.getItem('token');
  if (!has) return null;
  return <button className="btn" onClick={()=>{
    try { sessionStorage.removeItem('token'); } catch {}
    // optional: clear session-only user state
    window.location.hash = '#/auth';
  }}>ออกจากระบบ</button>;
}

function TopNav({right}){
  return (
    <div className="nav">
      <div className="brand">Smart ClassRoom</div>
      <div className="actions">{right}<LogoutButton /></div>
    </div>
  );
}

function Dashboard({ navigate }){
  const token = sessionStorage.getItem('token');
  useEffect(() => {
    if (!token) navigate('#/auth');
  }, [token, navigate]);
  if (!token) return null;

  const [profileName, setProfileName] = useState(localStorage.getItem('profileName') || ('ผู้ใช้-' + Math.floor(Math.random()*1000)));
  const [roomId, setRoomId] = useState('');
  const [createdRoomId, setCreatedRoomId] = useState('');
  const [lastRoomId, setLastRoomId] = useState(localStorage.getItem('lastRoomId') || '');



  const createRoom = async () => {
    const res = await fetch(`${SERVER_URL}/api/room`, {
      method: 'POST', headers: { 'Content-Type':'application/json', ...authHeaders() },
      body: JSON.stringify({ creatorName: profileName })
    });
    const data = await res.json();
    if (res.ok) {
      try {
        const store = JSON.parse(localStorage.getItem('creatorKeys')||'{}');
        if (data.creatorKey) { store[data.roomId] = data.creatorKey; localStorage.setItem('creatorKeys', JSON.stringify(store)); }
      } catch {}
      setCreatedRoomId(data.roomId);
      localStorage.setItem('profileName', profileName);
      localStorage.setItem('lastRoomId', data.roomId);
      navigate(`#/room?roomId=${data.roomId}&creator=1`);
    } else {
      alert('สร้างห้องไม่สำเร็จ: ' + (data.error || res.statusText));
    }
  };

  const joinRoom = () => {
    if (!roomId) return alert('กรอก Room ID');
    localStorage.setItem('profileName', profileName);
    navigate(`#/room?roomId=${roomId}`);
  };

  const openHistoryNewTab = () => {
    const store = JSON.parse(localStorage.getItem('creatorKeys')||'{}');
    const keys = Object.values(store);
    if (!keys.length) { alert('ประวัติแสดงเฉพาะเจ้าของห้องเท่านั้น — กรุณาสร้างห้องก่อน'); return; }
    window.open('#/history', '_blank');
  };

  return (<>
    <TopNav right={<>
      <button className="btn ghost" onClick={openHistoryNewTab}>ประวัติการสนทนา</button>
      <a className="btn" href="#/dashboard">หน้าแรก</a>
    </>} />
    <div className="container">
      <div className="grid">
        <div className="card">
          <div className="title">โปรไฟล์</div>
          <label>ชื่อที่ใช้แสดง
            <input value={profileName} onChange={e=>setProfileName(e.target.value)} />
          </label>
          <p className="muted">ชื่อนี้จะแสดงบนวิดีโอคอล</p>
        </div>

        <div className="card">
          <div className="title">สร้างห้อง</div>
          <button className="btn primary" onClick={createRoom}>+ สร้างห้อง</button>
          {createdRoomId && <p className="muted" style={{marginTop:8}}>ห้องล่าสุด: <b>{createdRoomId}</b></p>}
        </div>

        <div className="card">
          <div className="title">เข้าร่วมห้อง</div>
          <label>Room ID
            <input value={roomId} onChange={e=>setRoomId(e.target.value)} placeholder="เช่น abcd1234" />
          </label>
          <button className="btn" onClick={joinRoom}>เข้าร่วม</button>
        </div>

        <div className="card">
      <div className="title">ห้องของฉัน</div>
      {lastRoomId ? (
        <button className="btn" onClick={() => navigate(`#/room?roomId=${lastRoomId}&creator=1`)}>
          เข้าห้องเดิม ({lastRoomId})
        </button>
      ) : (
        <p className="muted">ยังไม่มีห้องที่สร้างไว้</p>
      )}
    </div>

      </div>
    </div>
    
  </>);
}

function useQuery(){
  const [q] = useState(() => new URLSearchParams((window.location.hash.split('?')[1]||'')));
  return q;
}

function Room({ navigate }) {
  const q = useQuery();
  const roomId = q.get('roomId') || '';
  const isCreator = q.get('creator') === '1';
  const [profileName] = useState(localStorage.getItem('profileName') || ('ผู้ใช้-' + Math.floor(Math.random() * 1000)));

  const [peers, setPeers] = useState([]);
  const [peerNames, setPeerNames] = useState({});
  const [isSharingScreen, setIsSharingScreen] = useState(false);


 


  const [messages, setMessages] = useState([]);
  const chatRef = useRef(null);

  // quiz
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState(['', '', '']);
  const [correctIndex, setCorrectIndex] = useState(null);
  const [liveQuiz, setLiveQuiz] = useState(null);
  const [myAnswer, setMyAnswer] = useState(null);
  const [leaderboard, setLeaderboard] = useState([]);
  const [mediaStates, setMediaStates] = useState({});
  const [selfControlLock, setSelfControlLock] = useState({ audio: false, video: false });
  const [uploadedQuizzes, setUploadedQuizzes] = useState([]);
  const [uploadError, setUploadError] = useState('');

  // media
  const localVideoRef = useRef(null);
  const [remoteVideos, setRemoteVideos] = useState({});
  const socketRef = useRef(null);
  const localStreamRef = useRef(null);
  const pcMap = useRef(new Map());
  const myIdRef = useRef(uuidv4());

  const sendMediaCommand = (targetId, action) => {
    if (!socketRef.current) return;
    socketRef.current.emit('media:control', { targetId, action });
  };

  const handleQuizUpload = async (event) => {
    const file = event.target?.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const parsed = JSON.parse(text);
      const items = Array.isArray(parsed) ? parsed : [parsed];
      const normalized = items
        .map(item => {
          const parsedIndex = Number(item?.correctIndex);
          return ({
            question: item?.question?.toString?.() || '',
            options: Array.isArray(item?.options) ? item.options.map(opt => opt?.toString?.() || '').filter(Boolean) : [],
            correctIndex: Number.isInteger(parsedIndex) ? parsedIndex : null,
          });
        })
        .filter(item => item.question && item.options.length >= 2);
      if (!normalized.length) {
        setUploadError('ไม่พบคำถามที่ใช้งานได้ในไฟล์');
        setUploadedQuizzes([]);
      } else {
        setUploadedQuizzes(normalized);
        setUploadError('');
      }
    } catch (err) {
      console.error('quiz upload parse error', err);
      setUploadError('ไม่สามารถอ่านไฟล์ได้ กรุณาตรวจสอบว่าเป็น JSON ที่ถูกต้อง');
      setUploadedQuizzes([]);
    } finally {
      if (event.target) event.target.value = '';
    }
  };

  const applyUploadedQuestion = (index) => {
    const item = uploadedQuizzes[index];
    if (!item) return;
    setQuestion(item.question || '');
    setOptions(item.options && item.options.length ? item.options : ['', '', '']);
    setCorrectIndex(typeof item.correctIndex === 'number' ? item.correctIndex : null);
  };

  const toggleScreenShare = async () => {
    try {
      if (!isSharingScreen && selfControlLock.video) {
        alert('ผู้สร้างห้องปิดกล้องไว้ ไม่สามารถแชร์หน้าจอได้');
        return;
      }
      if (isSharingScreen) {
        localStreamRef.current?.getVideoTracks?.().forEach(t => t.stop());
        const cam = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
        localStreamRef.current = cam;
        if (localVideoRef.current) localVideoRef.current.srcObject = cam;
        for (const pc of pcMap.current.values()) {
          const v = pc.getSenders().find(s => s.track && s.track.kind === 'video');
          if (v) v.replaceTrack(cam.getVideoTracks()[0]);
          const a = pc.getSenders().find(s => s.track && s.track.kind === 'audio');
          if (a && cam.getAudioTracks()[0]) a.replaceTrack(cam.getAudioTracks()[0]);
        }
        setIsSharingScreen(false);
        return;
      }

      const screen = await navigator.mediaDevices.getDisplayMedia({ video: true });
      const mic = localStreamRef.current?.getAudioTracks?.()[0] || null;
      const combined = new MediaStream([screen.getVideoTracks()[0], ...(mic ? [mic] : [])]);
      localStreamRef.current = combined;
      if (localVideoRef.current) localVideoRef.current.srcObject = combined;
      for (const pc of pcMap.current.values()) {
        const v = pc.getSenders().find(s => s.track && s.track.kind === 'video');
        if (v) v.replaceTrack(combined.getVideoTracks()[0]);
      }
      screen.getVideoTracks()[0].onended = () => {
        if (isSharingScreen) toggleScreenShare();
      };
      setIsSharingScreen(true);
    } catch (e) {
      console.error('start/stop screenshare error:', e);
      alert('ไม่สามารถเริ่มแชร์หน้าจอได้');
    }
  };

  const setupMedia = async () => {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: true,
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true }
    });
    localStreamRef.current = stream;
    if (localVideoRef.current) localVideoRef.current.srcObject = stream;
  };

  const createPC = (peerId) => {
    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
    if (localStreamRef.current) localStreamRef.current.getTracks().forEach(t => pc.addTrack(t, localStreamRef.current));
    pc.ontrack = (e) => setRemoteVideos(prev => ({ ...prev, [peerId]: e.streams[0] }));
    pc.onicecandidate = (e) => {
      if (e.candidate) socketRef.current.emit('signal', { to: peerId, data: { type: 'ice', candidate: e.candidate } });
    };
    return pc;
  };

  const makeOffer = async (peerId) => {
    if (!localStreamRef.current) await setupMedia();
    const existing = pcMap.current.get(peerId);
    const pc = existing || createPC(peerId);
    if (!existing) pcMap.current.set(peerId, pc);
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    socketRef.current.emit('signal', { to: peerId, data: { type: 'sdp', sdp: pc.localDescription } });
  };

  const handleSignal = async ({ from, data }) => {
    let pc = pcMap.current.get(from);
    if (!pc) { pc = createPC(from); pcMap.current.set(from, pc); }
    if (data.type === 'sdp') {
      if (data.sdp.type === 'offer') {
        await pc.setRemoteDescription(data.sdp);
        if (!localStreamRef.current) {
          await setupMedia();
          localStreamRef.current.getTracks().forEach(t => pc.addTrack(t, localStreamRef.current));
        }
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socketRef.current.emit('signal', { to: from, data: { type: 'sdp', sdp: pc.localDescription } });
      } else if (data.sdp.type === 'answer') {
        await pc.setRemoteDescription(data.sdp);
      }
    } else if (data.type === 'ice') {
      try { await pc.addIceCandidate(data.candidate); } catch (e) { console.warn('ice error', e); }
    }
  };

  useEffect(() => {
    const socket = io(SERVER_URL, { transports: ['websocket'] });
    socketRef.current = socket;
    socket.on('connect', () => {
      console.log('socket', socket.id);
      setSelfControlLock({ audio: false, video: false });
    });

    socket.on('peers', async (others) => {
      setPeers(others);
      setPeerNames(prev => ({ ...prev, ...Object.fromEntries(others.map(o => [o.id, o.name || 'Guest'])) }));
      setMediaStates(prev => {
        const next = { ...prev };
        others.forEach(o => {
          if (o.id !== socket.id && !next[o.id]) {
            next[o.id] = { audioMuted: false, videoDisabled: false };
          }
        });
        return next;
      });
      for (const p of others) await makeOffer(p.id);
    });
    socket.on('peer-joined', ({ id, name }) => {
      setPeers(prev => [...prev, { id, name }]);
      setPeerNames(prev => ({ ...prev, [id]: name || 'Guest' }));
      setMediaStates(prev => ({ ...prev, [id]: prev[id] || { audioMuted: false, videoDisabled: false } }));
    });
    socket.on('peer-left', ({ id }) => {
      setPeers(prev => prev.filter(p => p.id !== id));
      const pc = pcMap.current.get(id);
      if (pc) pc.close();
      pcMap.current.delete(id);
      setRemoteVideos(prev => {
        const x = { ...prev }; delete x[id]; return x;
      });
      setMediaStates(prev => {
        if (!prev[id]) return prev;
        const next = { ...prev };
        delete next[id];
        return next;
      });
    });
    socket.on('signal', handleSignal);

    socket.on('chat', (payload) => {
      setMessages(m => [...m, payload]);
      setTimeout(() => chatRef.current && (chatRef.current.scrollTop = chatRef.current.scrollHeight), 0);
    });

    socket.on('quiz:new', (quiz) => { setLiveQuiz(quiz); setMyAnswer(null); });
    socket.on('quiz:denied', () => alert('สร้าง Quiz ไม่ได้: เฉพาะผู้สร้างห้องเท่านั้น'));
    socket.on('quiz:leaderboard', (payload) => {
      if (!payload || !Array.isArray(payload.entries)) return;
      setLeaderboard(payload.entries.map(entry => ({
        displayName: entry.displayName || entry.display_name || 'ไม่ทราบชื่อ',
        correctCount: Number(entry.correctCount ?? entry.correctcount ?? 0),
        totalAnswered: Number(entry.totalAnswered ?? entry.totalanswered ?? 0),
      })));
    });

    socket.on('session:summary', (payload) => {
      if (Array.isArray(payload?.correctByUser)) {
        const formatted = payload.correctByUser.map(row => ({
          displayName: row.display_name || row.displayName || 'ไม่ทราบชื่อ',
          correctCount: Number(row.correctCount || row.correctcount || 0),
          totalAnswered: Number(row.totalAnswered || row.totalanswered || 0),
        }));
        setLeaderboard(formatted);
      }
    });

    socket.on('media:control:denied', () => {
      alert('สั่งปิดไมค์/กล้องไม่ได้: ต้องเป็นผู้สร้างห้องเท่านั้น');
    });

    socket.on('media:control', ({ action }) => {
      const lower = String(action || '').toLowerCase();
      if (lower === 'mute-audio') {
        const track = localStreamRef.current?.getAudioTracks?.()[0];
        if (track) track.enabled = false;
        setSelfControlLock(prev => ({ ...prev, audio: true }));
        alert('ผู้สร้างห้องได้ปิดไมค์ของคุณ');
      } else if (lower === 'unmute-audio') {
        const track = localStreamRef.current?.getAudioTracks?.()[0];
        if (track) track.enabled = true;
        setSelfControlLock(prev => ({ ...prev, audio: false }));
      } else if (lower === 'disable-video') {
        const track = localStreamRef.current?.getVideoTracks?.()[0];
        if (track) track.enabled = false;
        setSelfControlLock(prev => ({ ...prev, video: true }));
        alert('ผู้สร้างห้องได้ปิดกล้องของคุณ');
      } else if (lower === 'enable-video') {
        const track = localStreamRef.current?.getVideoTracks?.()[0];
        if (track) track.enabled = true;
        setSelfControlLock(prev => ({ ...prev, video: false }));
      }
    });

    socket.on('media:status', ({ targetId, update }) => {
      if (!targetId || !update) return;
      setMediaStates(prev => {
        const next = { ...prev };
        const current = next[targetId] || { audioMuted: false, videoDisabled: false };
        next[targetId] = {
          audioMuted: typeof update.audioMuted === 'boolean' ? update.audioMuted : current.audioMuted,
          videoDisabled: typeof update.videoDisabled === 'boolean' ? update.videoDisabled : current.videoDisabled,
        };
        return next;
      });
      if (targetId === socket.id) {
        setSelfControlLock(prev => ({
          audio: typeof update.audioMuted === 'boolean' ? update.audioMuted : prev.audio,
          video: typeof update.videoDisabled === 'boolean' ? update.videoDisabled : prev.video,
        }));
      }
    });

    socket.on('session:end:denied', () => alert('ยุติห้องไม่ได้: ต้องเป็นผู้สร้างห้อง'));
    socket.on('session:ended', ({ payload }) => {
      alert(`ห้องนี้ถูกยุติแล้ว\n${JSON.stringify(payload, null, 2)}`);
      cleanupAndLeave();
      localStorage.removeItem('lastRoomId');
      navigate('#/dashboard');
    });

    (async () => {
      await setupMedia();
      const creatorKeys = JSON.parse(localStorage.getItem('creatorKeys') || '{}');
      const creatorKey = creatorKeys[roomId] || null;
      socket.emit('join', { roomId, name: profileName, creatorKey });
    })();

    return () => socket.disconnect();
  }, []);

  const cleanupAndLeave = () => {
    try { localStreamRef.current?.getTracks()?.forEach(t => t.stop()); } catch { }
    localStreamRef.current = null;
    for (const [id, pc] of pcMap.current.entries()) { try { pc.close(); } catch { } }
    pcMap.current.clear();
    setRemoteVideos({});
    setPeers([]);
    setLeaderboard([]);
    setMediaStates({});
    setSelfControlLock({ audio: false, video: false });
    setUploadedQuizzes([]);
    setUploadError('');
    setLiveQuiz(null);
    setMyAnswer(null);
    try { socketRef.current?.disconnect(); } catch { }
  };

  const sendChat = (e) => {
    e.preventDefault();
    const text = e.target.elements.msg.value.trim();
    if (!text) return;
    socketRef.current.emit('chat', text);
    e.target.reset();
  };

  const createQuiz = () => {
    if (!question || options.filter(o => o.trim()).length < 2)
      return alert('กรอกคำถามและตัวเลือกอย่างน้อย 2 ข้อ');
    socketRef.current.emit('quiz:create', { roomId, question, options, correctIndex, createdBy: profileName });
    setQuestion('');
    setOptions(['', '', '']);
    setCorrectIndex(null);
  };

  const answerQuiz = (idx) => {
    if (!liveQuiz) return;
    setMyAnswer(idx);
    socketRef.current.emit('quiz:answer', {
      quizId: liveQuiz.id,
      userId: myIdRef.current,
      displayName: profileName,
      answerIndex: idx
    });
  };

  const endSession = () => {
    if (!isCreator) return alert('ต้องเป็นผู้สร้างห้องเท่านั้น');
    socketRef.current.emit('session:end', { roomId });
    localStorage.removeItem('lastRoomId');
  };

  return (
    <>
      <TopNav right={<>
        <a className="btn" href="#/dashboard">Dashboard</a>
        <button className="btn ghost" onClick={() => window.open('#/history', '_blank')}>ประวัติ</button>
      </>} />

      {leaderboard.length > 0 && (
        <div className="leaderboard-card leaderboard-floating">
          <div className="section-title">Leaderboard</div>
          <ol className="leaderboard-list">
            {leaderboard.map((row, idx) => (
              <li key={idx}>
                <div className="rank-pill">#{idx + 1}</div>
                <div className="leaderboard-meta">
                  <span className="leaderboard-name">{row.displayName}</span>
                  <span className="leaderboard-score">{row.correctCount}/{row.totalAnswered}</span>
                </div>
              </li>
            ))}
          </ol>
        </div>
      )}

      <div className={`container room-container${leaderboard.length ? ' with-leaderboard' : ''}`}>
        <div className="room-grid">
          {/* 🎥 ฝั่งวิดีโอ */}
          <div className="card" style={{ gridColumn: '1 / 2' }}>
            <div className="title">ห้อง: {roomId}</div>
            <div className="row"><span className="pill">ฉัน: {profileName}{isCreator ? ' • ผู้สร้าง' : ''}</span></div>

            <div className="section-title">วิดีโอคอล</div>
            <div className="videos">
              <div className={"video-wrap" + (selfControlLock.video ? ' video-off' : '')}>
                <video ref={localVideoRef} autoPlay playsInline muted style={{ opacity: selfControlLock.video ? 0.2 : 1 }}></video>
                <div className="name-tag">{profileName}</div>
                {selfControlLock.audio && <div className="media-badge badge-audio">ไมค์ถูกปิดโดยผู้สร้างห้อง</div>}
                {selfControlLock.video && <div className="media-badge badge-video">กล้องถูกปิดโดยผู้สร้างห้อง</div>}
              </div>
              {Object.entries(remoteVideos).map(([peerId, stream]) => {
                const state = mediaStates[peerId] || { audioMuted: false, videoDisabled: false };
                return (
                  <RemoteMedia
                    key={peerId}
                    stream={stream}
                    name={peerNames[peerId] || peerId.slice(0, 6)}
                    speakersOn={!state.audioMuted}
                    audioMuted={!!state.audioMuted}
                    videoDisabled={!!state.videoDisabled}
                    isCreator={isCreator}
                    peerId={peerId}
                    onCommand={sendMediaCommand}
                  />
                );
              })}
            </div>

            <div className="controls" style={{ marginTop: 10 }}>
              <button className="btn" onClick={() => {
                if (selfControlLock.audio) { alert('ไมค์ถูกปิดโดยผู้สร้างห้อง'); return; }
                const t = localStreamRef.current?.getAudioTracks?.()[0];
                if (t) { t.enabled = !t.enabled; }
              }}>สลับไมค์</button>

              <button className="btn" onClick={() => {
                if (selfControlLock.video) { alert('กล้องถูกปิดโดยผู้สร้างห้อง'); return; }
                const v = localStreamRef.current?.getVideoTracks?.()[0];
                if (v) { v.enabled = !v.enabled; }
              }}>สลับกล้อง</button>

              <button className="btn primary small" onClick={toggleScreenShare}>
                {isSharingScreen ? 'หยุดแชร์จอ' : 'แชร์จอ'}
              </button>

              {isCreator && <button className="btn primary" onClick={endSession}>จบการสนทนา</button>}
            </div>
          </div>

          {/* 💬 ฝั่งแชท + Quiz */}
          <div className="card" style={{ gridColumn: '2 / 3', position: 'sticky', top: 24, alignSelf: 'start' }}>
            <div className="title">แชท</div>
            <div ref={chatRef} className="chatbox">
              {messages.map((m, i) => (
                <div key={i} className="chat-item"><strong>{m.name || 'ไม่ทราบชื่อ'}</strong>: {m.msg}</div>
              ))}
            </div>
            <form onSubmit={sendChat} className="controls">
              <input name="msg" placeholder="พิมพ์แชท..." style={{ flex: 1 }} />
              <button className="btn">ส่ง</button>
            </form>

            <div className="section-title">Quiz</div>
            {isCreator ? (
              <>
                <div className="row">
                  <input placeholder="คำถาม" value={question} onChange={e => setQuestion(e.target.value)} style={{ flex: 1 }} />
                  <button className="btn" onClick={() => setOptions([...options, ''])}>+ ตัวเลือก</button>
                </div>
                {options.map((opt, i) => (
                  <div key={i} className="row">
                    <input placeholder={'ตัวเลือก ' + (i + 1)} value={opt} onChange={e => {
                      const next = [...options]; next[i] = e.target.value; setOptions(next);
                    }} style={{ flex: 1 }} />
                    <label className="row" style={{ fontSize: 12 }}>
                      <input type="radio" checked={correctIndex === i} onChange={() => setCorrectIndex(i)} /> เฉลย
                    </label>
                  </div>
                ))}
                <div className="upload-block">
                  <label className="upload-label">
                    <span>อัปโหลดไฟล์ Quiz (.json)</span>
                    <input type="file" accept=".json" onChange={handleQuizUpload} />
                  </label>
                  <p className="muted" style={{ fontSize: 12, marginTop: 4 }}>รูปแบบไฟล์: [{{"question":"...","options":["A","B"],"correctIndex":0}}, …]</p>
                  {uploadError && <p className="muted" style={{ color: '#dc2626' }}>{uploadError}</p>}
                  {uploadedQuizzes.length > 0 && (
                    <div className="uploaded-list">
                      <div className="muted" style={{ marginBottom: 6 }}>เลือกคำถามจากไฟล์</div>
                      <ul>
                        {uploadedQuizzes.map((item, idx) => (
                          <li key={idx}>
                            <button type="button" className="btn small" onClick={() => applyUploadedQuestion(idx)}>ใช้ข้อที่ {idx + 1}</button>
                            <span>{item.question}</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
                <div className="controls">
                  <button className="btn primary" onClick={createQuiz}>ส่ง Quiz</button>
                </div>
              </>
            ) : (
              <p className="muted">รอผู้สร้างห้องเริ่ม Quiz…</p>
            )}

            {/* 🧩 Quiz ที่กำลังเล่น + ตารางคะแนน */}
            {liveQuiz && (
              <>
                <div style={{ marginTop: 12 }}>
                  <div className="title" style={{ fontSize: 16 }}>คำถาม: {liveQuiz.question}</div>
                  <div className="grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
                    {liveQuiz.options.map((opt, i) => (
                      <div key={i} className={'option ' + (myAnswer === i ? 'selected' : '')}
                        onClick={() => answerQuiz(i)}>
                        {String.fromCharCode(65 + i)}. {opt}
                      </div>
                    ))}
                  </div>
                </div>


              </>
            )}
          </div>
        </div>
      </div>
    </>
  );
}





function RemoteMedia({ stream, name, speakersOn, audioMuted, videoDisabled, isCreator, peerId, onCommand }){
  const vref = useRef(null);
  const aref = useRef(null);
  useEffect(()=>{
    if (vref.current) vref.current.srcObject = stream;
  }, [stream]);
  useEffect(()=>{
    if (aref.current) {
      aref.current.srcObject = stream;
      aref.current.muted = audioMuted ? true : !speakersOn;
      const p = aref.current.play(); if (p && p.catch) p.catch(()=>{});
    }
  }, [stream, speakersOn, audioMuted]);
  return (
    <div className={"video-wrap" + (videoDisabled ? ' video-off' : '')}>
      <video ref={vref} autoPlay playsInline style={{ opacity: videoDisabled ? 0.2 : 1 }} />
      <audio ref={aref} autoPlay />
      <div className="name-tag">{name}</div>
      {audioMuted && <div className="media-badge badge-audio">ไมค์ถูกปิดโดยผู้สร้างห้อง</div>}
      {videoDisabled && <div className="media-badge badge-video">กล้องถูกปิดโดยผู้สร้างห้อง</div>}
      {isCreator && onCommand && (
        <div className="host-controls">
          <button className="btn small" onClick={() => onCommand(peerId, audioMuted ? 'unmute-audio' : 'mute-audio')}>
            {audioMuted ? 'เปิดไมค์' : 'ปิดไมค์'}
          </button>
          <button className="btn small" onClick={() => onCommand(peerId, videoDisabled ? 'enable-video' : 'disable-video')}>
            {videoDisabled ? 'เปิดกล้อง' : 'ปิดกล้อง'}
          </button>
        </div>
      )}
    </div>
  );
}

function History({ navigate }){
  const [rows, setRows] = useState([]);
  useEffect(() => {
    (async () => {
      const store = JSON.parse(localStorage.getItem('creatorKeys')||'{}');
      const keys = Object.values(store);
      const qs = keys.length ? `?keys=${encodeURIComponent(keys.join(','))}` : '';
      const res = await fetch(`${SERVER_URL}/api/history${qs}`, { headers: authHeaders() });
      const data = await res.json();
      setRows(data.sessions || []);
    })();
  }, []);

  return (<>
    <TopNav right={<a className="btn" href="#/dashboard">กลับ Dashboard</a>} />
    <div className="container">
      <div className="card">
        <div className="title">ประวัติการสนทนา</div>
        <table>
          <thead>
            <tr>
              <th>เริ่ม</th><th>จบ</th><th>Room</th><th>จำนวนคำถาม</th><th>จำนวนผู้ตอบ</th><th>รายชื่อผู้ตอบ</th><th>คะแนนถูกต่อคน</th>
            </tr>
          </thead>
          <tbody>
            {rows.map(s => (
              <tr key={s.sessionId}>
                <td>{new Date(s.started_at).toLocaleString()}</td>
                <td>{s.ended_at ? new Date(s.ended_at).toLocaleString() : '-'}</td>
                <td>{s.roomId}</td>
                <td>{s.totalQuestions}</td>
                <td>{s.respondentCount}</td>
                <td>{s.respondents.join(', ')}</td>
                <td>{s.correctByUser.length ? s.correctByUser.map(u => `${u.display_name||'ไม่ทราบชื่อ'}: ${u.correctCount}/${u.totalAnswered}`).join(' | ') : '-'}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {!rows.length && <p className="muted">ยังไม่มีประวัติ</p>}
      </div>
    </div>
  </>);
}

function Auth({ navigate }){
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const doAuth = async (mode) => {
    const url = `${SERVER_URL}/api/auth/${mode}`;
    const res = await fetch(url, {
      method: 'POST', headers: {'Content-Type':'application/json'},
      body: JSON.stringify({ username, password })
    });
    const data = await res.json();
    if (!res.ok) return alert(data.error || 'failed');
    sessionStorage.setItem('token', data.token);
    localStorage.setItem('profileName', data.user.username);
    window.location.hash = '#/dashboard';
  };

  return (<>
    <div className="nav"><div className="brand">Smart ClassRoom</div></div>
    <div className="container" style={{maxWidth:480}}>
      <div className="card">
        <div className="title">เข้าสู่ระบบ / สมัครสมาชิก</div>
        <label>ชื่อผู้ใช้
          <input value={username} onChange={e=>setUsername(e.target.value)} />
        </label>
        <label>รหัสผ่าน
          <input type="password" value={password} onChange={e=>setPassword(e.target.value)} />
        </label>
        <div className="row" style={{marginTop:8}}>
          <button className="btn primary" onClick={()=>doAuth('login')}>เข้าสู่ระบบ</button>
          <button className="btn" onClick={()=>doAuth('register')}>สมัครสมาชิก</button>
        </div>
      </div>
    </div>

    
  </>);
}
