'use strict';

const DEFAULT_ITERATIONS = 5000;

function randomStandardNormal() {
  let u = 0;
  let v = 0;
  while (u === 0) u = Math.random();
  while (v === 0) v = Math.random();
  return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}

function sampleNoise(mean, std, distribution) {
  if (std <= 0) return mean;
  const z = randomStandardNormal();
  if (distribution === 'lognormal') {
    const sigma = Math.sqrt(Math.log(1 + (std / Math.max(Math.abs(mean), 1)) ** 2));
    const mu = Math.log(Math.max(Math.abs(mean), 1)) - (sigma ** 2) / 2;
    const sample = Math.exp(mu + sigma * z);
    return mean >= 0 ? sample : -sample;
  }
  return mean + std * z;
}

function runMonteCarlo(startingBalance, baseForecast, dailyStd, opts = {}) {
  const iterations = opts.iterations || DEFAULT_ITERATIONS;
  const distribution = opts.distribution || 'normal';
  const horizonDays = baseForecast.length;

  const balancesByDay = Array.from({ length: horizonDays }, () => new Array(iterations));
  const gapCountByDay = new Array(horizonDays).fill(0);

  for (let i = 0; i < iterations; i++) {
    let runningBalance = startingBalance;
    for (let d = 0; d < horizonDays; d++) {
      const noisyFlow = sampleNoise(baseForecast[d], dailyStd[d] || 0, distribution);
      runningBalance += noisyFlow;
      balancesByDay[d][i] = runningBalance;
      if (runningBalance < 0) gapCountByDay[d] += 1;
    }
  }

  const p10 = [];
  const p50 = [];
  const p90 = [];
  const cashGapProbability = [];

  for (let d = 0; d < horizonDays; d++) {
    const sorted = balancesByDay[d].slice().sort((a, b) => a - b);
    p10.push(percentile(sorted, 10));
    p50.push(percentile(sorted, 50));
    p90.push(percentile(sorted, 90));
    cashGapProbability.push(gapCountByDay[d] / iterations);
  }

  return { p10, p50, p90, cashGapProbability };
}

function percentile(sortedArr, p) {
  if (sortedArr.length === 0) return 0;
  const idx = (p / 100) * (sortedArr.length - 1);
  const lower = Math.floor(idx);
  const upper = Math.ceil(idx);
  if (lower === upper) return sortedArr[lower];
  const weight = idx - lower;
  return sortedArr[lower] * (1 - weight) + sortedArr[upper] * weight;
}

module.exports = { runMonteCarlo, sampleNoise, randomStandardNormal, percentile, DEFAULT_ITERATIONS };
