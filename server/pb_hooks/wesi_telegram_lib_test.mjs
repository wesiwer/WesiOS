import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const lib = require('./wesi_telegram_lib.js');

assert.deepEqual(lib.parseCommand('/brief', 'WesiOSBot'), {name: 'brief', args: '', raw: '/brief'});
assert.equal(lib.parseCommand('/cash@WesiOSBot', 'WesiOSBot').name, 'cash');
assert.equal(lib.parseCommand('/cash@OtherBot', 'WesiOSBot').name, 'foreign');
assert.equal(lib.parseCommand('сколько денег на Beats?', 'WesiOSBot').name, 'cash');
assert.equal(lib.parseCommand('есть риск кассового разрыва?', 'WesiOSBot').name, 'risk');
assert.equal(lib.isExplicitGroupCommand('/cash@WesiOSBot', 'WesiOSBot'), true);
assert.equal(lib.isExplicitGroupCommand('/cash', 'WesiOSBot'), false);
assert.equal(lib.isExplicitGroupCommand('сколько денег?', 'WesiOSBot'), false);
assert.equal(lib.isExplicitGroupCommand('/cash@OtherBot', 'WesiOSBot'), false);
assert.equal(lib.parseStartCode({name: 'start', args: 'Abcd_1234567890-xy'}), 'Abcd_1234567890-xy');
assert.equal(lib.parseStartCode({name: 'start', args: '123'}), '');

const cb = lib.callback('org', 'org_wesi_beats');
assert.deepEqual(lib.parseCallback(cb), {action: 'org', value: 'org_wesi_beats'});
assert.equal(lib.parseCallback('bad'), null);

assert.equal(lib.riskFromCushionDays(8).level, 'critical');
assert.equal(lib.riskFromCushionDays(20).level, 'warning');
assert.equal(lib.riskFromCushionDays(45).level, 'ok');
assert.equal(lib.riskFromCushionDays(null).level, 'unknown');
assert.equal(lib.shouldNotifyRisk('ok', 'warning'), true);
assert.equal(lib.shouldNotifyRisk('warning', 'warning'), false);
assert.equal(lib.shouldNotifyRisk('warning', 'critical'), true);
assert.equal(lib.shouldNotifyRisk('critical', 'warning'), false);
assert.equal(lib.shouldNotifyRisk('critical', 'ok'), false);
assert.equal(lib.shouldNotifyOverdue(0, 1), true);
assert.equal(lib.shouldNotifyOverdue(2, 3), true);
assert.equal(lib.shouldNotifyOverdue(3, 3), false);
assert.equal(lib.shouldNotifyOverdue(3, 1), false);
assert.equal(lib.shouldNotifyOverdue(1, 0), false);

assert.equal(lib.dueState('2026-08-17T12:00:00Z', new Date('2026-08-18T10:00:00Z'), 0), 'overdue');
assert.equal(lib.dueState('2026-08-18T23:00:00Z', new Date('2026-08-18T10:00:00Z'), 0), 'today');
assert.equal(lib.dueState('2026-08-19T01:00:00Z', new Date('2026-08-18T10:00:00Z'), 0), 'future');
// At UTC+3 both 22:00Z and 23:30Z are already on the next local calendar day.
assert.equal(lib.dueState('2026-08-18T23:30:00Z', new Date('2026-08-18T22:00:00Z'), 180), 'today');

assert.equal(lib.isQuietHours(Date.UTC(2026, 7, 18, 21), 180, 23, 8), true); // 00:00 local
assert.equal(lib.isQuietHours(Date.UTC(2026, 7, 18, 10), 180, 23, 8), false);

let rate = lib.acceptRate(null, 1000, 2, 60000);
assert.equal(rate.ok, true);
rate = lib.acceptRate(rate.state, 2000, 2, 60000);
assert.equal(rate.ok, true);
rate = lib.acceptRate(rate.state, 3000, 2, 60000);
assert.equal(rate.ok, false);
rate = lib.acceptRate(rate.state, 70000, 2, 60000);
assert.equal(rate.ok, true);

assert.equal(lib.escapeHtml('<x & y>'), '&lt;x &amp; y&gt;');
assert.equal(lib.formatMoney(182400, 'RUB'), '182 400 ₽');
assert.equal(lib.formatMoney(12.5, 'USD'), '12,5 $');

console.log('wesi_telegram_lib_test: ok');
