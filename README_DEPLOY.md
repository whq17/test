# Deployable Bundle: WebRTC Rooms (HTTPS + TURN) • Docker Compose

บริการที่รวมมาให้:
- **app**: Node.js (Express + Socket.IO) เสิร์ฟเว็บและ signaling บนพอร์ต 4000
- **caddy**: reverse proxy + **HTTPS อัตโนมัติ** (Let's Encrypt)
- **turn**: **coturn** สำหรับ NAT traversal (3478/5349)

> โค้ดฝั่งแอปอยู่ในโฟลเดอร์ `app/` (พร้อมระบบ Login, Session เป็น per-browser session, Owner-only Quiz, History เฉพาะเจ้าของ)

---

## 1) เตรียมโดเมน
ตั้ง A/AAAA record ให้ `CADDY_DOMAIN` ชี้มาที่ IP ของเครื่อง (VPS)

## 2) ตั้งค่า .env
คัดลอก `.env.example` ไปเป็น `.env` แล้วแก้ค่าให้ถูกต้อง:
```bash
cp .env.example .env
# แก้:
# CADDY_DOMAIN=meet.yourdomain.com
# CADDY_EMAIL=you@yourdomain.com
# JWT_SECRET=สุ่มใหม่ยาวๆ
# TURN_REALM=yourdomain.com
# TURN_USER=appuser
# TURN_PASS=StrongRandomPassword123
```

## 3) รัน (Production)
ต้องติดตั้ง Docker + Docker Compose ก่อน จากนั้น:
```bash
docker compose up -d --build
```
เสร็จแล้วเข้าใช้งานที่:
```
https://<CADDY_DOMAIN>
```
Caddy จะออกใบรับรอง TLS ให้โดยอัตโนมัติ (ต้องตั้ง DNS ไว้ล่วงหน้า)

> ถ้ามี Firewall/UFW: เปิดพอร์ต 80/tcp, 443/tcp, 3478/5349 ทั้ง tcp/udp

## 4) ตั้งค่า TURN ในโค้ด (ถ้าจะใช้เซิร์ฟเวอร์ TURN นี้)
ปัจจุบันโค้ดใช้ `stun:stun.l.google.com:19302` อยู่แล้ว คุณอาจเพิ่ม TURN เพิ่มเติมในฝั่ง client (ไฟล์ `app/client/src/App.jsx`, ใน `new RTCPeerConnection({ iceServers: [...] })`):
```js
{ urls: 'turn:' + window.location.hostname + ':3478', username: 'appuser', credential: 'StrongRandomPassword123' }
```
> ถ้าเปิด TLS สำหรับ TURN ให้ใช้ `turns:` และพอร์ต 5349 พร้อมใส่ cert/pkey ในไฟล์ `turn/turnserver.conf` (และ mount certs เข้า container)

## 5) อัปเดตโค้ดแอปแล้ว deploy ใหม่
วางโค้ดใหม่ทับใน `app/` แล้วรัน:
```bash
docker compose up -d --build
```

## 6) โหมด Dev (ไม่แนะนำบนอินเทอร์เน็ต)
หากต้องการรัน dev แบบแยก (ไม่มี HTTPS):
```bash
# ในเครื่องนักพัฒนา
cd app/server && npm install && cp .env.example .env && npm run init:db && npm run dev
# และอีกหน้าต่าง
cd app/client && npm install && cp .env.example .env && npm run dev
# เปิด http://localhost:5173
```
> หมายเหตุ: เบราว์เซอร์บางตัวจะบล็อกกล้อง/ไมค์บน HTTP (นอก localhost)

## Notes
- SQLite เก็บใน volume `appdata` ของ Docker (ไม่หายเมื่อ container restart)
- ถ้าผู้ใช้เยอะ/สเกลหลายเครื่อง: แนะนำย้าย DB ไป PostgreSQL และเปิด socket.io adapter (redis) + sticky session
- ความปลอดภัย: เปลี่ยน `JWT_SECRET`, ตั้งรหัส TURN ให้เดายาก, จำกัด CORS ใน `.env` ฝั่งแอป (ถ้าต้องการ)

Good luck & have fun 🚀
