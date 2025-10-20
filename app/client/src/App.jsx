import React, { useCallback, useEffect, useRef, useState } from 'react';
import { io } from 'socket.io-client';
import { v4 as uuidv4 } from 'uuid';

const SERVER_URL = import.meta.env.VITE_SERVER_URL || window.location.origin;
function authHeaders(){ const t = sessionStorage.getItem('token'); return t ? { 'Authorization': 'Bearer ' + t } : {}; }

function useHashRoute(){
  const [route, setRoute] = useState(window.location.hash || '#/dashboard');
  useEffect(() => {
    const onHash = () => setRoute(window.location.hash || '#/dashboard');
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);
  return [route, (r)=>{ window.location.hash = r; }];
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
  if (!token) { window.location.hash = '#/auth'; return null; }

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
      navigate(`#/room?roomId=${data.roomId}&creator=1`);
    } else {
      alert('สร้างห้องไม่สำเร็จ: ' + (data.error || res.statusText));
    }
  localStorage.setItem('lastRoomId', data.roomId); // จดจำห้องล่าสุด
  navigate(`#/room?roomId=${data.roomId}&creator=1`);

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
  const [pendingQuizzes, setPendingQuizzes] = useState([]);

  // media
  const localVideoRef = useRef(null);
  const [remoteVideos, setRemoteVideos] = useState({});
  const socketRef = useRef(null);
  const localStreamRef = useRef(null);
  const pcMap = useRef(new Map());
  const myIdRef = useRef(uuidv4());
  const [mediaStates, setMediaStates] = useState({});
  const [mySocketId, setMySocketId] = useState(null);

  const broadcastMediaState = useCallback(() => {
    const socket = socketRef.current;
    if (!socket || socket.disconnected) return;
    const audioTrack = localStreamRef.current?.getAudioTracks?.()[0] || null;
    const videoTrack = localStreamRef.current?.getVideoTracks?.()[0] || null;
    socket.emit('media:state', {
      state: {
        audioMuted: audioTrack ? audioTrack.enabled === false : true,
        videoOff: videoTrack ? videoTrack.enabled === false : true,
        hasAudio: !!audioTrack,
        hasVideo: !!videoTrack
      }
    });
  }, []);

  const toggleScreenShare = async () => {
    try {
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
        setTimeout(broadcastMediaState, 0);
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
      setTimeout(broadcastMediaState, 0);
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
    setTimeout(broadcastMediaState, 0);
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
      setMySocketId(socket.id);
      setTimeout(broadcastMediaState, 0);
    });

    socket.on('peers', async (others) => {
      setPeers(others);
      setPeerNames(prev => ({ ...prev, ...Object.fromEntries(others.map(o => [o.id, o.name || 'Guest'])) }));
      for (const p of others) await makeOffer(p.id);
    });
    socket.on('peer-joined', ({ id, name }) => {
      setPeers(prev => [...prev, { id, name }]);
      setPeerNames(prev => ({ ...prev, [id]: name || 'Guest' }));
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

    socket.on('quiz:leaderboard', ({ leaderboard: rows }) => {
      const mapped = (rows || []).map(row => ({
        displayName: row.displayName || row.display_name || 'ไม่ทราบชื่อ',
        correctCount: Number(row.correctCount || row.correct_count || 0),
        totalAnswered: Number(row.totalAnswered || row.total_answered || 0)
      }));
      setLeaderboard(mapped);
    });

    socket.on('session:summary', (payload) => {
      if (payload.correctByUser) {
        const mapped = (payload.correctByUser || []).map(row => ({
          displayName: row.display_name || row.displayName || 'ไม่ทราบชื่อ',
          correctCount: Number(row.correctCount || row.correct_count || 0),
          totalAnswered: Number(row.totalAnswered || row.total_answered || 0)
        }));
        setLeaderboard(mapped);
      }
    });

    socket.on('session:end:denied', () => alert('ยุติห้องไม่ได้: ต้องเป็นผู้สร้างห้อง'));
    socket.on('session:ended', ({ payload }) => {
      alert(`ห้องนี้ถูกยุติแล้ว\n${JSON.stringify(payload, null, 2)}`);
      cleanupAndLeave();
      localStorage.removeItem('lastRoomId');
      navigate('#/dashboard');
    });

    socket.on('media:control', ({ action, by }) => {
      let changed = false;
      if (action === 'mute-audio') {
        const track = localStreamRef.current?.getAudioTracks?.()[0];
        if (track) { track.enabled = false; changed = true; }
      }
      if (action === 'disable-video') {
        const track = localStreamRef.current?.getVideoTracks?.()[0];
        if (track) { track.enabled = false; changed = true; }
      }
      if (changed) {
        setMessages(m => [...m, { id: Date.now(), name: 'ระบบ', msg: `${by || 'ผู้ดูแล'} ปิด${action === 'mute-audio' ? 'ไมค์' : 'กล้อง'}ของคุณ` }]);
        setTimeout(() => chatRef.current && (chatRef.current.scrollTop = chatRef.current.scrollHeight), 0);
        broadcastMediaState();
      }
    });

    socket.on('media:control:denied', () => {
      alert('คำสั่งควบคุมสื่อทำได้เฉพาะผู้สร้างห้องเท่านั้น');
    });

    socket.on('media:state', ({ socketId, state }) => {
      if (!socketId) return;
      if (state && state.disconnected) {
        setMediaStates(prev => {
          const next = { ...prev };
          delete next[socketId];
          return next;
        });
        return;
      }
      setMediaStates(prev => ({ ...prev, [socketId]: state || {} }));
    });

    (async () => {
      await setupMedia();
      const creatorKeys = JSON.parse(localStorage.getItem('creatorKeys') || '{}');
      const creatorKey = creatorKeys[roomId] || null;
      socket.emit('join', { roomId, name: profileName, creatorKey });
    })();

    return () => socket.disconnect();
  }, [broadcastMediaState, navigate, roomId]);

  const cleanupAndLeave = () => {
    try { localStreamRef.current?.getTracks()?.forEach(t => t.stop()); } catch { }
    localStreamRef.current = null;
    for (const [id, pc] of pcMap.current.entries()) { try { pc.close(); } catch { } }
    pcMap.current.clear();
    setRemoteVideos({});
    setPeers([]);
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

  const handleQuizUpload = async (e) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      const text = await file.text();
      const data = JSON.parse(text);
      const arr = Array.isArray(data) ? data : [data];
      const sanitized = arr
        .map(item => {
          if (!item || typeof item !== 'object') return null;
          const opts = Array.isArray(item.options) ? item.options.map(o => String(o || '')).filter(o => o.trim()) : [];
          if (!item.question || !opts.length) return null;
          const parsedIndex = Number(item.correctIndex);
          return {
            question: String(item.question || ''),
            options: opts,
            correctIndex: Number.isInteger(parsedIndex) ? parsedIndex : null
          };
        })
        .filter(Boolean);
      if (!sanitized.length) {
        alert('ไฟล์ไม่มีข้อมูล Quiz ที่ใช้งานได้');
        e.target.value = '';
        return;
      }
      setPendingQuizzes(sanitized);
      alert(`อัปโหลดชุดคำถาม ${sanitized.length} ข้อเรียบร้อย`);
    } catch (err) {
      console.error(err);
      alert('ไม่สามารถอ่านไฟล์ได้ กรุณาใช้ไฟล์ JSON');
    } finally {
      e.target.value = '';
    }
  };

  const loadUploadedQuiz = (idx) => {
    const quiz = pendingQuizzes[idx];
    if (!quiz) return;
    setQuestion(quiz.question);
    const opts = (quiz.options && quiz.options.length ? quiz.options : ['', '', '']).map(o => o);
    setOptions(opts);
    const candidate = Number.isInteger(quiz.correctIndex) && quiz.correctIndex >= 0 && quiz.correctIndex < opts.length
      ? quiz.correctIndex
      : null;
    setCorrectIndex(candidate);
  };

  const sendUploadedQuiz = (idx) => {
    const quiz = pendingQuizzes[idx];
    if (!quiz) return;
    const validCorrect = Number.isInteger(quiz.correctIndex) && quiz.correctIndex >= 0 && quiz.correctIndex < (quiz.options?.length || 0)
      ? quiz.correctIndex
      : null;
    socketRef.current.emit('quiz:create', {
      roomId,
      question: quiz.question,
      options: quiz.options,
      correctIndex: validCorrect,
      createdBy: profileName
    });
    setPendingQuizzes(prev => prev.filter((_, i) => i !== idx));
  };

  const sendAllUploaded = () => {
    if (!pendingQuizzes.length) return;
    socketRef.current.emit('quiz:bulkCreate', { roomId, quizzes: pendingQuizzes, createdBy: profileName }, (res) => {
      if (res?.ok) {
        if (res.errors?.length) {
          alert(`ส่ง ${res.created} ข้อ สำเร็จ แต่มี ${res.errors.length} ข้อที่ไม่สามารถส่งได้`);
          const failed = new Set(res.errors.map(e => e.index));
          setPendingQuizzes(prev => prev.filter((_, idx) => failed.has(idx)));
        } else {
          alert(`ส่ง Quiz ทั้งหมด ${res.created} ข้อเรียบร้อย`);
          setPendingQuizzes([]);
        }
      } else {
        alert('ไม่สามารถส่งชุดคำถามได้: ' + (res?.error || 'UNKNOWN'));
      }
    });
  };

  const forceMutePeer = (peerId) => {
    socketRef.current.emit('media:control', { roomId, targetId: peerId, action: 'mute-audio' });
  };

  const forceStopVideo = (peerId) => {
    socketRef.current.emit('media:control', { roomId, targetId: peerId, action: 'disable-video' });
  };

  useEffect(() => {
    if (!mySocketId) return;
    const audioTrack = localStreamRef.current?.getAudioTracks?.()[0];
    const videoTrack = localStreamRef.current?.getVideoTracks?.()[0];
    const state = {
      audioMuted: audioTrack ? audioTrack.enabled === false : true,
      videoOff: videoTrack ? videoTrack.enabled === false : true,
      hasAudio: !!audioTrack,
      hasVideo: !!videoTrack
    };
    setMediaStates(prev => ({ ...prev, [mySocketId]: state }));
  }, [mySocketId]);

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

      <div className="container">
        <div className="room-grid">
          {/* 🎥 ฝั่งวิดีโอ */}
          <div className="card" style={{ gridColumn: '1 / 2' }}>
            <div className="title">ห้อง: {roomId}</div>
            <div className="row"><span className="pill">ฉัน: {profileName}{isCreator ? ' • ผู้สร้าง' : ''}</span></div>

            <div className="section-title">วิดีโอคอล</div>
            <div className="videos">
              <div className="video-wrap">
                <video ref={localVideoRef} autoPlay playsInline muted></video>
                <div className="name-tag">{profileName}</div>
              </div>
              {Object.entries(remoteVideos).map(([peerId, stream]) => (
                <div key={peerId} style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                  <RemoteMedia
                    stream={stream}
                    name={peerNames[peerId] || peerId.slice(0, 6)}
                    speakersOn={true}
                    status={mediaStates[peerId]}
                  />
                  {isCreator && (
                    <div className="row" style={{ gap: 8 }}>
                      <button className="btn small" onClick={() => forceMutePeer(peerId)}>ปิดไมค์</button>
                      <button className="btn small" onClick={() => forceStopVideo(peerId)}>ปิดกล้อง</button>
                    </div>
                  )}
                </div>
              ))}
            </div>

            <div className="controls" style={{ marginTop: 10 }}>
              <button className="btn" onClick={() => {
                const t = localStreamRef.current?.getAudioTracks?.()[0];
                if (t) { t.enabled = !t.enabled; broadcastMediaState(); }
              }}>ปิดไมค์</button>

              <button className="btn" onClick={() => {
                const v = localStreamRef.current?.getVideoTracks?.()[0];
                if (v) { v.enabled = !v.enabled; broadcastMediaState(); }
              }}>ปิดกล้อง</button>

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
                <div className="row" style={{ marginTop: 8, gap: 8, alignItems: 'center' }}>
                  <input type="file" accept=".json" onChange={handleQuizUpload} />
                  {pendingQuizzes.length > 0 && <button className="btn small" onClick={sendAllUploaded}>ส่งทั้งหมด</button>}
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
                <div className="controls">
                  <button className="btn primary" onClick={createQuiz}>ส่ง Quiz</button>
                </div>
                {pendingQuizzes.length > 0 && (
                  <div className="card" style={{ marginTop: 12 }}>
                    <div className="title" style={{ fontSize: 16 }}>ชุดคำถามที่อัปโหลด</div>
                    {pendingQuizzes.map((quiz, idx) => (
                      <div key={idx} style={{ marginBottom: 12 }}>
                        <div style={{ fontWeight: 600 }}>#{idx + 1} {quiz.question}</div>
                        <ul style={{ marginLeft: 16 }}>
                          {quiz.options.map((opt, i) => {
                            const isAnswer = quiz.correctIndex !== null && quiz.correctIndex !== undefined && Number(quiz.correctIndex) === i;
                            return (
                              <li key={i} style={{ color: isAnswer ? 'green' : undefined }}>
                                {String.fromCharCode(65 + i)}. {opt}
                                {isAnswer ? ' (เฉลย)' : ''}
                              </li>
                            );
                          })}
                        </ul>
                        <div className="row" style={{ gap: 8 }}>
                          <button className="btn small" onClick={() => loadUploadedQuiz(idx)}>เติมในฟอร์ม</button>
                          <button className="btn primary small" onClick={() => sendUploadedQuiz(idx)}>ส่งทันที</button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
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

            <div className="section-title">Leaderboard</div>
            {leaderboard.length ? (
              <table className="leaderboard" style={{ width: '100%', fontSize: 13 }}>
                <thead>
                  <tr><th>ชื่อ</th><th>ตอบถูก</th><th>จำนวนที่ตอบ</th></tr>
                </thead>
                <tbody>
                  {leaderboard.map((row, idx) => {
                    const isMe = row.displayName === profileName;
                    return (
                      <tr key={idx} style={isMe ? { background: '#eef6ff' } : undefined}>
                        <td>{row.displayName || 'ไม่ทราบชื่อ'}</td>
                        <td>{row.correctCount}</td>
                        <td>{row.totalAnswered}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            ) : (
              <p className="muted">ยังไม่มีคะแนนจาก Quiz</p>
            )}
          </div>
        </div>
      </div>
    </>
  );
}





function RemoteMedia({ stream, name, speakersOn, status }){
  const vref = useRef(null);
  const aref = useRef(null);
  useEffect(()=>{
    if (vref.current) vref.current.srcObject = stream;
    if (aref.current) {
      aref.current.srcObject = stream;
      aref.current.muted = !speakersOn;
      const p = aref.current.play(); if (p && p.catch) p.catch(()=>{});
    }
  }, [stream, speakersOn]);
  return (
    <div className="video-wrap">
      <video ref={vref} autoPlay playsInline />
      <audio ref={aref} autoPlay />
      <div className="name-tag">{name}{status?.audioMuted ? ' 🔇' : ''}{status?.videoOff ? ' 📷✖' : ''}</div>
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
