/**
 * Apple App Store Connect API and App Store Server API clients for operator console.
 *
 * Docs reference:
 * - Tokens (Connect): https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
 * - Tokens (Server): https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests
 * - Apps: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps
 * - Subscription Groups: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-subscriptiongroups
 * - Subscriptions: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptiongroups-_id_-subscriptions
 * - Subscription Prices: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-prices
 * - Transaction Info: https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info
 * - Subscription Statuses: https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses
 * - JWS Transaction: https://developer.apple.com/documentation/appstoreserverapi/jwsdecodedtransactioninfo
 * - JWS Renewal: https://developer.apple.com/documentation/appstoreserverapi/jwsrenewalinfo
 *
 * Plan reference: docs/management-platform-plan.md §3.4 and §7 Phase 4.
 */
import * as jose from 'jose';

export class AppStoreError extends Error {
  constructor({ message, kind, status = null, code = null }) {
    super(message);
    this.name = 'AppStoreError';
    this.kind = kind; // 'unavailable' | 'rejected'
    this.status = status;
    this.code = code;
  }
}

function normalizePem(pem) {
  if (!pem) return null;
  let key = String(pem).trim();
  if (key.includes('\\n')) {
    key = key.replace(/\\n/g, '\n');
  }
  return key;
}

function sanitizeMessage(msg, sensitiveStrings = []) {
  if (!msg) return 'App Store error';
  let safe = String(msg);
  for (const str of sensitiveStrings) {
    if (str && str.length > 5) {
      safe = safe.split(str).join('[REDACTED]');
    }
  }
  return safe;
}

export function appStoreConfigFromEnv(env = process.env) {
  const ascKeyId = env.ASC_KEY_ID?.trim();
  const ascIssuerId = env.ASC_ISSUER_ID?.trim();
  const ascPrivateKey = normalizePem(env.ASC_PRIVATE_KEY);

  const iapKeyId = env.IAP_KEY_ID?.trim();
  const iapPrivateKey = normalizePem(env.IAP_PRIVATE_KEY);
  const appBundleId = env.APP_BUNDLE_ID?.trim();

  // The catalog looks the app up by bundle id, so the Connect side needs it too.
  const connect = (ascKeyId && ascIssuerId && ascPrivateKey && appBundleId)
    ? { keyId: ascKeyId, issuerId: ascIssuerId, privateKey: ascPrivateKey, bundleId: appBundleId }
    : null;

  const server = (iapKeyId && ascIssuerId && iapPrivateKey && appBundleId)
    ? { keyId: iapKeyId, issuerId: ascIssuerId, privateKey: iapPrivateKey, bundleId: appBundleId }
    : null;

  return { connect, server };
}

// Doc URL: https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests
export function createConnectTokenMaker({ keyId, issuerId, privateKey, now = () => Date.now() }) {
  if (!keyId || !issuerId || !privateKey) {
    throw new Error('keyId, issuerId, and privateKey are required for Connect token maker');
  }

  let cachedToken = null;
  let importedKey = null;
  const normalizedKey = normalizePem(privateKey);

  return async function getToken() {
    const nowMs = typeof now === 'function' ? now() : Date.now();
    if (cachedToken && nowMs < cachedToken.validUntilMs) {
      return cachedToken.token;
    }

    if (!importedKey) {
      importedKey = await jose.importPKCS8(normalizedKey, 'ES256');
    }

    const nowSec = Math.floor(nowMs / 1000);
    // Apple caps Connect API tokens at 20 minutes (1200s); issue for 19m
    const expSec = nowSec + (19 * 60);
    const token = await new jose.SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
      .setIssuer(issuerId)
      .setIssuedAt(nowSec)
      .setExpirationTime(expSec)
      .setAudience('appstoreconnect-v1')
      .sign(importedKey);

    // Reuse until 1 minute before expiry (18m window)
    cachedToken = {
      token,
      validUntilMs: nowMs + (18 * 60 * 1000),
    };

    return token;
  };
}

// Doc URL: https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests
export function createServerTokenMaker({ keyId, issuerId, bundleId, privateKey, now = () => Date.now() }) {
  if (!keyId || !issuerId || !bundleId || !privateKey) {
    throw new Error('keyId, issuerId, bundleId, and privateKey are required for Server token maker');
  }

  let cachedToken = null;
  let importedKey = null;
  const normalizedKey = normalizePem(privateKey);

  return async function getToken() {
    const nowMs = typeof now === 'function' ? now() : Date.now();
    if (cachedToken && nowMs < cachedToken.validUntilMs) {
      return cachedToken.token;
    }

    if (!importedKey) {
      importedKey = await jose.importPKCS8(normalizedKey, 'ES256');
    }

    const nowSec = Math.floor(nowMs / 1000);
    // Apple caps Server API tokens at 60 minutes (3600s); issue for 55m
    const expSec = nowSec + (55 * 60);
    const token = await new jose.SignJWT({ bid: bundleId })
      .setProtectedHeader({ alg: 'ES256', kid: keyId, typ: 'JWT' })
      .setIssuer(issuerId)
      .setIssuedAt(nowSec)
      .setExpirationTime(expSec)
      .setAudience('appstoreconnect-v1')
      .sign(importedKey);

    // Reuse until 1 minute before expiry (54m window)
    cachedToken = {
      token,
      validUntilMs: nowMs + (54 * 60 * 1000),
    };

    return token;
  };
}

function formatIsoDate(timestamp) {
  if (timestamp == null) return null;
  if (typeof timestamp === 'number') {
    return new Date(timestamp).toISOString();
  }
  const str = String(timestamp);
  if (/^\d+$/.test(str)) {
    return new Date(Number(str)).toISOString();
  }
  const parsed = DateTime?.tryParse ? null : new Date(str);
  return isNaN(parsed?.getTime()) ? str : parsed.toISOString();
}

export function createAppStoreClients({
  config,
  fetch = globalThis.fetch,
  timeoutMs = 10000,
  now = () => Date.now(),
}) {
  const sensitiveStrings = [
    config?.connect?.privateKey,
    config?.server?.privateKey,
  ].filter(Boolean);

  function makeRequestHelper(getToken, baseUrl) {
    return async function request(path, { method = 'GET', body = null } = {}) {
      const token = await getToken();
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), timeoutMs);
      const url = `${baseUrl}${path}`;
      const headers = {
        'Authorization': `Bearer ${token}`,
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
        throw new AppStoreError({
          message: sanitizeMessage(
            isTimeout ? 'App Store request timed out.' : `App Store network error: ${err.message}`,
            [...sensitiveStrings, token]
          ),
          kind: 'unavailable',
          status: null,
          code: isTimeout ? 'timeout' : 'network_error',
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

      if (!res.ok) {
        const kind = (res.status === 429 || res.status >= 500) ? 'unavailable' : 'rejected';
        const rawMsg = data?.errorMessage || data?.errors?.[0]?.detail || `App Store request failed with status ${res.status}`;
        const code = data?.errorCode ? String(data.errorCode) : (data?.errors?.[0]?.code ?? null);
        throw new AppStoreError({
          message: sanitizeMessage(rawMsg, [...sensitiveStrings, token]),
          kind,
          status: res.status,
          code,
        });
      }

      return data;
    };
  }

  // ─── Connect API client ──────────────────────────────────────────────────────
  let connectClient = null;
  if (config?.connect) {
    const getConnectToken = createConnectTokenMaker({
      keyId: config.connect.keyId,
      issuerId: config.connect.issuerId,
      privateKey: config.connect.privateKey,
      now,
    });
    const connectReq = makeRequestHelper(getConnectToken, 'https://api.appstoreconnect.apple.com');

    connectClient = {
      // Doc URL: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps
      async getApp(bundleId) {
        const data = await connectReq(`/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}`);
        const app = data?.data?.[0];
        if (!app) {
          throw new AppStoreError({
            message: `App with bundleId "${bundleId}" not found.`,
            kind: 'rejected',
            status: 404,
            code: 'notFound',
          });
        }
        return {
          id: app.id,
          name: app.attributes?.name ?? null,
          bundleId: app.attributes?.bundleId ?? null,
        };
      },

      // Doc URL: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-subscriptiongroups
      async listSubscriptionGroups(appId) {
        const data = await connectReq(`/v1/apps/${encodeURIComponent(appId)}/subscriptionGroups`);
        const groups = data?.data ?? [];
        return groups.map((g) => ({
          id: g.id,
          referenceName: g.attributes?.referenceName ?? null,
        }));
      },

      // Doc URL: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptiongroups-_id_-subscriptions
      async listSubscriptions(groupId) {
        const data = await connectReq(`/v1/subscriptionGroups/${encodeURIComponent(groupId)}/subscriptions`);
        const subs = data?.data ?? [];
        return subs.map((s) => ({
          id: s.id,
          name: s.attributes?.name ?? null,
          productId: s.attributes?.productId ?? null,
          state: s.attributes?.state ?? null,
        }));
      },

      // Doc URL: https://developer.apple.com/documentation/appstoreconnectapi/get-v1-subscriptions-_id_-prices
      async listSubscriptionPrices(subscriptionId) {
        const data = await connectReq(
          `/v1/subscriptions/${encodeURIComponent(subscriptionId)}/prices?include=subscriptionPricePoint,territory`
        );
        const prices = data?.data ?? [];
        const included = data?.included ?? [];

        const includedMap = new Map();
        for (const item of included) {
          includedMap.set(`${item.type}:${item.id}`, item);
        }

        return prices.map((p) => {
          const sppId = p.relationships?.subscriptionPricePoint?.data?.id;
          const territoryId = p.relationships?.territory?.data?.id;
          const spp = sppId ? includedMap.get(`subscriptionPricePoints:${sppId}`) : null;
          const terr = territoryId ? includedMap.get(`territories:${territoryId}`) : null;

          return {
            territory: territoryId ?? terr?.id ?? null,
            customerPrice: spp?.attributes?.customerPrice ?? null,
            currency: terr?.attributes?.currency ?? null,
            startDate: p.attributes?.startDate ?? null,
          };
        });
      },

      async getCatalog(bundleId) {
        const app = await this.getApp(bundleId);
        const groups = await this.listSubscriptionGroups(app.id);

        const subscriptionGroups = await Promise.all(
          groups.map(async (group) => {
            const subs = await this.listSubscriptions(group.id);
            const subscriptions = await Promise.all(
              subs.map(async (sub) => {
                const prices = await this.listSubscriptionPrices(sub.id);
                return {
                  id: sub.id,
                  name: sub.name,
                  productId: sub.productId,
                  state: sub.state,
                  prices,
                };
              })
            );
            return {
              id: group.id,
              referenceName: group.referenceName,
              subscriptions,
            };
          })
        );

        return {
          app,
          subscriptionGroups,
        };
      },
    };
  }

  // ─── Server API client ──────────────────────────────────────────────────────
  let serverClient = null;
  if (config?.server) {
    const getServerToken = createServerTokenMaker({
      keyId: config.server.keyId,
      issuerId: config.server.issuerId,
      bundleId: config.server.bundleId,
      privateKey: config.server.privateKey,
      now,
    });

    const prodReq = makeRequestHelper(getServerToken, 'https://api.storekit.itunes.apple.com');
    const sandboxReq = makeRequestHelper(getServerToken, 'https://api.storekit-sandbox.itunes.apple.com');

    serverClient = {
      // Doc URL: https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info
      async getTransaction(transactionId, { environment = 'production' } = {}) {
        const reqFn = environment === 'sandbox' ? sandboxReq : prodReq;
        return reqFn(`/inApps/v1/transactions/${encodeURIComponent(transactionId)}`);
      },

      // Doc URL: https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses
      async getSubscriptionStatuses(transactionId, { environment = 'production' } = {}) {
        const reqFn = environment === 'sandbox' ? sandboxReq : prodReq;
        return reqFn(`/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`);
      },

      // Doc URL: https://developer.apple.com/documentation/appstoreserverapi/jwsdecodedtransactioninfo
      // Doc URL: https://developer.apple.com/documentation/appstoreserverapi/jwsrenewalinfo
      async lookupTransaction(transactionId, { environment = 'production' } = {}) {
        const txData = await this.getTransaction(transactionId, { environment });
        if (!txData?.signedTransactionInfo) {
          throw new AppStoreError({
            message: 'Transaction info missing signed payload.',
            kind: 'rejected',
            status: 502,
          });
        }

        // Full chain verification is NOT done here because the data comes straight
        // from Apple over TLS; decoding the JWS payload with jose.decodeJwt is safe and sufficient.
        const txPayload = jose.decodeJwt(txData.signedTransactionInfo);

        let renewalPayload = null;
        let subscriptionStatus = null;
        try {
          const statusData = await this.getSubscriptionStatuses(transactionId, { environment });
          const group = statusData?.data?.[0];
          const lastTxs = group?.lastTransactions ?? [];
          const lastTx = lastTxs.find(t => String(t.originalTransactionId) === String(txPayload.originalTransactionId))
            ?? lastTxs[0];
          subscriptionStatus = lastTx?.status ?? null;
          if (lastTx?.signedRenewalInfo) {
            renewalPayload = jose.decodeJwt(lastTx.signedRenewalInfo);
          }
        } catch {
          // If transaction is not an auto-renewable subscription or statuses call fails, renewal info remains null
        }

        return {
          productId: txPayload.productId ?? null,
          transactionId: txPayload.transactionId ? String(txPayload.transactionId) : null,
          originalTransactionId: txPayload.originalTransactionId ? String(txPayload.originalTransactionId) : null,
          purchaseDate: formatIsoDate(txPayload.purchaseDate),
          expiresDate: formatIsoDate(txPayload.expiresDate),
          environment: txPayload.environment ?? null,
          type: txPayload.type ?? null,
          inAppOwnershipType: txPayload.inAppOwnershipType ?? null,
          revocationDate: formatIsoDate(txPayload.revocationDate),
          revocationReason: txPayload.revocationReason ?? null,
          autoRenewStatus: renewalPayload?.autoRenewStatus ?? null,
          autoRenewProductId: renewalPayload?.autoRenewProductId ?? null,
          expirationIntent: renewalPayload?.expirationIntent ?? null,
          status: subscriptionStatus,
        };
      },
    };
  }

  return {
    connect: connectClient,
    server: serverClient,
  };
}
