FROM node:14 AS build
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install
COPY . .
ARG REACT_APP_BACKEND_URL
ENV REACT_APP_BACKEND_URL=${REACT_APP_BACKEND_URL}
ARG REACT_APP_AUTH_URL
ENV REACT_APP_AUTH_URL=${REACT_APP_AUTH_URL}
ARG REACT_APP_NOTIFICATIONS_URL
ENV REACT_APP_NOTIFICATIONS_URL=${REACT_APP_NOTIFICATIONS_URL}
RUN set -e; \
    missing=""; \
    [ -z "$REACT_APP_BACKEND_URL" ] && missing="$missing REACT_APP_BACKEND_URL"; \
    [ -z "$REACT_APP_AUTH_URL" ] && missing="$missing REACT_APP_AUTH_URL"; \
    [ -z "$REACT_APP_NOTIFICATIONS_URL" ] && missing="$missing REACT_APP_NOTIFICATIONS_URL"; \
    if [ -n "$missing" ]; then \
      echo "ERROR: Missing required build-arg(s):$missing"; \
      echo "Usage: docker build --build-arg REACT_APP_BACKEND_URL=/api/tasks --build-arg REACT_APP_AUTH_URL=/api/auth --build-arg REACT_APP_NOTIFICATIONS_URL=/api/notifications ..."; \
      exit 1; \
    fi && \
    npm run build

FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /usr/src/app/build /usr/share/nginx/html
EXPOSE 3000
CMD ["nginx", "-g", "daemon off;"]
