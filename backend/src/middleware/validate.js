/**
 * Lightweight request validation middleware. No external dependencies.
 *
 * Usage:
 *   router.post('/', validateBody({ title: [required(), string(1, 100)] }), handler)
 *   router.get('/:id', validateParams('id'), handler)
 */

// ─── Rule builders ────────────────────────────────────────────────────────────

export const required = () => (v) =>
  v === undefined || v === null || v === '' ? 'is required' : null;

export const string = (min = 1, max = 255) => (v) => {
  if (v === undefined || v === null) return null; // presence handled by required()
  if (typeof v !== 'string') return 'must be a string';
  const len = v.trim().length;
  if (len < min) return `must be at least ${min} character(s)`;
  if (len > max) return `must be at most ${max} characters`;
  return null;
};

export const positiveInt = () => (v) => {
  if (v === undefined || v === null) return null;
  const n = Number(v);
  if (!Number.isInteger(n) || n <= 0) return 'must be a positive integer';
  return null;
};

export const email = () => (v) => {
  if (!v) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(v))
    ? null
    : 'must be a valid email address';
};

export const isoDate = () => (v) => {
  if (!v) return null;
  return isNaN(new Date(v).getTime()) ? 'must be a valid date/time string' : null;
};

export const oneOf = (values) => (v) => {
  if (v === undefined || v === null) return null; // presence handled by required()
  return values.includes(v) ? null : `must be one of: ${values.join(', ')}`;
};

// ─── Middleware factories ─────────────────────────────────────────────────────

import { sendError } from '../utils/httpError.js';

/**
 * Validates req.body fields against an array of rule functions.
 * Returns 400 with the first failing rule's message.
 */
export function validateBody(schema) {
  return (req, res, next) => {
    for (const [field, rules] of Object.entries(schema)) {
      const value = req.body[field];
      for (const rule of rules) {
        const err = rule(value);
        if (err) return sendError(res, 400, 'invalidInput', `${field}: ${err}`, { field });
      }
    }
    next();
  };
}

/**
 * Validates that the named route params are positive integers.
 * Returns 400 if any param fails.
 */
export function validateParams(...paramNames) {
  return (req, res, next) => {
    for (const name of paramNames) {
      const n = Number(req.params[name]);
      if (!Number.isInteger(n) || n <= 0) {
        return sendError(res, 400, 'invalidInput', `${name}: must be a positive integer`, { field: name });
      }
    }
    next();
  };
}
