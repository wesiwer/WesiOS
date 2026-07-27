'use strict';

const DEFAULT_PERIOD = 7;
const DEFAULT_ALPHA = 0.3;
const DEFAULT_BETA = 0.1;
const DEFAULT_GAMMA = 0.2;

function holtWintersForecast(series, horizonDays, opts = {}) {
  const period = opts.period || DEFAULT_PERIOD;
  const alpha = opts.alpha ?? DEFAULT_ALPHA;
  const beta = opts.beta ?? DEFAULT_BETA;
  const gamma = opts.gamma ?? DEFAULT_GAMMA;

  if (series.length < period * 2) {
    const mean = series.length > 0 ? series.reduce((a, b) => a + b, 0) / series.length : 0;
    return new Array(horizonDays).fill(mean);
  }

  const firstCycle = series.slice(0, period);
  const secondCycle = series.slice(period, period * 2);
  const firstMean = avg(firstCycle);
  const secondMean = avg(secondCycle);

  let level = firstMean;
  let trend = (secondMean - firstMean) / period;
  let seasonal = firstCycle.map((v) => v - firstMean);

  for (let t = 0; t < series.length; t++) {
    const s = t % period;
    const actual = series[t];
    const prevLevel = level;
    const prevTrend = trend;

    level = alpha * (actual - seasonal[s]) + (1 - alpha) * (prevLevel + prevTrend);
    trend = beta * (level - prevLevel) + (1 - beta) * prevTrend;
    seasonal[s] = gamma * (actual - level) + (1 - gamma) * seasonal[s];
  }

  const forecast = [];
  for (let h = 1; h <= horizonDays; h++) {
    const s = (series.length + h - 1) % period;
    forecast.push(level + h * trend + seasonal[s]);
  }
  return forecast;
}

function avg(nums) {
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

module.exports = { holtWintersForecast, DEFAULT_PERIOD, DEFAULT_ALPHA, DEFAULT_BETA, DEFAULT_GAMMA };
