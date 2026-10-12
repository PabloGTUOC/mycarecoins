import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { serviceError, sendServiceError } from '../src/utils/httpError.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const SERVICES_DIR = path.resolve(__dirname, '../src/services');

describe('httpError helpers', () => {
  test('serviceError constructs standard shape without params', () => {
    const res = serviceError(404, 'userNotFound', 'User not found.');
    assert.deepEqual(res, {
      error: {
        code: 404,
        key: 'userNotFound',
        message: 'User not found.',
      },
    });
  });

  test('serviceError constructs standard shape with params', () => {
    const res = serviceError(400, 'itemLimitExceeded', 'Limit of 5 exceeded.', { limit: 5 });
    assert.deepEqual(res, {
      error: {
        code: 400,
        key: 'itemLimitExceeded',
        message: 'Limit of 5 exceeded.',
        params: { limit: 5 },
      },
    });
  });

  test('sendServiceError sends status and { error, code } without params', () => {
    let statusCode = null;
    let jsonBody = null;
    const fakeRes = {
      status(s) {
        statusCode = s;
        return this;
      },
      json(body) {
        jsonBody = body;
        return this;
      },
    };

    const err = serviceError(403, 'familyNotMember', 'Not a family member.').error;
    sendServiceError(fakeRes, err);

    assert.equal(statusCode, 403);
    assert.deepEqual(jsonBody, {
      error: 'Not a family member.',
      code: 'familyNotMember',
    });
  });

  test('sendServiceError sends status and { error, code, params } with params', () => {
    let statusCode = null;
    let jsonBody = null;
    const fakeRes = {
      status(s) {
        statusCode = s;
        return this;
      },
      json(body) {
        jsonBody = body;
        return this;
      },
    };

    const err = serviceError(409, 'personalTimeTooShort', 'Personal time must last at least 15 minutes.', { minutes: 15 }).error;
    sendServiceError(fakeRes, err);

    assert.equal(statusCode, 409);
    assert.deepEqual(jsonBody, {
      error: 'Personal time must last at least 15 minutes.',
      code: 'personalTimeTooShort',
      params: { minutes: 15 },
    });
  });
});

describe('static scan: service errors have keys', () => {
  const serviceFiles = fs.readdirSync(SERVICES_DIR)
    .filter(file => file.endsWith('.js') && file !== 'adminService.js');

  test('all service error literals and serviceError calls include a key', () => {
    const missingKeys = [];

    for (const file of serviceFiles) {
      const fullPath = path.join(SERVICES_DIR, file);
      const content = fs.readFileSync(fullPath, 'utf8');
      const lines = content.split('\n');

      // 1. Check for legacy { error: { code: ... } } literals without key:
      for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.includes('error:') && line.includes('code:')) {
          const window = lines.slice(i, i + 6).join(' ');
          if (!window.includes('key:')) {
            missingKeys.push(`${file}:${i + 1} - object literal missing key`);
          }
        }
      }

      // 2. Check serviceError calls
      const serviceErrorRegex = /serviceError\s*\(\s*(\d+)\s*(?:,\s*([^,\n)]+))?/g;
      let m;
      while ((m = serviceErrorRegex.exec(content)) !== null) {
        const lineNum = content.slice(0, m.index).split('\n').length;
        const keyArg = m[2]?.trim();
        if (!keyArg) {
          missingKeys.push(`${file}:${lineNum} - serviceError missing key argument`);
        } else if (keyArg.startsWith("'") || keyArg.startsWith('"')) {
          const keyLiteral = keyArg.slice(1, -1);
          // Key should be camelCase, domain first, no whitespace
          if (!/^[a-z][a-zA-Z0-9]*$/.test(keyLiteral)) {
            missingKeys.push(`${file}:${lineNum} - key literal "${keyLiteral}" is not lowerCamelCase`);
          }
        }
      }
    }

    assert.deepEqual(missingKeys, [], `Found service errors lacking a valid key: \n${missingKeys.join('\n')}`);
  });
});

describe('static scan: one message text -> one key', () => {
  const serviceFiles = fs.readdirSync(SERVICES_DIR)
    .filter(file => file.endsWith('.js') && file !== 'adminService.js');

  test('each message text maps to exactly one stable key across all services', () => {
    const messageToKeys = new Map();

    for (const file of serviceFiles) {
      const fullPath = path.join(SERVICES_DIR, file);
      const content = fs.readFileSync(fullPath, 'utf8');

      // Match serviceError(status, 'key', 'message' | `message` | "message")
      const serviceErrorRegex = /serviceError\s*\(\s*(\d+)\s*,\s*([a-zA-Z0-9_.'"`]+)\s*,\s*(['"`])([\s\S]*?)\3/g;
      let m;
      while ((m = serviceErrorRegex.exec(content)) !== null) {
        const rawKey = m[2].trim();
        const rawMsg = m[4].trim();
        const key = rawKey.replace(/^['"`]|['"`]$/g, '');
        if (rawKey.startsWith("'") || rawKey.startsWith('"')) {
          if (!messageToKeys.has(rawMsg)) {
            messageToKeys.set(rawMsg, new Set());
          }
          messageToKeys.get(rawMsg).add(key);
        }
      }

      // refuse(key, message) helper
      const refuseRegex = /refuse\s*\(\s*['"]([a-zA-Z0-9_]+)['"]\s*,\s*(['"`])([\s\S]*?)\2/g;
      while ((m = refuseRegex.exec(content)) !== null) {
        const key = m[1];
        const msg = m[3].trim();
        if (!messageToKeys.has(msg)) messageToKeys.set(msg, new Set());
        messageToKeys.get(msg).add(key);
      }

      // { key: '...', message: '...' } helper
      const keyMsgRegex = /key\s*:\s*['"]([a-zA-Z0-9_]+)['"]\s*,\s*message\s*:\s*(['"`])([\s\S]*?)\2/g;
      while ((m = keyMsgRegex.exec(content)) !== null) {
        const key = m[1];
        const msg = m[3].trim();
        if (!messageToKeys.has(msg)) messageToKeys.set(msg, new Set());
        messageToKeys.get(msg).add(key);
      }

      // { error: '...', key: '...' } helper
      const errorKeyRegex = /error\s*:\s*(['"`])([\s\S]*?)\1\s*,\s*key\s*:\s*['"]([a-zA-Z0-9_]+)['"]/g;
      while ((m = errorKeyRegex.exec(content)) !== null) {
        const key = m[3];
        const msg = m[2].trim();
        if (!messageToKeys.has(msg)) messageToKeys.set(msg, new Set());
        messageToKeys.get(msg).add(key);
      }
    }

    const conflicts = [];
    for (const [msg, keys] of messageToKeys.entries()) {
      if (keys.size > 1) {
        conflicts.push(`Message "${msg}" maps to multiple keys: [${Array.from(keys).join(', ')}]`);
      }
    }

    assert.deepEqual(conflicts, [], `Found message-to-key conflicts: \n${conflicts.join('\n')}`);
  });
});
