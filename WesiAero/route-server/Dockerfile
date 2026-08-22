FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
USER node
ENV WESI_AERO_ROUTE_CONFIG=/config/config.json
EXPOSE 8792
CMD ["node", "src/index.mjs"]
