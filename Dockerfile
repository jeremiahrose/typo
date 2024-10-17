FROM node:22-bookworm

WORKDIR /usr/src/app

RUN apt-get update && apt-get install -y zsh jq fzf fd-find

RUN --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    --mount=type=cache,target=/root/.npm \
    npm ci

# Set up test data
RUN mkdir /home/node/MovieFolder

USER node
COPY . .
