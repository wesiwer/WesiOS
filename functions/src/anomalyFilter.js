'use strict';

const Z_SCORE_THRESHOLD = 2.5;

function filterAnomalies(transactions, threshold = Z_SCORE_THRESHOLD) {
  const byCategory = groupBy(transactions, (t) => t.category);
  const statsByCategory = {};
  const cleaned = [];
  const removed = [];

  for (const [category, txs] of Object.entries(byCategory)) {
    const amounts = txs.map((t) => t.amount);
    const mean = average(amounts);
    const std = standardDeviation(amounts, mean);
    statsByCategory[category] = { mean, std, count: txs.length };

    if (std === 0 || txs.length < 4) {
      cleaned.push(...txs);
      continue;
    }

    for (const t of txs) {
      const z = Math.abs((t.amount - mean) / std);
      if (z > threshold) {
        removed.push({ ...t, zScore: Number(z.toFixed(3)) });
      } else {
        cleaned.push(t);
      }
    }
  }

  return { cleaned, removed, statsByCategory };
}

function groupBy(arr, keyFn) {
  return arr.reduce((acc, item) => {
    const key = keyFn(item);
    (acc[key] = acc[key] || []).push(item);
    return acc;
  }, {});
}

function average(nums) {
  if (nums.length === 0) return 0;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

function standardDeviation(nums, mean) {
  if (nums.length === 0) return 0;
  const variance = average(nums.map((n) => (n - mean) ** 2));
  return Math.sqrt(variance);
}

module.exports = { filterAnomalies, average, standardDeviation, groupBy, Z_SCORE_THRESHOLD };
