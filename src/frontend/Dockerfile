FROM node:12.13-alpine as build-deps
WORKDIR /frontend-app/
COPY package.json yarn.lock ./
RUN yarn install
COPY js ./js
RUN yarn run build
