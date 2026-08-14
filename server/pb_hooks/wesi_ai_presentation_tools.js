function text(value, max) {
  const raw = String(value == null ? "" : value).trim();
  return raw.length <= max ? raw : raw.slice(0, max);
}

function strings(value, maxItems, maxLength) {
  if (!Array.isArray(value)) return [];
  return value.slice(0, maxItems).map(function(item) {
    return text(item, maxLength);
  }).filter(Boolean);
}

function finiteNumbers(value, maxItems) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const raw of value.slice(0, maxItems)) {
    const n = Number(raw);
    if (Number.isFinite(n)) out.push(n);
  }
  return out;
}

function renderTable(input) {
  const columns = strings(input.columns, 20, 120);
  if (!columns.length) return {ok: false, code: "VALIDATION_ERROR", message: "Таблице нужны колонки"};
  const rows = [];
  if (Array.isArray(input.rows)) {
    for (const rawRow of input.rows.slice(0, 100)) {
      if (!Array.isArray(rawRow)) continue;
      const row = [];
      for (let i = 0; i < columns.length; i++) row.push(text(rawRow[i], 500));
      rows.push(row);
    }
  }
  if (!rows.length) return {ok: false, code: "VALIDATION_ERROR", message: "Таблице нужны строки"};
  return {
    ok: true,
    result: {
      contentBlock: {
        type: "table",
        data: {title: text(input.title, 240), columns: columns, rows: rows},
      },
    },
  };
}

function renderChart(input) {
  const chartType = text(input.chartType, 20).toLowerCase();
  if (["line", "bar", "pie", "scatter"].indexOf(chartType) < 0) {
    return {ok: false, code: "VALIDATION_ERROR", message: "Поддерживаются line, bar, pie и scatter"};
  }
  const labels = strings(input.labels, 80, 80);
  const series = [];
  if (Array.isArray(input.series)) {
    for (const raw of input.series.slice(0, 12)) {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
      const values = finiteNumbers(raw.values, 200);
      if (!values.length) continue;
      series.push({name: text(raw.name, 120), values: values});
    }
  }
  if (!series.length) return {ok: false, code: "VALIDATION_ERROR", message: "Графику нужны числовые серии"};
  if (chartType !== "scatter" && !labels.length) {
    return {ok: false, code: "VALIDATION_ERROR", message: "Графику нужны подписи точек"};
  }
  return {
    ok: true,
    result: {
      contentBlock: {
        type: "chart",
        data: {
          title: text(input.title, 240),
          chartType: chartType,
          labels: labels,
          series: series,
          xLabel: text(input.xLabel, 100),
          yLabel: text(input.yLabel, 100),
        },
      },
    },
  };
}

function renderDiagram(input) {
  const nodes = [];
  const nodeIds = {};
  if (Array.isArray(input.nodes)) {
    for (const raw of input.nodes.slice(0, 40)) {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
      const id = text(raw.id, 80);
      const label = text(raw.label, 220);
      if (!id || !label || nodeIds[id]) continue;
      nodeIds[id] = true;
      nodes.push({id: id, label: label});
    }
  }
  if (!nodes.length) return {ok: false, code: "VALIDATION_ERROR", message: "Диаграмме нужны узлы"};
  const edges = [];
  if (Array.isArray(input.edges)) {
    for (const raw of input.edges.slice(0, 80)) {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) continue;
      const from = text(raw.from, 80);
      const to = text(raw.to, 80);
      if (!nodeIds[from] || !nodeIds[to]) continue;
      edges.push({from: from, to: to, label: text(raw.label, 120)});
    }
  }
  return {
    ok: true,
    result: {
      contentBlock: {
        type: "diagram",
        data: {title: text(input.title, 240), nodes: nodes, edges: edges},
      },
    },
  };
}

module.exports = {
  definitions: function() {
    return [
      {
        name: "render_table",
        description: "Показать пользователю интерактивно читаемую таблицу прямо в сообщении Wesi AI. Используй, когда данные лучше сравнивать по строкам и колонкам.",
        parameters: {
          type: "object",
          required: ["columns", "rows"],
          properties: {
            title: {type: "string"},
            columns: {type: "array", items: {type: "string"}, maxItems: 20},
            rows: {type: "array", items: {type: "array"}, maxItems: 100},
          },
        },
      },
      {
        name: "render_chart",
        description: "Построить график прямо в сообщении Wesi AI. line — динамика, bar — сравнение, pie — доли, scatter — связь числовых наблюдений. Передавай только данные, которые уже известны или получены verified WesiOS tools; не выдумывай числа.",
        parameters: {
          type: "object",
          required: ["chartType", "series"],
          properties: {
            title: {type: "string"},
            chartType: {type: "string", enum: ["line", "bar", "pie", "scatter"]},
            labels: {type: "array", items: {type: "string"}, maxItems: 80},
            series: {
              type: "array",
              maxItems: 12,
              items: {
                type: "object",
                required: ["values"],
                properties: {
                  name: {type: "string"},
                  values: {type: "array", items: {type: "number"}, maxItems: 200},
                },
              },
            },
            xLabel: {type: "string"},
            yLabel: {type: "string"},
          },
        },
      },
      {
        name: "render_diagram",
        description: "Построить схему или диаграмму процесса прямо в сообщении Wesi AI из узлов и связей.",
        parameters: {
          type: "object",
          required: ["nodes"],
          properties: {
            title: {type: "string"},
            nodes: {
              type: "array",
              maxItems: 40,
              items: {
                type: "object",
                required: ["id", "label"],
                properties: {id: {type: "string"}, label: {type: "string"}},
              },
            },
            edges: {
              type: "array",
              maxItems: 80,
              items: {
                type: "object",
                required: ["from", "to"],
                properties: {from: {type: "string"}, to: {type: "string"}, label: {type: "string"}},
              },
            },
          },
        },
      },
    ];
  },

  context: function() {
    return {presentationBlocks: ["table", "chart", "diagram"]};
  },

  execute: function(e, ctx, name, args) {
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    if (name === "render_table") return renderTable(input);
    if (name === "render_chart") return renderChart(input);
    if (name === "render_diagram") return renderDiagram(input);
    return {ok: false, code: "FORBIDDEN", message: "Неизвестный presentation tool"};
  },
};
