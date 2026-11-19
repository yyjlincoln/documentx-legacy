# Stage 1: Build Vue.js frontend
FROM node:22-alpine AS frontend-build
WORKDIR /build
# The DocumentX-NG-UI submodule ships no npm lockfile; ours is kept in frontend/.
COPY DocumentX-NG-UI/package.json ./
COPY frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY DocumentX-NG-UI/ .
RUN npm run build
# Output: /build/dist/

# Stage 2: Backend source with local compatibility patches applied
FROM python:3.12-slim AS backend-src
RUN apt-get update && \
    apt-get install -y --no-install-recommends patch && \
    rm -rf /var/lib/apt/lists/*
COPY DocumentX-NG/ /src/
COPY patches/DocumentX-NG/ /patches/
RUN cd /src && \
    for p in /patches/*.patch; do patch -p1 --forward --batch < "$p" || exit 1; done

# Stage 3: Python backend + nginx + supervisord
FROM python:3.12-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends nginx supervisor curl && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --system --gid 10001 documentx && \
    useradd --system --uid 10001 --gid documentx --no-create-home \
        --home-dir /nonexistent --shell /usr/sbin/nologin documentx

# Install Python dependencies
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir --root-user-action=ignore -r /app/requirements.txt

# Copy frontend build artifacts
COPY --from=frontend-build /build/dist /app/frontend/dist

# Copy backend source
COPY --from=backend-src /src/ /app/backend/

# Writable paths for the unprivileged user: cache directory, the secrets.json
# written by the entrypoint, and nginx's temp/log directories.
RUN mkdir -p /etc/documentx && \
    touch /app/backend/secrets.json && \
    chmod 600 /app/backend/secrets.json && \
    chown documentx:documentx /etc/documentx /app/backend/secrets.json && \
    chown -R documentx:documentx /var/lib/nginx /var/log/nginx

# Nginx config
RUN rm -f /etc/nginx/sites-enabled/default
COPY nginx-main.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/documentx.conf

# Supervisord config
COPY supervisord.conf /etc/supervisor/conf.d/documentx.conf

# Entrypoint to decode SECRETS_JSON env var
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app/backend

USER documentx

# Port 80 binds without root because Docker (>= 20.10) sets
# net.ipv4.ip_unprivileged_port_start=0 in container network namespaces.
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/documentx.conf"]
