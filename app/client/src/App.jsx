import React, { useEffect, useRef, useState } from 'react';
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
  const [participants, setParticipants] = useState([]); // ✳️ รายชื่อผู้เข้าร่วม

  const [isSharingScreen, setIsSharingScreen] = useState(false); 
  
  // ✳️ Media Control States
  const [isMicOn, setIsMicOn] = useState(true);
  const [isCameraOn, setIsCameraOn] = useState(true);

  const [messages, setMessages] = useState([]);
  const chatRef = useRef(null);

  // quiz
  const [question, setQuestion] = useState('');
  const [options, setOptions] = useState(['', '', '']);
  const [correctIndex, setCorrectIndex] = useState(null);
  const [liveQuiz, setLiveQuiz] = useState(null);
  const [myAnswer, setMyAnswer] = useState(null);
  
  // ✳️ Quiz Timer States
  const [quizDuration, setQuizDuration] = useState(60); // ผู้สร้างตั้งค่า (วินาที)
  const [countdown, setCountdown] = useState(null); // เวลาที่เหลือ (วินาที)
  const timerIdRef = useRef(null); // ใช้เก็บ ID ของ setInterval

  // media
  const localVideoRef = useRef(null);
  const [remoteVideos, setRemoteVideos] = useState({}); // id->MediaStream
  const socketRef = useRef(null);
  const localStreamRef = useRef(null);
  const pcMap = useRef(new Map());
  const myIdRef = useRef(uuidv4());

  // ✳️ Function: สลับปิด/เปิด ไมค์
  const toggleMic = () => {
    const track = localStreamRef.current?.getAudioTracks?.()[0];
    if (track) { track.enabled = !track.enabled; setIsMicOn(track.enabled); }
  };
  
  // ✳️ Function: สลับปิด/เปิด กล้อง
  const toggleCamera = () => {
    const track = localStreamRef.current?.getVideoTracks?.()[0];
    if (track) { track.enabled = !track.enabled; setIsCameraOn(track.enabled); }
  };

  const toggleScreenShare = async () => {
  try {
    if (isSharingScreen) {
      // ⛔️ หยุดแชร์จอ -> กลับมากล้อง/ไมค์
      localStreamRef.current?.getVideoTracks?.().forEach(t => t.stop());

      const cam = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
      localStreamRef.current = cam;
      if (localVideoRef.current) localVideoRef.current.srcObject = cam;

      // แทนที่ track บน PeerConnection ทุกตัว
      for (const pc of pcMap.current.values()) {
        const v = pc.getSenders().find(s => s.track && s.track.kind === 'video');
        if (v) v.replaceTrack(cam.getVideoTracks()[0]);
        const a = pc.getSenders().find(s => s.track && s.track.kind === 'audio');
        if (a && cam.getAudioTracks()[0]) a.replaceTrack(cam.getAudioTracks()[0]);
      }

      setIsSharingScreen(false);
      setIsMicOn(true); 
      setIsCameraOn(true);
      return;
    }

    // 🟢 เริ่มแชร์จอ (ขอเฉพาะวิดีโอจอ; ใช้ไมค์เดิม)
    const screen = await navigator.mediaDevices.getDisplayMedia({ video: true });
    const mic = localStreamRef.current?.getAudioTracks?.()[0] || null;
    const combined = new MediaStream([screen.getVideoTracks()[0], ...(mic ? [mic] : [])]);

    localStreamRef.current = combined;
    if (localVideoRef.current) localVideoRef.current.srcObject = combined;

    // ส่งภาพหน้าจอไปทุก peer
    for (const pc of pcMap.current.values()) {
      const v = pc.getSenders().find(s => s.track && s.track.kind === 'video');
      if (v) v.replaceTrack(combined.getVideoTracks()[0]);
    }

    // ผู้ใช้กด Stop sharing ใน UI เบราว์เซอร์ -> สลับกลับอัตโนมัติ
    screen.getVideoTracks()[0].onended = () => {
      if (isSharingScreen) toggleScreenShare();
    };

    setIsSharingScreen(true);
    setIsCameraOn(false); // กล้องถูกแทนที่ด้วยจอ
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
      setParticipants(others.map(o => o.name || 'Guest').concat(profileName)); // ✳️ อัปเดตรายชื่อ
      for (const p of others) await makeOffer(p.id);
    });
    socket.on('peer-joined', ({ id, name }) => {
      setPeers(prev => [...prev, { id, name }]);
      setPeerNames(prev => ({ ...prev, [id]: name || 'Guest' }));
      setParticipants(prev => [...prev, name || 'Guest']); // ✳️ อัปเดตรายชื่อ
    });
    socket.on('peer-left', ({ id, name }) => {
      setPeers(prev => prev.filter(p => p.id !== id));
      const pc = pcMap.current.get(id); if (pc) pc.close();
      pcMap.current.delete(id);
      setRemoteVideos(prev => { const x = { ...prev }; delete x[id]; return x; });
      setParticipants(prev => prev.filter(n => n !== name)); // ✳️ อัปเดตรายชื่อ
    });
    socket.on('signal', handleSignal);

    socket.on('chat', (payload) => {
      setMessages(m => [...m, payload]);
      setTimeout(()=> chatRef.current && (chatRef.current.scrollTop = chatRef.current.scrollHeight), 0);
    });

    // ✳️ Quiz Logic: เมื่อได้รับ Quiz ใหม่
    socket.on('quiz:new', (quiz) => { 
      setLiveQuiz(quiz); 
      setMyAnswer(null); 
      
      if (timerIdRef.current) clearInterval(timerIdRef.current);
      
      const endTime = quiz.startTime + (quiz.durationSeconds * 1000);
      
      const updateTimer = () => {
        const timeLeft = Math.max(0, Math.floor((endTime - Date.now()) / 1000));
        setCountdown(timeLeft);
        if (timeLeft === 0) {
            clearInterval(timerIdRef.current);
            timerIdRef.current = null;
        }
      };
      updateTimer();
      timerIdRef.current = setInterval(updateTimer, 1000);
    });

    // ✳️ Time-up Logic: เมื่อ Server แจ้งว่าหมดเวลา (พร้อมเฉลย)
    socket.on('quiz:time-up', ({ quizId, correctIndex }) => {
        if (timerIdRef.current) clearInterval(timerIdRef.current);
        timerIdRef.current = null;
        
        setLiveQuiz(prev => {
            if (prev && prev.id === quizId) {
                return { ...prev, correctIndex: correctIndex }; 
            }
            return prev;
        });
        setCountdown(0); 
    });

    socket.on('quiz:denied', () => alert('สร้าง Quiz ไม่ได้: เฉพาะผู้สร้างห้องเท่านั้น'));
    socket.on('quiz:answered', (r) => {});

    socket.on('session:summary', (payload) => {
      alert(`สรุปผลส่งถึงผู้สร้าง\n${JSON.stringify(payload, null, 2)}`);
    });
    socket.on('session:end:denied', () => alert('ยุติห้องไม่ได้: ต้องเป็นผู้สร้างห้อง'));

    socket.on('session:ended', ({ forceLeave, payload }) => {
      alert(`ห้องนี้ถูกยุติแล้ว\n${JSON.stringify(payload, null, 2)}`);
      cleanupAndLeave();
      // stay in same tab & keep token/profile in localStorage
      navigate('#/dashboard');
    });

 socket.on('room-participants', (participantsData) => {
            // ✅ เก็บ Array ของ Object { id, name } เต็มรูปแบบ
            setParticipants(participantsData); 
        });


    (async () => {
      await setupMedia();
      socket.emit('join', { roomId, name: profileName });
      setParticipants([profileName]); // ✳️ ตั้งค่าชื่อตัวเองเมื่อ Join
    })();

    return () => {
      if (timerIdRef.current) clearInterval(timerIdRef.current); // ✳️ Cleanup Timer
      cleanupAndLeave();
      socket.disconnect();
    };
  }, []);

  const cleanupAndLeave = () => {
    try { localStreamRef.current?.getTracks()?.forEach(t => t.stop()); } catch {}
    localStreamRef.current = null;
    for (const [id, pc] of pcMap.current.entries()) { try { pc.close(); } catch {} }
    pcMap.current.clear();
    setRemoteVideos({});
    setPeers([]);
    // socketRef.current?.disconnect(); // จัดการแล้วใน useEffect return
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
    if (correctIndex === null) return alert('กรุณาเลือกเฉลย'); 

    // ✳️ ส่ง durationSeconds ไปยัง Server
    socketRef.current.emit('quiz:create', { 
      roomId, 
      question, 
      options, 
      correctIndex, 
      createdBy: profileName,
      durationSeconds: quizDuration // ส่งเวลาที่ตั้งค่า
    });
    setQuestion(''); setOptions(['','','']); setCorrectIndex(null);
    setCountdown(null);
  };

  const answerQuiz = (idx) => {
    if (!liveQuiz) return;
    setMyAnswer(idx);
    socketRef.current.emit('quiz:answer', { quizId: liveQuiz.id, userId: myIdRef.current, displayName: profileName, answerIndex: idx });
  };

  const endSession = () => {
    if (!isCreator) return alert('ต้องเป็นผู้สร้างห้องเท่านั้น');
    socketRef.current.emit('session:end', { roomId });
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
            {/* ✳️ ปุ่มควบคุมไมค์/กล้อง */}
            <button className="btn" onClick={toggleMic}>
              {isMicOn ? 'ปิดไมค์' : 'เปิดไมค์'}
            </button>
            <button className="btn" onClick={toggleCamera}>
              {isCameraOn ? 'ปิดกล้อง' : 'เปิดกล้อง'}
            </button>

            <button className="btn primary small" onClick={toggleScreenShare}>
              {isSharingScreen ? 'หยุดแชร์จอ' : 'แชร์จอ'}
            </button>
            
            {isCreator && <button className="btn primary" onClick={endSession}>จบการสนทนา</button>}
          </div>
        </div>

        <div className="card" style={{gridColumn:'2 / 3', position:'sticky', top:24, alignSelf:'start'}}>
          {/* ✳️ ส่วนแสดงรายชื่อผู้เข้าร่วม */}

<div className="section-title">👥 ผู้เข้าร่วม ({peers.length + 1})</div>

<div className="participants-list" style={{ marginTop: 10, maxHeight: 200, overflowY: 'auto' }}>

                {participants.map((p, index) => (

                    <div key={index} style={{

                        padding: '4px 0',

                        borderBottom: '1px dotted #000000ff',

                        fontWeight: p.isHost ? 'bold' : 'normal',

                        color: p.isHost ? 'var(--red)' : 'var(--dark)'

                    }}>

                        {p.displayName} {p.isHost && '(เจ้าของห้อง)'}

                    </div>

                ))}

            </div>


          <ul className="participant-list">
            {participants.map(name => <li key={name}>{name}</li>)}
          </ul>
          <style>{`.participant-list { list-style: none; padding: 0; margin-bottom: 20px; max-height: 150px; overflow-y: auto; } .participant-list li { padding: 6px 0; border-bottom: 1px solid var(--border); } .participant-list li:last-child { border-bottom: none; }`}</style>
          
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
            {/* ✳️ ส่วนผู้สร้าง: ช่องตั้งเวลาตอบ */}
            <div className="row" style={{marginBottom: 10, alignItems: 'center'}}>
              <label style={{whiteSpace: 'nowrap', marginRight: 10}}>เวลาตอบ (วินาที):</label>
              <input 
                type="number" 
                min="5" 
                max="300" 
                value={quizDuration} 
                onChange={e=>setQuizDuration(Math.max(5, Math.min(300, parseInt(e.target.value) || 60)))} 
                style={{width: 80, textAlign: 'center'}}
              />
            </div>

            <div className="row" style={{marginBottom: 10}}>
              <input placeholder="คำถาม" value={question} onChange={e=>setQuestion(e.target.value)} style={{flex:1}}/>
            </div>
            <div className="controls" style={{justifyContent: 'flex-start', marginBottom: 10}}>
              <button className="btn ghost small" onClick={()=> setOptions([...options, ''])}>+ เพิ่มตัวเลือก</button>
            </div>
            
            {options.map((opt, i) => (
              <div key={i} className="row" style={{alignItems: 'center', marginBottom: 8}}>
                <label className="row" style={{fontSize:12, marginRight: 8, cursor: 'pointer', whiteSpace: 'nowrap'}}>
                  <input type="radio" name="correctAnswer" checked={correctIndex===i} onChange={()=>setCorrectIndex(i)} /> เฉลย
                </label>
                <input placeholder={'ตัวเลือก ' + (i+1)} value={opt} onChange={e=>{
                  const next = [...options]; next[i] = e.target.value; setOptions(next);
                }} style={{flex:1}}/>
                {options.length > 2 && ( // อนุญาตให้ลบได้ถ้ามีมากกว่า 2 ตัวเลือก
                  <button className="btn ghost small" onClick={() => {
                      const next = options.filter((_, idx) => idx !== i);
                      setOptions(next);
                      if (correctIndex === i) setCorrectIndex(null);
                      else if (correctIndex !== null && correctIndex > i) setCorrectIndex(correctIndex - 1);
                  }} style={{marginLeft: 8, color: 'var(--red)'}}>ลบ</button>
                )}
              </div>
            ))}

            <div className="controls">
              <button 
                  className="btn primary" 
                  onClick={createQuiz}
                  disabled={!question.trim() || options.filter(o => o.trim()).length < 2 || correctIndex === null}
              >
                ส่ง Quiz เริ่มถาม
              </button>
            </div>
          </>) : (
            <p className="muted">รอผู้สร้างห้องเริ่ม Quiz…</p>
          )}

          {liveQuiz && (
            <div style={{marginTop:12}}>
              <div className="title" style={{fontSize:16}}>
                คำถาม: {liveQuiz.question}
                {/* ✳️ แสดงเวลาถอยหลัง */}
                {countdown !== null && (
                    <span style={{float: 'right', color: countdown > 10 ? 'var(--blue)' : 'var(--red)', fontWeight: 'bold'}}>
                      ⏱️ {countdown} วินาที
                    </span>
                )}
              </div>
              
                <div className="grid" style={{gridTemplateColumns:'1fr 1fr'}}>
                {liveQuiz.options.map((opt, i) => {
                  const isAnswered = myAnswer === i;
                  const isCorrect = liveQuiz.correctIndex !== null && i === liveQuiz.correctIndex;
                  const isQuizEnded = countdown !== null && countdown === 0;
                  const canAnswer = countdown > 0 && myAnswer === null;
                  
                  // กำหนด Style ตามสถานะ (หมดเวลา/เฉลย)
                  let optionStyle = {};
                  if (isQuizEnded) {
                      if (isCorrect) optionStyle = {backgroundColor: '#d4edda', borderColor: '#155724', fontWeight: 'bold'}; 
                      else if (isAnswered) optionStyle = {backgroundColor: '#f8d7da', borderColor: '#721c24'}; 
                  } else if (isAnswered) {
                      optionStyle = {backgroundColor: 'var(--blue-light)'};
                  }
                  
                  return (
                    <div 
                        key={i} 
                        className={'option ' + (isAnswered && !isQuizEnded ? 'selected' : '')}
                        onClick={()=> { if (canAnswer) answerQuiz(i); }} // ✳️ ตอบได้เมื่อยังไม่หมดเวลาและยังไม่เคยตอบ
                        style={{ cursor: canAnswer ? 'pointer' : 'default', ...optionStyle }}
                    >
                      {String.fromCharCode(65+i)}. {opt}
                      
                      {/* ✳️ แสดงเฉลยเมื่อหมดเวลา */}
                      {isQuizEnded && isCorrect && <span style={{marginLeft: 5}}>✅ เฉลย</span>}
                      {isQuizEnded && isAnswered && !isCorrect && <span style={{marginLeft: 5}}>❌ คำตอบของคุณ</span>}
                    </div>
                  ); // <--- อย่าลืม ; ที่นี่
                })}
              </div>
             
              
              {isQuizEnded && liveQuiz.correctIndex !== null && myAnswer === null && (
                  <p style={{color: 'var(--red)', fontWeight: 'bold', marginTop: 10}}>คุณไม่ได้ตอบคำถามนี้</p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  </>);
} // <--- จบ Room Component ตรงนี้

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
