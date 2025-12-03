# Multi-stage build for Love2D web deployment
# Stage 1: Build with love.js
# Stage 2: Serve with nginx

# ============================================
# Stage 1: Build the game with love.js
# ============================================
FROM node:20-alpine AS build

WORKDIR /app

# Install love.js globally
# Using Davidobot's actively maintained fork
RUN npm install -g love.js

# Copy game source files
COPY game/ ./game/

# Optional: Comment out t.version in conf.lua for compatibility
# Some love.js versions are strict about version matching
RUN if [ -f ./game/conf.lua ]; then \
      sed -i "s/t.version/-- t.version/" ./game/conf.lua; \
    fi

# Build the game for web
ARG GAME_TITLE="Hello World Love2D"
ARG GAME_MEMORY=33554432

RUN love.js ./game ./dist \
    --title "${GAME_TITLE}" \
    --memory ${GAME_MEMORY}

# ============================================
# Stage 2: Serve with nginx
# ============================================
FROM nginx:alpine AS production

# Copy custom nginx config with required CORS headers
COPY nginx.conf /etc/nginx/nginx.conf

# Copy built game from build stage
COPY --from=build /app/dist /usr/share/nginx/html

# Expose port 80 (nginx default)
EXPOSE 80

# nginx runs automatically as the default command
