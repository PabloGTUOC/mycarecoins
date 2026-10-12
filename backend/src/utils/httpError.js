/** A service-level refusal. `key` is the stable code the app translates;
 *  `message` is the English text; `params` fills the placeholders. */
export function serviceError(status, key, message, params) {
  return { error: { code: status, key, message, ...(params ? { params } : {}) } };
}

/** Sends a service refusal as { error, code, params }. */
export function sendServiceError(res, err) {
  const body = { error: err.message };
  if (err.key) body.code = err.key;
  if (err.params) body.params = err.params;
  return res.status(err.code).json(body);
}

/** Sends a route-level refusal as { error, code, params }. */
export function sendError(res, status, key, message, params) {
  const body = { error: message, code: key };
  if (params) body.params = params;
  return res.status(status).json(body);
}

