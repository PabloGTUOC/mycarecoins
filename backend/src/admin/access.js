/**
 * Cloudflare Access check for the operator console (docs/management-platform-plan.md §2.2).
 *
 * Cloudflare Access sits in front of admin.mycarecoins.app and adds a signed
 * token to every request it lets through (Cf-Access-Jwt-Assertion). Checking
 * it here means a request that reached this container some other way is
 * still refused. The signing keys rotate, so they are fetched from the team's
 * certs endpoint and cached by jose.
 */
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { sendError } from '../utils/httpError.js';

// `keys` replaces the remote key set in tests.
export function createAccessVerifier({ teamDomain, audience, keys }) {
  const issuer = teamDomain.replace(/\/+$/, '');
  const jwks = keys ?? createRemoteJWKSet(new URL(`${issuer}/cdn-cgi/access/certs`));
  return async (token) => {
    const { payload } = await jwtVerify(token, jwks, { issuer, audience });
    return payload;
  };
}

/**
 * The verifier for this process, from CF_ACCESS_TEAM_DOMAIN and CF_ACCESS_AUD.
 * Production refuses to start without them; elsewhere the check is skipped,
 * so the console can run locally.
 */
export function accessVerifierFromEnv(env = process.env) {
  const teamDomain = env.CF_ACCESS_TEAM_DOMAIN;
  const audience = env.CF_ACCESS_AUD;
  if (teamDomain && audience) return createAccessVerifier({ teamDomain, audience });
  if (env.NODE_ENV === 'production') {
    throw new Error('CF_ACCESS_TEAM_DOMAIN and CF_ACCESS_AUD must be set in production.');
  }
  return null;
}

export function requireAccess(verify) {
  return async (req, res, next) => {
    if (!verify) return next();
    const token = req.headers['cf-access-jwt-assertion'];
    if (!token) return sendError(res, 403, 'accessMissing', 'Missing Cloudflare Access token.');
    try {
      const payload = await verify(token);
      req.access = { email: payload.email ?? null, sub: payload.sub ?? null };
      return next();
    } catch {
      return sendError(res, 403, 'accessInvalid', 'Invalid Cloudflare Access token.');
    }
  };
}
