/**
 * RevenueCat REST API v2 client for operator console free-plan mirroring.
 *
 * Docs reference: https://www.revenuecat.com/docs/api-v2/customer
 * Plan reference: docs/management-platform-plan.md §4 and §7 Phase 3.
 */

export class RevenueCatError extends Error {
  constructor({ message, kind, status = null, type = null }) {
    super(message);
    this.name = 'RevenueCatError';
    this.kind = kind; // 'unavailable' | 'rejected'
    this.status = status;
    this.type = type;
  }
}

function sanitizeMessage(msg, apiKey) {
  if (!msg) return 'RevenueCat error';
  let safe = String(msg);
  if (apiKey) {
    safe = safe.split(apiKey).join('[REDACTED]');
  }
  return safe;
}

export function revenueCatConfigFromEnv(env = process.env) {
  const apiKey = env.RC_SECRET_API_KEY?.trim();
  const projectId = env.RC_PROJECT_ID?.trim();
  const entitlementId = env.RC_ENTITLEMENT_ID?.trim();

  if (!apiKey || !projectId || !entitlementId) {
    return null;
  }
  return { apiKey, projectId, entitlementId };
}

export function createRevenueCatClient({
  apiKey,
  projectId,
  fetch = globalThis.fetch,
  timeoutMs = 10000,
}) {
  if (!apiKey) throw new Error('RevenueCat apiKey is required');
  if (!projectId) throw new Error('RevenueCat projectId is required');

  const baseUrl = 'https://api.revenuecat.com/v2';

  async function request(path, { method = 'GET', body = null } = {}) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
    const url = `${baseUrl}${path}`;
    const headers = {
      'Authorization': `Bearer ${apiKey}`,
      'Accept': 'application/json',
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    let res;
    try {
      res = await fetch(url, {
        method,
        headers,
        body: body != null ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      });
    } catch (err) {
      clearTimeout(timeoutId);
      const isTimeout = err.name === 'AbortError' || controller.signal.aborted;
      throw new RevenueCatError({
        message: sanitizeMessage(
          isTimeout ? 'RevenueCat request timed out.' : `RevenueCat network error: ${err.message}`,
          apiKey
        ),
        kind: 'unavailable',
        status: null,
        type: isTimeout ? 'timeout' : 'network_error',
      });
    } finally {
      clearTimeout(timeoutId);
    }

    let data = null;
    const text = await res.text().catch(() => '');
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = { raw: text };
      }
    }

    return { res, data };
  }

  function raiseError(res, data) {
    const kind = (res.status === 429 || res.status >= 500) ? 'unavailable' : 'rejected';
    const type = data?.type || data?.code || null;
    const rawMsg = data?.message || `RevenueCat request failed with status ${res.status}`;
    throw new RevenueCatError({
      message: sanitizeMessage(rawMsg, apiKey),
      kind,
      status: res.status,
      type,
    });
  }

  return {
    // Doc URL: https://www.revenuecat.com/docs/api-v2/customer
    async ensureCustomer(customerId, attributes = null) {
      const { res, data } = await request(`/projects/${projectId}/customers`, {
        method: 'POST',
        body: {
          id: customerId,
          ...(attributes ? { attributes } : {}),
        },
      });

      if (res.ok) {
        return data;
      }

      // 409 Conflict: customer already exists in RevenueCat.
      if (res.status === 409 || data?.type === 'resource_already_exists_error') {
        const hasAttrs = Array.isArray(attributes)
          ? attributes.length > 0
          : (attributes && Object.keys(attributes).length > 0);
        if (hasAttrs) {
          const attrRes = await request(
            `/projects/${projectId}/customers/${encodeURIComponent(customerId)}/attributes`,
            {
              method: 'POST',
              body: { attributes },
            }
          );
          if (!attrRes.res.ok) {
            raiseError(attrRes.res, attrRes.data);
          }
          return attrRes.data ?? { id: customerId, attributes };
        }
        return data ?? { id: customerId };
      }

      raiseError(res, data);
    },

    // Doc URL: https://www.revenuecat.com/docs/api-v2/customer
    async grantEntitlement(customerId, entitlementId, expiresAtMs) {
      const { res, data } = await request(
        `/projects/${projectId}/customers/${encodeURIComponent(customerId)}/actions/grant_entitlement`,
        {
          method: 'POST',
          body: {
            entitlement_id: entitlementId,
            expires_at: expiresAtMs,
          },
        }
      );

      if (!res.ok) {
        raiseError(res, data);
      }
      return data;
    },

    // Doc URL: https://www.revenuecat.com/docs/api-v2/customer
    async revokeGrantedEntitlement(customerId, entitlementId) {
      const { res, data } = await request(
        `/projects/${projectId}/customers/${encodeURIComponent(customerId)}/actions/revoke_granted_entitlement`,
        {
          method: 'POST',
          body: {
            entitlement_id: entitlementId,
          },
        }
      );

      if (!res.ok) {
        raiseError(res, data);
      }
      return data;
    },

    // Doc URL: https://www.revenuecat.com/docs/api-v2/customer
    async getCustomer(customerId) {
      const { res, data } = await request(
        `/projects/${projectId}/customers/${encodeURIComponent(customerId)}`,
        {
          method: 'GET',
        }
      );

      if (!res.ok) {
        raiseError(res, data);
      }
      return data;
    },

    // Doc URL: https://www.revenuecat.com/docs/api-v2/charts-and-metrics/metrics/get-metrics-overview
    async getMetricsOverview() {
      const { res, data } = await request(
        `/projects/${projectId}/metrics/overview`,
        {
          method: 'GET',
        }
      );

      if (!res.ok) {
        raiseError(res, data);
      }

      const rawMetrics = data?.metrics || data?.items || (Array.isArray(data) ? data : []);
      return rawMetrics.map((m) => ({
        id: m.id != null ? String(m.id) : null,
        name: m.name != null ? String(m.name) : null,
        value: m.value ?? null,
        unit: m.unit ?? data?.currency ?? null,
        period: m.period ?? m.period_label ?? null,
      }));
    },
  };
}
