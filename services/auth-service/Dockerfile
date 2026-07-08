FROM node:20-alpine
WORKDIR /usr/src/app
COPY package*.json ./
# bcrypt is a native addon with no musl/alpine prebuilt binary, so it must be
# compiled. libstdc++ is needed at runtime by the compiled addon and stays
# installed; the compiler toolchain is a virtual package dropped in the same
# layer to keep the runtime image lean.
RUN apk add --no-cache libstdc++ \
    && apk add --no-cache --virtual .build-deps python3 make g++ \
    && npm install \
    && apk del .build-deps
COPY . .
CMD ["node", "index.js"]
