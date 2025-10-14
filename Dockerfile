# -------- Builder: install & build client --------
FROM node:20-alpine AS builder
WORKDIR /app
COPY app/server ./server
COPY app/client ./client

# Install deps
RUN cd server && npm ci
RUN cd client && npm ci

# Build client
RUN cd client && npm run build

# -------- Runtime image --------
FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
# Copy server
COPY --from=builder /app/server ./server
# Copy built client
COPY --from=builder /app/client/dist ./client/dist

# Create data dir for sqlite
RUN mkdir -p /app/server/data
VOLUME ["/app/server/data"]

# Default envs
ENV PORT=4000
ENV ORIGIN=https://localhost
ENV DATABASE_PATH=./data/app.sqlite
ENV JWT_SECRET=change_me_prod_secret

# Expose port
EXPOSE 4000

# Start server
WORKDIR /app/server
# ensure DB created
CMD [ "sh", "-c", "node scripts/init-db.js && node index.js" ]
