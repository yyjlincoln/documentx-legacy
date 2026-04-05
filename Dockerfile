# Stage 1: Build Vue.js frontend
FROM node:16-alpine AS frontend-build
WORKDIR /build
COPY DocumentX-NG-UI/package.json DocumentX-NG-UI/package-lock.json* ./
RUN npm install
COPY DocumentX-NG-UI/ .
RUN npm run build
# Output: /build/dist/

# Stage 2: Python backend + nginx + supervisord
FROM python:3.10-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx supervisor curl && \
    rm -rf /var/lib/apt/lists/*

# Copy frontend build artifacts
COPY --from=frontend-build /build/dist /app/frontend/dist

# Copy backend source
COPY DocumentX-NG/ /app/backend/

# Install Python dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# Create cache directory
RUN mkdir -p /etc/documentx

# Nginx config
RUN rm -f /etc/nginx/sites-enabled/default
COPY nginx.conf /etc/nginx/conf.d/documentx.conf

# Supervisord config
COPY supervisord.conf /etc/supervisor/conf.d/documentx.conf

WORKDIR /app/backend

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://127.0.0.1:40000/getUIColorScheme || exit 1

CMD ["supervisord", "-c", "/etc/supervisor/conf.d/documentx.conf"]
