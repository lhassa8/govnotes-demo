import { verifyAccessToken } from './jwt.js';
import { unauthorized } from '../lib/errors.js';

export const requireAuth = (req, _res, next) => {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) {
    return next(unauthorized('missing bearer token'));
  }
  const token = header.slice('Bearer '.length).trim();
  if (!token) {
    return next(unauthorized('missing bearer token'));
  }

  try {
    const claims = verifyAccessToken(token);
    req.user = { id: claims.sub, email: claims.email };
    return next();
  } catch (err) {
    return next(err);
  }
};
