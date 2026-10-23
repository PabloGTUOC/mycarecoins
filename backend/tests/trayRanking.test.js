import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { rankTemplates, TRAY_QUICK_MAX, TRAY_QUICK_MIN } from '../src/utils/trayRanking.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const fixturePath = path.join(__dirname, 'fixtures/tray_ranking_cases.json');
const cases = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));

describe('rankTemplates fixture suite', () => {
  test('constants match specification', () => {
    assert.equal(TRAY_QUICK_MAX, 8);
    assert.equal(TRAY_QUICK_MIN, 3);
  });

  for (const c of cases) {
    test(c.name, () => {
      const result = rankTemplates({
        templates: c.templates,
        activities: c.activities,
        userId: c.userId,
        now: c.now,
      });

      const actualOrdered = result.ordered.map((t) => t.title);
      const actualQuick = result.quick.map((t) => t.title);

      assert.deepStrictEqual(actualOrdered, c.ordered, `Ordered titles mismatch for case: ${c.name}`);
      assert.deepStrictEqual(actualQuick, c.quick, `Quick titles mismatch for case: ${c.name}`);
    });
  }
});
