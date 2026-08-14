# FA Diagnosis System — Frontend (offline)
# Skip Node build on the target host: copy pre-built dist/ into nginx.
# Build dist/ on an internet machine: npm ci && npm run build
# (see deploy/offline-prep.sh)

FROM nginx:1.27-alpine

COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY dist /usr/share/nginx/html

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
