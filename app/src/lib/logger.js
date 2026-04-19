import pino from 'pino';
import { config } from '../config.js';

export const logger = pino({
  level: config.logLevel,
  base: {
    service: 'govnotes-app',
    env: config.env,
  },
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      'password',
      'token',
      '*.password',
      '*.jwt',
    ],
    remove: true,
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});
