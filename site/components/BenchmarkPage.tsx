import data from '../docs/benchmark/data.json';

type GateStatus = string;

type RunMetrics = {
  hybrid_recall_at_5?: number | null;
  hybrid_mrr_at_5?: number | null;
  bm25_recall_at_5?: number | null;
  bm25_mrr_at_5?: number | null;
  vs_bm25_pct?: number | null;
  target_15pct?: string | null;
  near_dup_supersede_rate?: number | null;
  near_dup_ok?: number | null;
  near_dup_total?: number | null;
  cross_user_leaks?: number | null;
  reopen_ok?: number | null;
  extraction_precision?: number | null;
  extraction_hit?: number | null;
  extraction_denom?: number | null;
  extraction_status?: string | null;
};

type Run = {
  embedder?: string;
  model?: string | null;
  dim?: number | null;
  extractor_model?: string | null;
  metrics: RunMetrics;
  gates: Record<string, GateStatus>;
  status: string;
};

type ResultDoc = {
  version: string;
  git_tag: string;
  committed_at: string;
  fixture?: { path: string; note: string };
  runs: {
    offline: Run;
    api: Run;
    live: Run;
  };
};

const MODE_ORDER = ['offline', 'api', 'live'] as const;

function fmt(n: number | null | undefined, digits = 3): string {
  if (n === null || n === undefined || Number.isNaN(n)) return '—';
  return n.toFixed(digits);
}

function fmtPct(n: number | null | undefined): string {
  if (n === null || n === undefined || Number.isNaN(n)) return '—';
  const sign = n > 0 ? '+' : '';
  return `${sign}${n.toFixed(1)}%`;
}

function delta(
  cur: number | null | undefined,
  prev: number | null | undefined,
): string {
  if (
    cur === null ||
    cur === undefined ||
    prev === null ||
    prev === undefined ||
    Number.isNaN(cur) ||
    Number.isNaN(prev)
  ) {
    return '—';
  }
  const d = cur - prev;
  const sign = d > 0 ? '+' : '';
  return `${sign}${d.toFixed(3)}`;
}

function StatusChip({ status }: { status: string }) {
  const color =
    status === 'pass'
      ? '#1a7f37'
      : status === 'fail'
        ? '#cf222e'
        : status === 'error'
          ? '#9a6700'
          : '#656d76';
  return (
    <span
      style={{
        display: 'inline-block',
        marginRight: '0.5rem',
        fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
        fontSize: '0.85rem',
        color,
        fontWeight: 600,
      }}
    >
      {status}
    </span>
  );
}

function MetricRow({
  label,
  value,
  prev,
}: {
  label: string;
  value: string;
  prev?: string;
}) {
  return (
    <tr>
      <td>{label}</td>
      <td style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }}>
        {value}
      </td>
      {prev !== undefined ? (
        <td style={{ fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace' }}>
          {prev}
        </td>
      ) : null}
    </tr>
  );
}

export function BenchmarkPage() {
  const results = data.results as ResultDoc[];
  const latestVersion = data.latestVersion as string;
  const latest = results.find(r => r.version === latestVersion) ?? results[0];
  // results are newest-first; previous release is the next older entry.
  const latestIdx = latest
    ? results.findIndex(r => r.version === latest.version)
    : -1;
  const previous =
    latestIdx >= 0 && latestIdx + 1 < results.length
      ? results[latestIdx + 1]
      : undefined;

  if (!latest) {
    return <p>No benchmark results yet.</p>;
  }

  return (
    <div>
      <p>
        Latest release <strong>{latest.version}</strong> ({latest.git_tag}) ·{' '}
        {latest.committed_at}
      </p>
      <p>
        Offline <StatusChip status={latest.runs.offline.status} />
        API <StatusChip status={latest.runs.api.status} />
        Live <StatusChip status={latest.runs.live.status} />
      </p>
      {latest.fixture ? (
        <p style={{ fontSize: '0.9rem', opacity: 0.85 }}>
          Fixture: <code>{latest.fixture.path}</code> — {latest.fixture.note}
        </p>
      ) : null}

      <h2>Summary</h2>
      <table>
        <thead>
          <tr>
            <th>Version</th>
            <th>Offline</th>
            <th>API hybrid R@5</th>
            <th>vs BM25</th>
            <th>Live precision</th>
            <th>Conflict</th>
          </tr>
        </thead>
        <tbody>
          {results.map(r => (
            <tr key={r.version}>
              <td>
                <code>{r.version}</code>
              </td>
              <td>
                <StatusChip status={r.runs.offline.status} />
              </td>
              <td>
                {fmt(r.runs.api.metrics.hybrid_recall_at_5)}{' '}
                <StatusChip status={r.runs.api.status} />
              </td>
              <td>{fmtPct(r.runs.api.metrics.vs_bm25_pct)}</td>
              <td>
                {fmt(r.runs.live.metrics.extraction_precision)}{' '}
                <StatusChip status={r.runs.live.status} />
              </td>
              <td>
                {fmt(r.runs.offline.metrics.near_dup_supersede_rate)}
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      <h2>Latest breakdown ({latest.version})</h2>
      {MODE_ORDER.map(mode => {
        const run = latest.runs[mode];
        const m = run.metrics;
        return (
          <div key={mode} style={{ marginBottom: '1.5rem' }}>
            <h3>
              {mode} · <StatusChip status={run.status} />
              {run.model ? (
                <span style={{ fontWeight: 400, fontSize: '0.9rem' }}>
                  {' '}
                  model={run.model}
                  {run.dim ? ` dim=${run.dim}` : ''}
                </span>
              ) : null}
              {run.extractor_model ? (
                <span style={{ fontWeight: 400, fontSize: '0.9rem' }}>
                  {' '}
                  extractor={run.extractor_model}
                </span>
              ) : null}
            </h3>
            <table>
              <thead>
                <tr>
                  <th>Metric</th>
                  <th>Value</th>
                </tr>
              </thead>
              <tbody>
                <MetricRow
                  label="Hybrid Recall@5"
                  value={fmt(m.hybrid_recall_at_5)}
                />
                <MetricRow label="Hybrid MRR@5" value={fmt(m.hybrid_mrr_at_5)} />
                <MetricRow
                  label="BM25 Recall@5"
                  value={fmt(m.bm25_recall_at_5)}
                />
                <MetricRow label="BM25 MRR@5" value={fmt(m.bm25_mrr_at_5)} />
                <MetricRow label="vs BM25" value={fmtPct(m.vs_bm25_pct)} />
                <MetricRow
                  label="TARGET_15PCT"
                  value={m.target_15pct ?? '—'}
                />
                <MetricRow
                  label="Near-dup supersede"
                  value={`${fmt(m.near_dup_supersede_rate)} (${m.near_dup_ok ?? '—'}/${m.near_dup_total ?? '—'})`}
                />
                <MetricRow
                  label="Cross-user leaks"
                  value={String(m.cross_user_leaks ?? '—')}
                />
                <MetricRow
                  label="Persistence reopen"
                  value={String(m.reopen_ok ?? '—')}
                />
                <MetricRow
                  label="Extraction precision"
                  value={
                    m.extraction_status === 'skipped'
                      ? 'skipped'
                      : `${fmt(m.extraction_precision)} (${m.extraction_hit ?? '—'}/${m.extraction_denom ?? '—'})`
                  }
                />
              </tbody>
            </table>
            <p style={{ fontSize: '0.9rem' }}>
              Gates:{' '}
              {Object.entries(run.gates)
                .map(([k, v]) => `${k}=${v}`)
                .join(' · ')}
            </p>
          </div>
        );
      })}

      <h2>Diff vs previous</h2>
      {!previous ? (
        <p>Only one archived version — no previous release to compare.</p>
      ) : (
        <>
          <p>
            Comparing <code>{latest.version}</code> → previous{' '}
            <code>{previous.version}</code>
          </p>
          <table>
            <thead>
              <tr>
                <th>Metric</th>
                <th>{latest.version}</th>
                <th>Δ vs {previous.version}</th>
              </tr>
            </thead>
            <tbody>
              <MetricRow
                label="API hybrid Recall@5"
                value={fmt(latest.runs.api.metrics.hybrid_recall_at_5)}
                prev={delta(
                  latest.runs.api.metrics.hybrid_recall_at_5,
                  previous.runs.api.metrics.hybrid_recall_at_5,
                )}
              />
              <MetricRow
                label="API vs BM25 %"
                value={fmtPct(latest.runs.api.metrics.vs_bm25_pct)}
                prev={delta(
                  latest.runs.api.metrics.vs_bm25_pct,
                  previous.runs.api.metrics.vs_bm25_pct,
                )}
              />
              <MetricRow
                label="Offline hybrid Recall@5"
                value={fmt(latest.runs.offline.metrics.hybrid_recall_at_5)}
                prev={delta(
                  latest.runs.offline.metrics.hybrid_recall_at_5,
                  previous.runs.offline.metrics.hybrid_recall_at_5,
                )}
              />
              <MetricRow
                label="Live extraction precision"
                value={fmt(latest.runs.live.metrics.extraction_precision)}
                prev={delta(
                  latest.runs.live.metrics.extraction_precision,
                  previous.runs.live.metrics.extraction_precision,
                )}
              />
              <MetricRow
                label="Near-dup supersede"
                value={fmt(latest.runs.offline.metrics.near_dup_supersede_rate)}
                prev={delta(
                  latest.runs.offline.metrics.near_dup_supersede_rate,
                  previous.runs.offline.metrics.near_dup_supersede_rate,
                )}
              />
              <MetricRow
                label="API status"
                value={latest.runs.api.status}
                prev={
                  latest.runs.api.status === previous.runs.api.status
                    ? 'unchanged'
                    : `${previous.runs.api.status} → ${latest.runs.api.status}`
                }
              />
              <MetricRow
                label="Live status"
                value={latest.runs.live.status}
                prev={
                  latest.runs.live.status === previous.runs.live.status
                    ? 'unchanged'
                    : `${previous.runs.live.status} → ${latest.runs.live.status}`
                }
              />
            </tbody>
          </table>
        </>
      )}
    </div>
  );
}
