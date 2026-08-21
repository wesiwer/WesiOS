FROM node:24-bookworm-slim

WORKDIR /app
COPY package.json ./
COPY src ./src

RUN mkdir -p /data /profiles && chown -R node:node /data /profiles /app

USER node
ENV WESI_AERO_HOST=0.0.0.0
ENV WESI_AERO_PORT=8790
ENV WESI_AERO_DATABASE=/data/wesi-aero.db
ENV WESI_AERO_PROFILE_DIR=/profiles
EXPOSE 8790

CMD ["node", "src/index.mjs"]
