# Minimal UI • Rooms + Video Call + Quiz + History (open history in new tab)

## Run
### Server
```powershell
cd server
npm install
Copy-Item .env.example .env
npm run init:db
npm run dev
```

### Client
```powershell
cd ../client
npm install
Copy-Item .env.example .env
npm run dev
```

Open http://localhost:5173

## What’s new
- **Minimal, clean UI** (Inter-like look, soft borders, name overlays on videos)
- **Name overlay** matches **profile name** you set on Dashboard
- **History opens in a new tab** (`#/history`) via the Dashboard button
- **Peers list includes names** (server tracks socketId→name; initial peers come with names)
- Creator-only **End Session** → everyone gets kicked + creator receives summary
