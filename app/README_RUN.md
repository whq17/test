# Run on http://localhost:4000 (Server serves Client build)

## Quick Start
### 1) Start Server (builds client automatically)
```powershell
cd server
npm install
Copy-Item .env.example .env
npm run init:db
npm run serve
```
เปิดเบราว์เซอร์ไปที่ **http://localhost:4000**

### Dev Mode (แยก 2 หน้าต่าง)
- Server:
  ```powershell
  cd server
  npm install
  Copy-Item .env.example .env
  npm run init:db
  npm run dev
  ```
- Client (hot reload): 
  ```powershell
  cd ../client
  npm install
  Copy-Item .env.example .env
  npm run dev
  ```
  เปิด http://localhost:5173

> โปรดอนุญาตสิทธิ์กล้อง/ไมโครโฟน และถ้าจะใช้งานนอก localhost แนะนำใช้ HTTPS + TURN server.


## Login system
- สมัคร/ล็อกอินได้ที่ `#/auth`
- รหัสผ่านถูกเก็บในฐานข้อมูลแบบ **แฮช (bcrypt)**
- ต้องล็อกอินก่อนถึงจะ **สร้างห้อง** และดู **History** ได้
