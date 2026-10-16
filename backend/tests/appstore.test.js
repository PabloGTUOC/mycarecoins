import { test, describe, before } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as jose from 'jose';
import {
  AppStoreError,
  appStoreConfigFromEnv,
  createConnectTokenMaker,
  createServerTokenMaker,
  createAppStoreClients,
} from '../src/admin/appstore.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function loadFixture(name) {
  const file = path.join(__dirname, 'fixtures', 'appstore', name);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function fakeFetch(handler) {
  const calls = [];
  const fn = async (url, options = {}) => {
    calls.push({ url, ...options });
    return handler(url, options);
  };
  fn._calls = calls;
  return fn;
}

const jsonResponse = (data, status = 200) => ({
  ok: status >= 200 && status < 300,
  status,
  async text() {
    return JSON.stringify(data);
  },
});

describe('App Store Tokens & Config', () => {
  let privateKeyPem;
  let publicKeyPem;
  let keyPair;

  before(async () => {
    keyPair = await jose.generateKeyPair('ES256', { extractable: true });
    privateKeyPem = await jose.exportPKCS8(keyPair.privateKey);
    publicKeyPem = await jose.exportSPKI(keyPair.publicKey);
  });

  test('appStoreConfigFromEnv parses connect and server config or returns null parts', () => {
    const fullEnv = {
      ASC_KEY_ID: 'asc_key_1',
      ASC_ISSUER_ID: 'issuer_guid_1',
      ASC_PRIVATE_KEY: privateKeyPem,
      IAP_KEY_ID: 'iap_key_1',
      IAP_PRIVATE_KEY: privateKeyPem,
      APP_BUNDLE_ID: 'app.mycarecoins',
    };
    const config = appStoreConfigFromEnv(fullEnv);
    assert.deepEqual(config, {
      connect: {
        keyId: 'asc_key_1',
        issuerId: 'issuer_guid_1',
        privateKey: privateKeyPem.trim(),
        bundleId: 'app.mycarecoins',
      },
      server: {
        keyId: 'iap_key_1',
        issuerId: 'issuer_guid_1',
        privateKey: privateKeyPem.trim(),
        bundleId: 'app.mycarecoins',
      },
    });

    const onlyConnect = appStoreConfigFromEnv({
      ASC_KEY_ID: 'k',
      ASC_ISSUER_ID: 'i',
      ASC_PRIVATE_KEY: privateKeyPem,
      APP_BUNDLE_ID: 'b',
    });
    assert.ok(onlyConnect.connect);
    // The catalog needs the bundle id, so Connect without it is off.
    assert.equal(appStoreConfigFromEnv({
      ASC_KEY_ID: 'k', ASC_ISSUER_ID: 'i', ASC_PRIVATE_KEY: privateKeyPem,
    }).connect, null);
    assert.equal(onlyConnect.server, null);

    const empty = appStoreConfigFromEnv({});
    assert.equal(empty.connect, null);
    assert.equal(empty.server, null);
  });

  test('Connect token maker: ES256, kid, claims, cap <= 20m, reuse window', async () => {
    let nowMs = 1700000000000;
    const now = () => nowMs;

    const getToken = createConnectTokenMaker({
      keyId: 'asc_key_test',
      issuerId: 'issuer_guid_test',
      privateKey: privateKeyPem,
      now,
    });

    const token1 = await getToken();
    const { payload, protectedHeader } = await jose.jwtVerify(token1, keyPair.publicKey, {
      currentDate: new Date(nowMs),
    });

    assert.equal(protectedHeader.alg, 'ES256');
    assert.equal(protectedHeader.kid, 'asc_key_test');
    assert.equal(protectedHeader.typ, 'JWT');
    assert.equal(payload.iss, 'issuer_guid_test');
    assert.equal(payload.aud, 'appstoreconnect-v1');
    assert.equal(payload.iat, Math.floor(nowMs / 1000));
    assert.equal(payload.exp, Math.floor(nowMs / 1000) + 19 * 60);

    // Lifetime is 19 minutes, well within Apple's 20-minute cap
    assert.ok(payload.exp - payload.iat <= 1200);

    // Reuse within 18 minutes
    nowMs += 10 * 60 * 1000;
    const token2 = await getToken();
    assert.equal(token2, token1);

    // Beyond 18 minutes (1 minute before expiry), generates a new token
    nowMs += 9 * 60 * 1000;
    const token3 = await getToken();
    assert.notEqual(token3, token1);
  });

  test('Server token maker: ES256, kid, bid claim, cap <= 60m, reuse window', async () => {
    let nowMs = 1700000000000;
    const now = () => nowMs;

    const getToken = createServerTokenMaker({
      keyId: 'iap_key_test',
      issuerId: 'issuer_guid_test',
      bundleId: 'app.mycarecoins',
      privateKey: privateKeyPem,
      now,
    });

    const token1 = await getToken();
    const { payload, protectedHeader } = await jose.jwtVerify(token1, keyPair.publicKey, {
      currentDate: new Date(nowMs),
    });

    assert.equal(protectedHeader.alg, 'ES256');
    assert.equal(protectedHeader.kid, 'iap_key_test');
    assert.equal(protectedHeader.typ, 'JWT');
    assert.equal(payload.iss, 'issuer_guid_test');
    assert.equal(payload.bid, 'app.mycarecoins');
    assert.equal(payload.aud, 'appstoreconnect-v1');
    assert.equal(payload.iat, Math.floor(nowMs / 1000));
    assert.equal(payload.exp, Math.floor(nowMs / 1000) + 55 * 60);

    // Lifetime is 55 minutes, within Apple's 60-minute cap
    assert.ok(payload.exp - payload.iat <= 3600);

    // Reuse within 54 minutes
    nowMs += 30 * 60 * 1000;
    const token2 = await getToken();
    assert.equal(token2, token1);

    // Beyond 54 minutes (1 minute before expiry), generates a new token
    nowMs += 25 * 60 * 1000;
    const token3 = await getToken();
    assert.notEqual(token3, token1);
  });

  test('never leaks private key or token in AppStoreError message', async () => {
    const fetch = fakeFetch(async () => jsonResponse({ errorMessage: `Failed with key ${privateKeyPem}` }, 400));
    const clients = createAppStoreClients({
      config: {
        connect: {
          keyId: 'k',
          issuerId: 'i',
          privateKey: privateKeyPem,
        },
      },
      fetch,
    });

    await assert.rejects(
      async () => clients.connect.getApp('app.mycarecoins'),
      (err) => {
        assert.ok(err instanceof AppStoreError);
        assert.ok(!err.message.includes(privateKeyPem));
        assert.ok(err.message.includes('[REDACTED]'));
        return true;
      }
    );
  });
});

describe('App Store Connect Client', () => {
  let privateKeyPem;

  before(async () => {
    const keyPair = await jose.generateKeyPair('ES256', { extractable: true });
    privateKeyPem = await jose.exportPKCS8(keyPair.privateKey);
  });

  test('getApp returns app details', async () => {
    const appFixture = loadFixture('app_response.json');
    const fetch = fakeFetch(async (url, opts) => {
      assert.equal(url, 'https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=app.mycarecoins');
      assert.equal(opts.method, 'GET');
      assert.ok(opts.headers.Authorization.startsWith('Bearer '));
      return jsonResponse(appFixture, 200);
    });

    const clients = createAppStoreClients({
      config: { connect: { keyId: 'k', issuerId: 'i', privateKey: privateKeyPem } },
      fetch,
    });

    const app = await clients.connect.getApp('app.mycarecoins');
    assert.deepEqual(app, {
      id: 'app_12345',
      name: 'MyCareCoins',
      bundleId: 'app.mycarecoins',
    });
  });

  test('listSubscriptionGroups returns subscription groups', async () => {
    const groupsFixture = loadFixture('subscription_groups.json');
    const fetch = fakeFetch(async (url) => {
      assert.equal(url, 'https://api.appstoreconnect.apple.com/v1/apps/app_12345/subscriptionGroups');
      return jsonResponse(groupsFixture, 200);
    });

    const clients = createAppStoreClients({
      config: { connect: { keyId: 'k', issuerId: 'i', privateKey: privateKeyPem } },
      fetch,
    });

    const groups = await clients.connect.listSubscriptionGroups('app_12345');
    assert.deepEqual(groups, [{ id: 'group_100', referenceName: 'MyCareCoins Pro Group' }]);
  });

  test('listSubscriptions returns subscriptions in group', async () => {
    const subsFixture = loadFixture('subscriptions.json');
    const fetch = fakeFetch(async (url) => {
      assert.equal(url, 'https://api.appstoreconnect.apple.com/v1/subscriptionGroups/group_100/subscriptions');
      return jsonResponse(subsFixture, 200);
    });

    const clients = createAppStoreClients({
      config: { connect: { keyId: 'k', issuerId: 'i', privateKey: privateKeyPem } },
      fetch,
    });

    const subs = await clients.connect.listSubscriptions('group_100');
    assert.equal(subs.length, 2);
    assert.deepEqual(subs[0], {
      id: 'sub_monthly',
      name: 'Pro Monthly',
      productId: 'pro_monthly',
      state: 'APPROVED',
    });
  });

  test('listSubscriptionPrices extracts territory, customerPrice, currency, and startDate', async () => {
    const pricesFixture = loadFixture('subscription_prices.json');
    const fetch = fakeFetch(async (url) => {
      assert.equal(
        url,
        'https://api.appstoreconnect.apple.com/v1/subscriptions/sub_monthly/prices?include=subscriptionPricePoint,territory'
      );
      return jsonResponse(pricesFixture, 200);
    });

    const clients = createAppStoreClients({
      config: { connect: { keyId: 'k', issuerId: 'i', privateKey: privateKeyPem } },
      fetch,
    });

    const prices = await clients.connect.listSubscriptionPrices('sub_monthly');
    assert.deepEqual(prices, [
      {
        territory: 'USA',
        customerPrice: '4.99',
        currency: 'USD',
        startDate: '2024-01-01',
      },
      {
        territory: 'EUR',
        customerPrice: '4.99',
        currency: 'EUR',
        startDate: '2024-01-01',
      },
    ]);
  });

  test('getCatalog chains app, groups, subscriptions, and prices', async () => {
    const appFixture = loadFixture('app_response.json');
    const groupsFixture = loadFixture('subscription_groups.json');
    const subsFixture = loadFixture('subscriptions.json');
    const pricesFixture = loadFixture('subscription_prices.json');

    const fetch = fakeFetch(async (url) => {
      if (url.includes('/prices')) return jsonResponse(pricesFixture, 200);
      if (url.includes('/subscriptions')) return jsonResponse(subsFixture, 200);
      if (url.includes('/subscriptionGroups')) return jsonResponse(groupsFixture, 200);
      if (url.includes('/v1/apps')) return jsonResponse(appFixture, 200);
      throw new Error(`Unexpected url: ${url}`);
    });

    const clients = createAppStoreClients({
      config: { connect: { keyId: 'k', issuerId: 'i', privateKey: privateKeyPem } },
      fetch,
    });

    const catalog = await clients.connect.getCatalog('app.mycarecoins');
    assert.equal(catalog.app.id, 'app_12345');
    assert.equal(catalog.subscriptionGroups.length, 1);
    assert.equal(catalog.subscriptionGroups[0].subscriptions.length, 2);
    assert.equal(catalog.subscriptionGroups[0].subscriptions[0].prices.length, 2);
  });
});

describe('App Store Server Client', () => {
  let privateKeyPem;
  let testSigningKey;

  before(async () => {
    const keyPair = await jose.generateKeyPair('ES256', { extractable: true });
    privateKeyPem = await jose.exportPKCS8(keyPair.privateKey);
    testSigningKey = keyPair.privateKey;
  });

  async function signJws(payload) {
    return new jose.SignJWT(payload)
      .setProtectedHeader({ alg: 'ES256' })
      .sign(testSigningKey);
  }

  test('lookupTransaction decodes JWS, extracts strictly allowed fields, omits appAccountToken', async () => {
    const signedTx = await signJws({
      productId: 'pro_monthly',
      transactionId: '1000000123456789',
      originalTransactionId: '1000000123456789',
      purchaseDate: 1700000000000,
      expiresDate: 1702592000000,
      environment: 'Production',
      type: 'Auto-Renewable Subscription',
      inAppOwnershipType: 'PURCHASED',
      revocationDate: null,
      revocationReason: null,
      appAccountToken: 'FORBIDDEN_USER_IDENTIFIER_UUID',
      otherPrivateField: 'secret_info',
    });

    const signedRenewal = await signJws({
      autoRenewStatus: 1,
      autoRenewProductId: 'pro_monthly',
      expirationIntent: null,
      userSecretInfo: 'should_not_leak',
    });

    const fetch = fakeFetch(async (url) => {
      if (url.includes('/inApps/v1/transactions/1000000123456789')) {
        return jsonResponse({ signedTransactionInfo: signedTx }, 200);
      }
      if (url.includes('/inApps/v1/subscriptions/1000000123456789')) {
        return jsonResponse({
          environment: 'Production',
          bundleId: 'app.mycarecoins',
          data: [
            {
              subscriptionGroupIdentifier: 'group_100',
              lastTransactions: [
                {
                  originalTransactionId: '1000000123456789',
                  status: 1,
                  signedTransactionInfo: signedTx,
                  signedRenewalInfo: signedRenewal,
                },
              ],
            },
          ],
        }, 200);
      }
      throw new Error(`Unexpected url: ${url}`);
    });

    const clients = createAppStoreClients({
      config: {
        server: {
          keyId: 'k',
          issuerId: 'i',
          bundleId: 'app.mycarecoins',
          privateKey: privateKeyPem,
        },
      },
      fetch,
    });

    const result = await clients.server.lookupTransaction('1000000123456789');

    // Strict allowed fields check
    assert.deepEqual(result, {
      productId: 'pro_monthly',
      transactionId: '1000000123456789',
      originalTransactionId: '1000000123456789',
      purchaseDate: new Date(1700000000000).toISOString(),
      expiresDate: new Date(1702592000000).toISOString(),
      environment: 'Production',
      type: 'Auto-Renewable Subscription',
      inAppOwnershipType: 'PURCHASED',
      revocationDate: null,
      revocationReason: null,
      autoRenewStatus: 1,
      autoRenewProductId: 'pro_monthly',
      expirationIntent: null,
      status: 1,
    });

    // Verification of forbidden fields
    assert.equal(result.appAccountToken, undefined);
    assert.equal(result.otherPrivateField, undefined);
    assert.equal(result.userSecretInfo, undefined);
  });

  test('lookupTransaction targets sandbox endpoint when environment is sandbox', async () => {
    const signedTx = await signJws({
      productId: 'pro_monthly',
      transactionId: '2000000999',
    });

    const fetch = fakeFetch(async (url) => {
      assert.ok(url.startsWith('https://api.storekit-sandbox.itunes.apple.com'));
      return jsonResponse({ signedTransactionInfo: signedTx }, 200);
    });

    const clients = createAppStoreClients({
      config: {
        server: {
          keyId: 'k',
          issuerId: 'i',
          bundleId: 'app.mycarecoins',
          privateKey: privateKeyPem,
        },
      },
      fetch,
    });

    await clients.server.lookupTransaction('2000000999', { environment: 'sandbox' });
    assert.equal(fetch._calls.length, 2);
    assert.ok(fetch._calls[0].url.includes('api.storekit-sandbox.itunes.apple.com'));
  });

  test('lookupTransaction maps 404 from Apple to rejected AppStoreError with status 404', async () => {
    const notFoundFixture = loadFixture('error_not_found.json');
    const fetch = fakeFetch(async () => jsonResponse(notFoundFixture, 404));

    const clients = createAppStoreClients({
      config: {
        server: {
          keyId: 'k',
          issuerId: 'i',
          bundleId: 'app.mycarecoins',
          privateKey: privateKeyPem,
        },
      },
      fetch,
    });

    await assert.rejects(
      async () => clients.server.lookupTransaction('9999999999'),
      (err) => {
        assert.ok(err instanceof AppStoreError);
        assert.equal(err.kind, 'rejected');
        assert.equal(err.status, 404);
        assert.equal(err.code, '4040010');
        assert.match(err.message, /Transaction id not found/);
        return true;
      }
    );
  });

  test('maps network errors and 5xx to unavailable AppStoreError', async () => {
    const fetch = fakeFetch(async () => jsonResponse({ message: 'Internal Server Error' }, 500));
    const clients = createAppStoreClients({
      config: {
        server: {
          keyId: 'k',
          issuerId: 'i',
          bundleId: 'app.mycarecoins',
          privateKey: privateKeyPem,
        },
      },
      fetch,
    });

    await assert.rejects(
      async () => clients.server.getTransaction('123'),
      (err) => {
        assert.ok(err instanceof AppStoreError);
        assert.equal(err.kind, 'unavailable');
        assert.equal(err.status, 500);
        return true;
      }
    );
  });
});
