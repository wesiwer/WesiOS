'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { computeForecast } = require('./src/forecastEngine');

initializeApp();

exports.forecastBalance = onCall(
  { region: 'europe-west1', memory: '512MiB', timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Требуется авторизация.');
    }

    const uid = request.auth.uid;
    const horizonDays = clampHorizon(request.data?.horizonDays);
    const distribution = request.data?.distribution === 'lognormal' ? 'lognormal' : 'normal';

    const db = getFirestore();

    const [transactions, scheduledRules, whatIfScenarios, accountDoc] = await Promise.all([
      loadTransactions(db, uid),
      loadScheduledRules(db, uid),
      loadWhatIfScenarios(db, uid),
      db.collection('users').doc(uid).collection('finance').doc('account').get(),
    ]);

    const currentBalance = accountDoc.exists ? (accountDoc.data().currentBalance || 0) : 0;
    const startDate = tomorrowISO();

    const result = computeForecast({
      currentBalance,
      transactions,
      scheduledRules,
      whatIfScenarios,
      horizonDays,
      startDate,
      distribution,
      iterations: 5000,
    });

    await db
      .collection('users')
      .doc(uid)
      .collection('finance')
      .doc('lastForecast')
      .set({ ...result, computedAt: new Date().toISOString() });

    return result;
  }
);

exports.nightlyForecastRefresh = onSchedule(
  { schedule: '0 3 * * *', timeZone: 'Europe/Moscow', region: 'europe-west1' },
  async () => {
    const db = getFirestore();
    const usersSnap = await db.collection('users').get();

    for (const userDoc of usersSnap.docs) {
      const uid = userDoc.id;
      try {
        const [transactions, scheduledRules, whatIfScenarios, accountDoc] = await Promise.all([
          loadTransactions(db, uid),
          loadScheduledRules(db, uid),
          loadWhatIfScenarios(db, uid),
          db.collection('users').doc(uid).collection('finance').doc('account').get(),
        ]);
        if (!accountDoc.exists) continue;

        const result = computeForecast({
          currentBalance: accountDoc.data().currentBalance || 0,
          transactions,
          scheduledRules,
          whatIfScenarios,
          horizonDays: 90,
          startDate: tomorrowISO(),
          distribution: 'normal',
          iterations: 5000,
        });

        await db
          .collection('users')
          .doc(uid)
          .collection('finance')
          .doc('lastForecast')
          .set({ ...result, computedAt: new Date().toISOString() });
      } catch (err) {
        console.error(`Не удалось пересчитать прогноз для ${uid}:`, err);
      }
    }
  }
);

async function loadTransactions(db, uid) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('finance')
    .doc('data')
    .collection('transactions')
    .orderBy('date')
    .get();
  return snap.docs.map((d) => d.data());
}

async function loadScheduledRules(db, uid) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('finance')
    .doc('data')
    .collection('scheduledTransactions')
    .get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function loadWhatIfScenarios(db, uid) {
  const snap = await db
    .collection('users')
    .doc(uid)
    .collection('finance')
    .doc('data')
    .collection('whatIfScenarios')
    .where('active', '==', true)
    .get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

function clampHorizon(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return 90;
  return Math.min(Math.round(n), 365);
}

function tomorrowISO() {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString().slice(0, 10);
}

module.exports.computeForecast = computeForecast;
