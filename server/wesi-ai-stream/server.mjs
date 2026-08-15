import http from 'node:http';
import {createGateway} from './gateway.mjs';

const host = process.env.WESI_STREAM_HOST || '127.0.0.1';
const port = Number(process.env.WESI_STREAM_PORT || 8792);

let handler;
try {
  handler = createGateway();
} catch (error) {
  console.error('Wesi AI stream gateway configuration error:', error?.message || error);
  process.exit(1);
}

http.createServer(handler).listen(port, host, () => {
  console.log(`Wesi AI stream gateway listening on ${host}:${port}`);
});
