# Build the CareCoins operator console Flutter web app. Firebase web config is compiled in via
# lib/firebase_options.dart, so no build args are needed.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
# Empty API_BASE = same-origin requests; nginx below proxies /admin-api
# to the admin-api container.
# --no-web-resources-cdn embeds CanvasKit and web fonts inside the container
# so they are served locally from nginx without external CDN dependencies.
RUN flutter build web --release --dart-define=API_BASE= --no-web-resources-cdn

FROM nginx:1.27-alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
