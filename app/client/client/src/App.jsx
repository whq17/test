import React, { useEffect, useRef, useState } from 'react';
import { io } from 'socket.io-client';
import { v4 as uuidv4 } from 'uuid';

const SERVER_URL = import.meta.env.VITE_SERVER_URL || 'http://localhost:4000';

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
  return <Dashboard navigate={navigate} />;
}

function TopNav({right}){
  return (
    <div className="nav">
      <div className="Smart-Classroom</div>
      <div className="actions">{right}</div>
    </div>
  );
}

function Dashboard({ navigate }){
  const [profileName, setProfileName] = useState(localStorage.getItem('profileName') || ('ผู้ใช้-' + Math.floor(Math.random()*1000)));
  const [roomId, setRoomId] = useState('');
  const [createdRoomId, setCreatedRoomId] = useState('');

  const createRoom = async () => {
    const res = await fetch(`${SERVER_URL}/api/room`, {
      method: 'POST', headers: { 'Content-Type':'application/json' },
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
      </div>
    </div>
  </>);
}

function useQuery(){
  const [q] = useState(() => new URLSearchParams((window.location.hash.split('?')[1]||'')));
  return q;
}

function Room({ navigate }){
  const q = useQuery();
  const roomId = q.get('roomId') || '';
  const isCreator = q.get('creator') === '1';
  const [profileName] = useState(localStorage.getItem('profileName') || ('ผู้ใช้-' + Math.floor(Math.random()*1000)));

  const [peers, setPeers] = useState([]); // [{id,name}]
  const [peerNames, setPeerNames] = useState({}); // id->name
  const [messages, setMessages] = useState([]);
  const chatRef = useRef(null);

  // quiz
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState(['', '', '']);
  const [correctIndex, setCorrectIndex] = useState(null);
  const [liveQuiz, setLiveQuiz] = useState(null);
  const [myAnswer, setMyAnswer] = useState(null);

  // media
  const localVideoRef = useRef(null);
  const [remoteVideos, setRemoteVideos] = useState({}); // id->MediaStream
  const socketRef = useRef(null);
  const localStreamRef = useRef(null);
  const pcMap = useRef(new Map());
  const myIdRef = useRef(uuidv4());

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
    pc.onicecandidate = (e) => { if (e.candidate) socketRef.current.emit('signal', { to: peerId, data:{ type:'ice', candidate:e.candidate } }); };
    return pc;
  };

  const makeOffer = async (peerId) => {
    if (!localStreamRef.current) await setupMedia();
    const existing = pcMap.current.get(peerId);
    const pc = existing || createPC(peerId);
    if (!existing) pcMap.current.set(peerId, pc);
    const offer = await pc.createOffer(); await pc.setLocalDescription(offer);
    socketRef.current.emit('signal', { to: peerId, data: { type:'sdp', sdp: pc.localDescription } });
  };

  const handleSignal = async ({ from, data }) => {
    let pc = pcMap.current.get(from);
    if (!pc) { pc = createPC(from); pcMap.current.set(from, pc); }
    if (data.type === 'sdp') {
      if (data.sdp.type === 'offer') {
        await pc.setRemoteDescription(data.sdp);
        if (!localStreamRef.current) { await setupMedia(); localStreamRef.current.getTracks().forEach(t => pc.addTrack(t, localStreamRef.current)); }
        const answer = await pc.createAnswer(); await pc.setLocalDescription(answer);
        socketRef.current.emit('signal', { to: from, data: { type:'sdp', sdp: pc.localDescription } });
      } else if (data.sdp.type === 'answer') {
        await pc.setRemoteDescription(data.sdp);
      }
    } else if (data.type === 'ice') {
      try { await pc.addIceCandidate(data.candidate); } catch(e){ console.warn('ice error', e); }
    }
  };

  useEffect(() => {
    const socket = io(SERVER_URL, { transports: ['websocket'] });
    socketRef.current = socket;
    socket.on('connect', () => console.log('socket', socket.id));

    socket.on('peers', async (others) => {
      setPeers(others);
      setPeerNames(prev => ({ ...prev, ...Object.fromEntries(others.map(o=>[o.id, o.name||'Guest'])) }));
      for (const p of others) await makeOffer(p.id);
    });
    socket.on('peer-joined', ({ id, name }) => {
      setPeers(prev => [...prev, { id, name }]);
      setPeerNames(prev => ({ ...prev, [id]: name || 'Guest' }));
    });
    socket.on('peer-left', ({ id }) => {
      setPeers(prev => prev.filter(p => p.id !== id));
      const pc = pcMap.current.get(id); if (pc) pc.close();
      pcMap.current.delete(id);
      setRemoteVideos(prev => { const x = { ...prev }; delete x[id]; return x; });
    });
    socket.on('signal', handleSignal);

    socket.on('chat', (payload) => {
      setMessages(m => [...m, payload]);
      setTimeout(()=> chatRef.current && (chatRef.current.scrollTop = chatRef.current.scrollHeight), 0);
    });

    socket.on('quiz:new', (quiz) => { setLiveQuiz(quiz); setMyAnswer(null); });
    socket.on('quiz:answered', (r) => {});

    socket.on('session:summary', (payload) => {
      alert(`สรุปผลส่งถึงผู้สร้าง\n${JSON.stringify(payload, null, 2)}`);
    });
    socket.on('session:end:denied', () => alert('ยุติห้องไม่ได้: ต้องเป็นผู้สร้างห้อง'));

    socket.on('session:ended', ({ forceLeave, payload }) => {
      alert(`ห้องนี้ถูกยุติแล้ว\n${JSON.stringify(payload, null, 2)}`);
      cleanupAndLeave();
      navigate('#/dashboard');
    });

    (async () => {
      await setupMedia();
      socket.emit('join', { roomId, name: profileName });
    })();

    return () => socket.disconnect();
  }, []);

  const cleanupAndLeave = () => {
    try { localStreamRef.current?.getTracks()?.forEach(t => t.stop()); } catch {}
    localStreamRef.current = null;
    for (const [id, pc] of pcMap.current.entries()) { try { pc.close(); } catch {} }
    pcMap.current.clear();
    setRemoteVideos({});
    setPeers([]);
    try { socketRef.current?.disconnect(); } catch {}
  };

  const sendChat = (e) => {
    e.preventDefault();
    const text = e.target.elements.msg.value.trim();
    if (!text) return;
    socketRef.current.emit('chat', text);
    e.target.reset();
  };

  const createQuiz = () => {
    if (!question || options.filter(o => o.trim()).length < 2) return alert('กรอกคำถามและตัวเลือกอย่างน้อย 2 ข้อ');
    socketRef.current.emit('quiz:create', { roomId, question, options, correctIndex, createdBy: profileName });
    setQuestion(''); setOptions(['','','']); setCorrectIndex(null);
  };

  const answerQuiz = (idx) => {
    if (!liveQuiz) return;
    setMyAnswer(idx);
    socketRef.current.emit('quiz:answer', { quizId: liveQuiz.id, userId: myIdRef.current, displayName: profileName, answerIndex: idx });
  };

  return (<>
    <TopNav right={<>
      <a className="btn" href="#/dashboard">Dashboard</a>
      <button className="btn ghost" onClick={()=>window.open('#/history','_blank')}>ประวัติ</button>
    </>} />
    <div className="container">
      <div className="room-grid">
        <div className="card" style={{gridColumn:'1 / 2'}}>
          <div className="title">ห้อง: {roomId}</div>
          <div className="row"><span className="pill">ฉัน: {profileName}{isCreator?' • ผู้สร้าง':''}</span></div>

          <div className="section-title">วิดีโอคอล</div>
          <div className="videos">
            <div className="video-wrap">
              <video ref={localVideoRef} autoPlay playsInline muted></video>
              <div className="name-tag">{profileName}</div>
            </div>
            {Object.entries(remoteVideos).map(([peerId, stream]) => (
              <RemoteMedia key={peerId} stream={stream} name={peerNames[peerId] || peerId.slice(0,6)} speakersOn={true} />
            ))}
          </div>

          <div className="controls" style={{marginTop:10}}>
            <button className="btn" onClick={()=>{
              const t = localStreamRef.current?.getAudioTracks?.()[0];
              if (t){ t.enabled = !t.enabled; }
            }}>สลับไมค์</button>
            <button className="btn" onClick={()=>{
              const v = localStreamRef.current?.getVideoTracks?.()[0];
              if (v){ v.enabled = !v.enabled; }
            }}>สลับกล้อง</button>
            {isCreator && <button className="btn primary" onClick={()=> socketRef.current.emit('session:end', { roomId })}>จบการสนทนา</button>}
          </div>
        </div>

        <div className="card" style={{gridColumn:'2 / 3', position:'sticky', top:24, alignSelf:'start'}}>
          <div className="title">แชท</div>
          <div ref={chatRef} className="chatbox">
            {messages.map((m, i) => (
              <div key={i} className="chat-item"><strong>{m.name||'ไม่ทราบชื่อ'}</strong><span className="chat-time">{m.ts ? new Date(m.ts).toLocaleTimeString() : ''}</span>: {m.msg}</div>
            ))}
          </div>
          <form onSubmit={sendChat} className="controls">
            <input name="msg" placeholder="พิมพ์แชท..." style={{flex:1}} />
            <button className="btn">ส่ง</button>
          </form>

          <div className="section-title">Quiz</div>
          {isCreator ? (<>
            <div className="row">
              <input placeholder="คำถาม" value={question} onChange={e=>setQuestion(e.target.value)} style={{flex:1}}/>
              <button className="btn" onClick={()=> setOptions([...options, ''])}>+ ตัวเลือก</button>
            </div>
            {options.map((opt, i) => (
              <div key={i} className="row">
                <input placeholder={'ตัวเลือก ' + (i+1)} value={opt} onChange={e=>{
                  const next = [...options]; next[i] = e.target.value; setOptions(next);
                }} style={{flex:1}}/>
                <label className="row" style={{fontSize:12}}>
                  <input type="radio" checked={correctIndex===i} onChange={()=>setCorrectIndex(i)} /> เฉลย
                </label>
              </div>
            ))}
            <div className="controls">
              <button className="btn primary" onClick={createQuiz}>ส่ง Quiz</button>
            </div>
          </>) : (
            <p className="muted">รอผู้สร้างห้องเริ่ม Quiz…</p>
          )}

          {liveQuiz && (
            <div style={{marginTop:12}}>
              <div className="title" style={{fontSize:16}}>คำถาม: {liveQuiz.question}</div>
              <div className="grid" style={{gridTemplateColumns:'1fr 1fr'}}>
                {liveQuiz.options.map((opt, i) => (
                  <div key={i} className={'option ' + (myAnswer===i ? 'selected' : '')} onClick={()=>answerQuiz(i)}>
                    {String.fromCharCode(65+i)}. {opt}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  </>);
}

function RemoteMedia({ stream, name, speakersOn }){
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
      <div className="name-tag">{name}</div>
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
      const res = await fetch(`${SERVER_URL}/api/history${qs}`);
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
