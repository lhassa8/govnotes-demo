import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { unauthorized } from '../lib/errors.js';

export const signAccessToken = (user) =>
  jwt.sign(
    { sub: user.id, email: user.email },
    config.jwt.signingKey,
    {
      algorithm: 'HS256',
      expiresIn: config.jwt.accessTtlSeconds,
      issuer: config.jwt.issuer,
    },
  );

export const verifyAccessToken = (token) => {
  try {
    return jwt.verify(token, config.jwt.signingKey, {
      algorithms: ['HS256'],
      issuer: config.jwt.issuer,
    });
  } catch {
    throw unauthorized('invalid or expired token');
  }
};
