FROM node:20-alpine
WORKDIR /usr/src/app
COPY package*.json ./
# bcrypt is a native addon with no musl/alpine prebuilt binary, so it must be
# compiled. Pull in the build toolchain as a virtual package and drop it in the
# same layer to keep the runtime image lean.
RUN apk add --no-cache --virtual .build-deps python3 make g++ \
    && npm install \
    && apk del .build-deps
COPY . .
CMD ["node", "index.js"]
