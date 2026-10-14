# Interface web Flutter de Sylla Transit ERP (déployée sur erp.stt-ml.com via Coolify)

FROM ghcr.io/cirruslabs/flutter:3.41.3 AS build
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
