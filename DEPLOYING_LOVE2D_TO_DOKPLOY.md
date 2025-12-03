# Deploying a Love2D Game to Dokploy using love.js

This guide explains how to create a GitHub Action that automatically deploys your Love2D game to the web using [Davidobot's love.js](https://github.com/Davidobot/love.js) and Dokploy, based on the website deployment workflow in this repository.

## Table of Contents

1. [Overview](#overview)
2. [Repository Architecture](#repository-architecture)
3. [Prerequisites](#prerequisites)
4. [Step-by-Step Setup](#step-by-step-setup)
5. [The Dockerfile](#the-dockerfile)
6. [The GitHub Action](#the-github-action)
7. [Dokploy Configuration](#dokploy-configuration)
8. [Common Issues & Solutions](#common-issues--solutions)
9. [Sources & References](#sources--references)

---

## Overview

### What is love.js?

[love.js](https://github.com/Davidobot/love.js) is a port of the LOVE 2D game framework to the web using Emscripten. It compiles your Love2D game (written in Lua) to WebAssembly, allowing it to run in modern web browsers.

### How This Deployment Works

1. **Push code** to your GitHub repository
2. **GitHub Action** triggers and calls Dokploy API
3. **Dokploy** pulls your code and builds the Docker image
4. **Docker** runs love.js to compile your game and serves it via nginx
5. **Your game** is now playable on the web!

---

## Repository Architecture

### Recommended Folder Structure

For a **standalone Love2D game repository**, use this structure:

```
my-love2d-game/
├── .github/
│   └── workflows/
│       ├── deploy-dokploy.yml      # Deploy on push
│       └── cleanup-dokploy.yml     # Cleanup on branch delete
├── game/                           # Your Love2D game source
│   ├── main.lua                    # Entry point (required)
│   ├── conf.lua                    # Configuration (optional but recommended)
│   ├── assets/                     # Graphics, sounds, etc.
│   │   ├── images/
│   │   ├── sounds/
│   │   └── fonts/
│   ├── src/                        # Game logic modules
│   │   ├── player.lua
│   │   ├── enemies.lua
│   │   └── ...
│   └── lib/                        # Third-party libraries
│       └── ...
├── Dockerfile                      # Multi-stage build with love.js + nginx
├── nginx.conf                      # Custom nginx config with required headers
└── README.md
```

### For a Monorepo (like this repository)

If your Love2D game is part of a monorepo with other projects:

```
monorepo/
├── .github/
│   └── workflows/
│       ├── love2d-game-deploy-dokploy.yml
│       └── love2d-game-cleanup-dokploy.yml
├── love2d-game/                    # Your game subfolder
│   ├── game/                       # Game source files
│   │   ├── main.lua
│   │   ├── conf.lua
│   │   ├── assets/
│   │   └── src/
│   ├── Dockerfile
│   └── nginx.conf
├── website/                        # Other projects...
└── other-project/
```

### Key Files Explained

| File | Purpose |
|------|---------|
| `main.lua` | **Required.** Entry point with `love.load()`, `love.update(dt)`, `love.draw()` |
| `conf.lua` | Configuration: window size, title, version, identity |
| `Dockerfile` | Multi-stage build: love.js compilation + nginx serving |
| `nginx.conf` | Custom headers for SharedArrayBuffer (required for pthreads) |
| `deploy-dokploy.yml` | GitHub Action to deploy to Dokploy |
| `cleanup-dokploy.yml` | GitHub Action to cleanup on branch deletion |

---

## Prerequisites

### 1. Dokploy Instance

You need a running Dokploy instance. Set up these in your GitHub repository:

**Repository Variables** (`Settings > Secrets and variables > Actions > Variables`):
- `DOKPLOY_URL` - Your Dokploy instance URL (e.g., `https://dokploy.example.com`)
- `DOKPLOY_PROJECT_ID` - Project ID in Dokploy
- `DOKPLOY_ENVIRONMENT_ID` - Environment ID for deployments
- `DOKPLOY_GITHUB_ID` - GitHub integration ID in Dokploy
- `DOKPLOY_SERVER_ID` - Server ID where app will be deployed

**Repository Secrets** (`Settings > Secrets and variables > Actions > Secrets`):
- `DOKPLOY_API_KEY` - API key generated in Dokploy

### 2. Love2D Game

Your game should:
- Work with **LOVE 11.5** (the version love.js supports)
- Avoid LuaJIT-specific features (FFI, bitops)
- Use Lua 5.1 compatible code (no `goto` statement)

### 3. Self-Hosted Runner (Optional)

The original workflow uses `runs-on: self-hosted`. You can change this to `runs-on: ubuntu-latest` if you don't have a self-hosted runner.

---

## Step-by-Step Setup

### Step 1: Create Your Game Folder Structure

```bash
mkdir -p my-love2d-game/game/assets/{images,sounds,fonts}
mkdir -p my-love2d-game/game/src
mkdir -p my-love2d-game/game/lib
mkdir -p my-love2d-game/.github/workflows
```

### Step 2: Create main.lua

Create `game/main.lua`:

```lua
function love.load()
    -- Initialize your game
    message = "Hello, Web!"
end

function love.update(dt)
    -- Update game state
end

function love.draw()
    love.graphics.print(message, 400, 300)
end
```

### Step 3: Create conf.lua

Create `game/conf.lua`:

```lua
function love.conf(t)
    t.title = "My Love2D Game"
    t.version = "11.5"  -- Important: match love.js version
    t.window.width = 800
    t.window.height = 600
    t.window.resizable = false

    -- Recommended settings for web
    t.modules.thread = false  -- Threads have limited browser support
end
```

> **Note:** You may need to comment out `t.version` for compatibility with some love.js builds. The Dockerfile handles this automatically.

### Step 4: Create the Dockerfile

See [The Dockerfile](#the-dockerfile) section below.

### Step 5: Create nginx.conf

See [The Dockerfile](#the-dockerfile) section below.

### Step 6: Create GitHub Actions

See [The GitHub Action](#the-github-action) section below.

### Step 7: Configure Dokploy

See [Dokploy Configuration](#dokploy-configuration) section below.

---

## The Dockerfile

Create `Dockerfile` in your repository root:

```dockerfile
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
# Options:
#   -t, --title: Game title shown in browser tab
#   -m, --memory: Memory allocation in bytes (default: 16MB, increase for larger games)
#   -c, --compatibility: Use compatibility mode (wider browser support, worse audio)
#
# Memory guide:
#   - Simple games: 16777216 (16MB) - default
#   - Medium games: 33554432 (32MB)
#   - Complex games: 67108864 (64MB)
#   - Large games: 134217728 (128MB)

ARG GAME_TITLE="Love2D Game"
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
```

### Create nginx.conf

Create `nginx.conf` in your repository root. This is **critical** for love.js to work properly:

```nginx
# nginx configuration for Love2D web games
# Includes required headers for SharedArrayBuffer (pthreads support)

worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               application/wasm;

    server {
        listen 80;
        server_name localhost;
        root /usr/share/nginx/html;
        index index.html;

        # CRITICAL: Required headers for SharedArrayBuffer (pthreads)
        # Without these, love.js will fall back to compatibility mode
        # which has degraded audio quality
        add_header Cross-Origin-Opener-Policy "same-origin" always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;

        # Cache static assets
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|wasm|data)$ {
            expires 1y;
            add_header Cache-Control "public, immutable";
            # Re-add CORS headers (add_header in location blocks override parent)
            add_header Cross-Origin-Opener-Policy "same-origin" always;
            add_header Cross-Origin-Embedder-Policy "require-corp" always;
        }

        # Handle SPA routing (optional, for games with multiple HTML pages)
        location / {
            try_files $uri $uri/ /index.html;
        }

        # Health check endpoint
        location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
        }
    }
}
```

### Why These Headers Are Important

The `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers enable **cross-origin isolation**, which is required for:

- **SharedArrayBuffer**: Used by love.js for threading (better audio)
- **High-resolution timers**: More accurate `love.timer.getDelta()`

Without these headers, love.js falls back to **compatibility mode** with degraded audio quality.

---

## The GitHub Action

### Deploy Workflow

Create `.github/workflows/love2d-deploy-dokploy.yml`:

```yaml
name: Love2D Game - Deploy to Dokploy

on:
  push:
    paths:
      - "game/**"
      - "Dockerfile"
      - "nginx.conf"
      - ".github/workflows/love2d-deploy-dokploy.yml"
  workflow_dispatch:  # Allow manual triggers

jobs:
  deploy:
    runs-on: ubuntu-latest  # Or 'self-hosted' if you have a runner

    steps:
      - name: Checkout code
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Display Configuration
        env:
          DOKPLOY_URL: ${{ vars.DOKPLOY_URL }}
          DOKPLOY_PROJECT_ID: ${{ vars.DOKPLOY_PROJECT_ID }}
        run: |
          echo "=========================================="
          echo "Love2D Game Deployment Configuration"
          echo "=========================================="
          echo "Repository: ${{ github.repository }}"
          echo "Branch: ${{ github.ref_name }}"
          echo "Commit: ${{ github.sha }}"
          echo "Dokploy URL: ${DOKPLOY_URL}"
          echo "=========================================="

      - name: Generate deployment metadata
        id: metadata
        run: |
          OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]' | tr '/' '-')
          REPO=$(echo "${{ github.event.repository.name }}" | tr '[:upper:]' '[:lower:]')

          # For monorepo, add project name
          PROJECT="love2d-game"

          if [ "${{ github.event_name }}" = "pull_request" ]; then
            BRANCH=$(echo "${{ github.head_ref }}" | tr '/' '-')
          else
            BRANCH=$(echo "${GITHUB_REF#refs/heads/}" | tr '/' '-')
          fi

          SHORT_SHA=$(echo "${{ github.sha }}" | cut -c1-7)
          APP_NAME="${OWNER}-${REPO}-${PROJECT}-${BRANCH}"

          # DNS subdomain limit is 63 characters
          if [ ${#APP_NAME} -gt 63 ]; then
            APP_NAME="${REPO}-${PROJECT}-${BRANCH}"
          fi
          if [ ${#APP_NAME} -gt 63 ]; then
            APP_NAME="${REPO}-${PROJECT}"
          fi

          echo "owner=${OWNER}" >> $GITHUB_OUTPUT
          echo "repo=${REPO}" >> $GITHUB_OUTPUT
          echo "project=${PROJECT}" >> $GITHUB_OUTPUT
          echo "branch=${BRANCH}" >> $GITHUB_OUTPUT
          echo "short_sha=${SHORT_SHA}" >> $GITHUB_OUTPUT
          echo "app_name=${APP_NAME}" >> $GITHUB_OUTPUT
          echo "domain_name=${APP_NAME}" >> $GITHUB_OUTPUT

          echo "App Name: ${APP_NAME}"

      - name: Get or Create Dokploy Application
        id: dokploy_app
        env:
          DOKPLOY_URL: ${{ vars.DOKPLOY_URL }}
          DOKPLOY_API_KEY: ${{ secrets.DOKPLOY_API_KEY }}
          DOKPLOY_PROJECT_ID: ${{ vars.DOKPLOY_PROJECT_ID }}
          DOKPLOY_ENVIRONMENT_ID: ${{ vars.DOKPLOY_ENVIRONMENT_ID }}
          DOKPLOY_GITHUB_ID: ${{ vars.DOKPLOY_GITHUB_ID }}
          DOKPLOY_SERVER_ID: ${{ vars.DOKPLOY_SERVER_ID }}
          APP_NAME: ${{ steps.metadata.outputs.app_name }}
        run: |
          DOKPLOY_URL="${DOKPLOY_URL%/}"

          echo "Checking if application '${APP_NAME}' exists..."

          # Get all projects
          PROJECTS=$(curl -s -X 'GET' \
            "${DOKPLOY_URL}/api/project.all" \
            -H 'accept: application/json' \
            -H "x-api-key: ${DOKPLOY_API_KEY}")

          # Find existing application
          APP_ID=$(echo "$PROJECTS" | jq -r --arg name "$APP_NAME" '
            .[] | select(.projectId == env.DOKPLOY_PROJECT_ID) |
            .environments[]? | select(.environmentId == env.DOKPLOY_ENVIRONMENT_ID) |
            .applications[]? | select(.name == $name) | .applicationId
          ' | head -n1)

          if [ -n "$APP_ID" ] && [ "$APP_ID" != "null" ]; then
            echo "Found existing application: ${APP_ID}"
          else
            echo "Creating new application..."

            REPO_OWNER="${GITHUB_REPOSITORY%%/*}"
            REPO_NAME="${GITHUB_REPOSITORY##*/}"

            CREATE_RESPONSE=$(curl -s -w "\n%{http_code}" -X 'POST' \
              "${DOKPLOY_URL}/api/trpc/application.create" \
              -H 'accept: application/json' \
              -H 'Content-Type: application/json' \
              -H "x-api-key: ${DOKPLOY_API_KEY}" \
              -d "{
                \"json\": {
                  \"name\": \"${APP_NAME}\",
                  \"projectId\": \"${DOKPLOY_PROJECT_ID}\",
                  \"environmentId\": \"${DOKPLOY_ENVIRONMENT_ID}\",
                  \"serverId\": \"${DOKPLOY_SERVER_ID}\"
                }
              }")

            CREATE_HTTP_CODE=$(echo "$CREATE_RESPONSE" | tail -n1)
            CREATE_BODY=$(echo "$CREATE_RESPONSE" | sed '$d')

            if [ "$CREATE_HTTP_CODE" -ge 200 ] && [ "$CREATE_HTTP_CODE" -lt 300 ]; then
              APP_ID=$(echo "$CREATE_BODY" | jq -r '.result.data.json.applicationId // .result.data.applicationId // .applicationId')
              echo "Application created: ${APP_ID}"

              # Disable autoDeploy
              curl -s -X 'POST' \
                "${DOKPLOY_URL}/api/trpc/application.update" \
                -H 'accept: application/json' \
                -H 'Content-Type: application/json' \
                -H "x-api-key: ${DOKPLOY_API_KEY}" \
                -d "{\"json\": {\"applicationId\": \"${APP_ID}\", \"autoDeploy\": false}}"

              # Configure GitHub provider
              curl -s -X 'POST' \
                "${DOKPLOY_URL}/api/trpc/application.saveGithubProvider" \
                -H 'accept: application/json' \
                -H 'Content-Type: application/json' \
                -H "x-api-key: ${DOKPLOY_API_KEY}" \
                -d "{
                  \"json\": {
                    \"applicationId\": \"${APP_ID}\",
                    \"githubId\": \"${DOKPLOY_GITHUB_ID}\",
                    \"repository\": \"${REPO_NAME}\",
                    \"owner\": \"${REPO_OWNER}\",
                    \"branch\": \"${{ github.ref_name }}\",
                    \"buildPath\": \"/\",
                    \"autoDeploy\": false
                  }
                }"

              # Configure build settings
              curl -s -X 'POST' \
                "${DOKPLOY_URL}/api/trpc/application.update" \
                -H 'accept: application/json' \
                -H 'Content-Type: application/json' \
                -H "x-api-key: ${DOKPLOY_API_KEY}" \
                -d "{
                  \"json\": {
                    \"applicationId\": \"${APP_ID}\",
                    \"replicas\": 1,
                    \"buildType\": \"dockerfile\",
                    \"dockerfile\": \"Dockerfile\"
                  }
                }"

              # Create domain
              DOMAIN="your-domain.com"
              OWNER="${{ steps.metadata.outputs.owner }}"
              REPO="${{ steps.metadata.outputs.repo }}"
              BRANCH="${{ steps.metadata.outputs.branch }}"
              PATH_PREFIX="/${OWNER}/${REPO}/${BRANCH}/"

              curl -s -X 'POST' \
                "${DOKPLOY_URL}/api/trpc/domain.create" \
                -H 'accept: application/json' \
                -H 'Content-Type: application/json' \
                -H "x-api-key: ${DOKPLOY_API_KEY}" \
                -d "{
                  \"json\": {
                    \"applicationId\": \"${APP_ID}\",
                    \"host\": \"${DOMAIN}\",
                    \"path\": \"${PATH_PREFIX}\",
                    \"port\": 80,
                    \"https\": true,
                    \"certificateType\": \"letsencrypt\",
                    \"domainType\": \"application\",
                    \"stripPath\": true
                  }
                }"
            else
              echo "Failed to create application"
              exit 1
            fi
          fi

          echo "application_id=${APP_ID}" >> $GITHUB_OUTPUT

      - name: Deploy to Dokploy
        env:
          DOKPLOY_URL: ${{ vars.DOKPLOY_URL }}
          DOKPLOY_API_KEY: ${{ secrets.DOKPLOY_API_KEY }}
          APPLICATION_ID: ${{ steps.dokploy_app.outputs.application_id }}
        run: |
          DOKPLOY_URL="${DOKPLOY_URL%/}"

          echo "Deploying to Dokploy..."

          RESPONSE=$(curl -s -w "\n%{http_code}" -X 'POST' \
            "${DOKPLOY_URL}/api/trpc/application.deploy" \
            -H 'accept: application/json' \
            -H 'Content-Type: application/json' \
            -H "x-api-key: ${DOKPLOY_API_KEY}" \
            -d "{\"json\": {\"applicationId\": \"${APPLICATION_ID}\"}}")

          HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

          if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
            echo "Deployment triggered successfully!"
          else
            echo "Deployment failed with status: ${HTTP_CODE}"
            exit 1
          fi

      - name: Deployment Summary
        if: always()
        run: |
          echo "## Love2D Game Deployment" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "- **Application**: ${{ steps.metadata.outputs.app_name }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Branch**: ${{ steps.metadata.outputs.branch }}" >> $GITHUB_STEP_SUMMARY
          echo "- **Commit**: ${{ steps.metadata.outputs.short_sha }}" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          if [ "${{ job.status }}" = "success" ]; then
            echo "Deployment triggered successfully!" >> $GITHUB_STEP_SUMMARY
          else
            echo "Deployment failed" >> $GITHUB_STEP_SUMMARY
          fi
```

### Cleanup Workflow

Create `.github/workflows/love2d-cleanup-dokploy.yml`:

```yaml
name: Love2D Game - Cleanup Dokploy App on Branch Delete

on:
  delete:
    branches:
      - '**'

jobs:
  cleanup:
    runs-on: ubuntu-latest
    if: github.event.ref_type == 'branch'

    steps:
      - name: Generate application name
        id: metadata
        run: |
          OWNER=$(echo "${{ github.repository_owner }}" | tr '[:upper:]' '[:lower:]' | tr '/' '-')
          REPO=$(echo "${{ github.event.repository.name }}" | tr '[:upper:]' '[:lower:]')
          PROJECT="love2d-game"
          BRANCH=$(echo "${{ github.event.ref }}" | tr '/' '-')
          APP_NAME="${OWNER}-${REPO}-${PROJECT}-${BRANCH}"

          if [ ${#APP_NAME} -gt 63 ]; then
            APP_NAME="${REPO}-${PROJECT}-${BRANCH}"
          fi

          echo "app_name=${APP_NAME}" >> $GITHUB_OUTPUT
          echo "Deleted branch: ${BRANCH}"
          echo "Application to delete: ${APP_NAME}"

      - name: Delete Dokploy Application
        env:
          DOKPLOY_URL: ${{ vars.DOKPLOY_URL }}
          DOKPLOY_API_KEY: ${{ secrets.DOKPLOY_API_KEY }}
          DOKPLOY_PROJECT_ID: ${{ vars.DOKPLOY_PROJECT_ID }}
          DOKPLOY_ENVIRONMENT_ID: ${{ vars.DOKPLOY_ENVIRONMENT_ID }}
          APP_NAME: ${{ steps.metadata.outputs.app_name }}
        run: |
          DOKPLOY_URL="${DOKPLOY_URL%/}"

          # Find application
          PROJECTS=$(curl -s -X 'GET' \
            "${DOKPLOY_URL}/api/project.all" \
            -H 'accept: application/json' \
            -H "x-api-key: ${DOKPLOY_API_KEY}")

          APP_ID=$(echo "$PROJECTS" | jq -r --arg name "$APP_NAME" '
            .[] | select(.projectId == env.DOKPLOY_PROJECT_ID) |
            .environments[]? | select(.environmentId == env.DOKPLOY_ENVIRONMENT_ID) |
            .applications[]? | select(.name == $name) | .applicationId
          ' | head -n1)

          if [ -n "$APP_ID" ] && [ "$APP_ID" != "null" ]; then
            echo "Deleting application: ${APP_ID}"

            curl -s -X 'POST' \
              "${DOKPLOY_URL}/api/trpc/application.delete" \
              -H 'accept: application/json' \
              -H 'Content-Type: application/json' \
              -H "x-api-key: ${DOKPLOY_API_KEY}" \
              -d "{\"json\": {\"applicationId\": \"${APP_ID}\"}}"

            echo "Application deleted successfully"
          else
            echo "Application not found, nothing to delete"
          fi
```

---

## Dokploy Configuration

### Setting Up Dokploy

1. **Create a Project** in Dokploy for your games
2. **Create an Environment** (e.g., "production" or "preview")
3. **Set up GitHub Integration**:
   - Go to Settings > Git Providers > GitHub
   - Follow the OAuth flow to connect your GitHub account
   - Note the GitHub Integration ID

4. **Generate an API Key**:
   - Go to Settings > API Keys
   - Create a new key with appropriate permissions
   - Save this as `DOKPLOY_API_KEY` in GitHub Secrets

5. **Note your IDs**:
   - Project ID: Found in the URL when viewing the project
   - Environment ID: Found in environment settings
   - Server ID: Found in server settings

### Domain Configuration

The workflow creates domains with this pattern:
```
https://your-domain.com/{owner}/{repo}/{branch}/
```

For example:
```
https://games.example.com/myuser/my-game/main/
```

Make sure:
1. Your domain has a wildcard DNS record pointing to Dokploy
2. You have Let's Encrypt or another certificate configured

---

## Common Issues & Solutions

### 1. Audio Issues

**Problem:** Audio sounds choppy or doesn't loop properly.

**Solutions:**
- Enable cross-origin isolation headers (see nginx.conf above)
- Load audio as "static" type in your game
- If issues persist, use the `-c` (compatibility) flag in love.js, but expect degraded audio

### 2. `goto` Statement Errors

**Problem:** Build fails with Lua syntax errors about `goto`.

**Solution:** love.js uses Lua 5.1 which doesn't support `goto`. Refactor your code:

```lua
-- Instead of:
::continue::
-- Use break or restructure your loops
```

### 3. Shader Compilation Errors

**Problem:** Shaders that work on desktop fail in the browser.

**Solution:** OpenGL ES is stricter. Ensure explicit type conversions:

```glsl
// Wrong (implicit conversion)
float result = someInt / 2;

// Correct (explicit conversion)
float result = float(someInt) / 2.0;
```

### 4. Memory Errors

**Problem:** Game crashes with out-of-memory errors.

**Solution:** Increase memory in the Dockerfile:

```dockerfile
ARG GAME_MEMORY=67108864  # 64MB
# or
ARG GAME_MEMORY=134217728  # 128MB
```

### 5. `t.version` Mismatch

**Problem:** love.js refuses to run due to version mismatch.

**Solution:** The Dockerfile automatically comments out `t.version` in conf.lua. If you still have issues, set it to match love.js:

```lua
t.version = "11.5"  -- or remove this line entirely
```

### 6. LuaJIT-Specific Features

**Problem:** Code using FFI or bitops doesn't work.

**Solution:** love.js uses Lua 5.1, not LuaJIT. Remove or replace these features:

```lua
-- Instead of LuaJIT bit operations:
local bit = require("bit")
local result = bit.band(a, b)

-- Use Lua 5.1 compatible alternatives or avoid bitwise operations
```

### 7. String Formatting with Booleans

**Problem:** `string.format()` crashes with boolean values.

**Solution:** Explicitly convert to string:

```lua
-- Wrong in Lua 5.1:
string.format("Value: %s", someBool)

-- Correct:
string.format("Value: %s", tostring(someBool))
```

---

## Testing Locally

Before deploying, test your build locally:

```bash
# Build the Docker image
docker build --tag my-love2d-game .

# Run it
docker run --publish 8080:80 --detach --name game my-love2d-game

# Open http://localhost:8080 in your browser

# Cleanup
docker stop game && docker rm game
```

---

## Sources & References

### Primary Resources
- [Davidobot/love.js](https://github.com/Davidobot/love.js) - The actively maintained fork of love.js for LOVE 11.5
- [Building love2d games for the web with love.js and Docker](https://kalis.me/building-love2d-games-web-docker/) - Excellent tutorial on the Docker build process
- [Dokploy Documentation](https://docs.dokploy.com/) - Official Dokploy docs

### Love2D Resources
- [LOVE 2D Official](https://love2d.org/) - Official LOVE 2D website
- [LOVE Wiki - Game Distribution](https://www.love2d.org/wiki/Game_Distribution) - Distribution options
- [awesome-love2d](https://github.com/love2d-community/awesome-love2d) - Curated list of LOVE libraries

### Technical References
- [Cross-Origin Isolation Guide](https://web.dev/articles/cross-origin-isolation-guide) - Required headers for SharedArrayBuffer
- [How I Learned to love.js Again](https://pagefault.se/post/how-i-learned-to-love-js-again/) - Practical tips for love.js compatibility
- [LÖVE Web Builder](https://schellingb.github.io/LoveWebBuilder/) - Alternative online tool for quick testing

### Alternative Tools
- [rozenmad/love-web-builder](https://github.com/rozenmad/love-web-builder) - LÖVE 12.0 web builder (experimental)
- [2dengine/love.js](https://github.com/2dengine/love.js) - Alternative frontend for love.js
- [LoveJS Player](https://alexjgriffith.itch.io/lovejs-player) - Interactive player with WebSocket support

---

## Summary

This guide showed you how to:

1. **Structure your repository** for a Love2D game with web deployment
2. **Create a Dockerfile** that uses love.js to compile your game and nginx to serve it
3. **Configure nginx** with the required headers for cross-origin isolation
4. **Set up GitHub Actions** to automatically deploy to Dokploy
5. **Handle common issues** when porting Love2D games to the web

The key insight from the original website deployment workflow is that Dokploy handles the heavy lifting of:
- Pulling code from GitHub
- Building Docker images
- Managing deployments
- Handling SSL certificates
- Creating preview URLs for branches

By combining love.js (for compilation), nginx (for serving with proper headers), and Dokploy (for orchestration), you get a robust CI/CD pipeline for your Love2D games!

Happy game development! :)
