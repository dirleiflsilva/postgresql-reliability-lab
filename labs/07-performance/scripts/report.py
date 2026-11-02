#!/usr/bin/env python3
"""Generate a Markdown report from retained Lab 07 evidence."""
import json
import math
from pathlib import Path
import statistics
import sys


def summary(values):
    values = sorted(values)
    return f'{statistics.median(values):.3f} / {values[math.ceil(len(values)*.95)-1]:.3f} / {statistics.pstdev(values):.3f} (n={len(values)})'


def deltas(before, after):
    if before['reset'] != after['reset']:
        return {'valid': False, 'reason': 'stats_reset ou dealloc mudou durante a janela'}
    old = {(s['userid'],s['dbid'],s['queryid']): s for s in before['statements']}
    rows = []
    for statement in after['statements']:
        prior = old.get((statement['userid'],statement['dbid'],statement['queryid']), {})
        row = {k: statement[k] - prior.get(k, 0) for k in ('calls','total_exec_time','shared_blks_hit','shared_blks_read')}
        if any(value < 0 for value in row.values()):
            return {'valid': False, 'reason': 'Contador diminuiu'}
        if row['calls']:
            row['query'] = statement['query']
            rows.append(row)
    return {'valid': True, 'statements': rows}


def report(folder):
    results = json.loads((folder/'results.json').read_text())
    meta = json.loads((folder/'metadata.json').read_text())
    lines = ['# Lab 07 — resultados', '',
             f"Perfil: `{meta['manifest']['profile']}`; pedidos: {meta['manifest']['orders']}; líder: `{meta['leader']}`.",
             f"Janela UTC: {meta['started_utc']} a {meta.get('finished_utc','incompleta')}.", '',
             'Tempos em ms: mediana / p95 / desvio padrão. As amostras de EXPLAIN incluem o custo de instrumentação; as latências pgbench incluem a comunicação cliente/servidor.', '',
             '| Cenário | Fase | Execução servidor (ms) | Buffers hit/read, mediana |',
             '|---|---|---|---|']
    for name, phases in results.items():
        if name == 'write_cost':
            continue
        for phase, rounds in phases.items():
            plans = [p for r in rounds for p in r['plans']]
            hits = statistics.median(p['Plan'].get('Shared Hit Blocks',0) for p in plans)
            reads = statistics.median(p['Plan'].get('Shared Read Blocks',0) for p in plans)
            lines.append(f'| {name} | {phase} | {summary([p["Execution Time"] for p in plans])} | {hits:g} / {reads:g} |')
            for r in rounds:
                label = f'{name}_{phase}_{r["round"]}'
                before = json.loads((folder/(label+'.before.json')).read_text())
                after = json.loads((folder/(label+'.after.json')).read_text())
                (folder/(label+'.delta.json')).write_text(json.dumps(deltas(before,after),indent=2)+'\n')
    lines += ['', '| Cenário | Fase | Clientes | Latência cliente (ms) | TPS médio entre rodadas | Falhas |', '|---|---|---:|---|---:|---:|']
    for name, phases in results.items():
        if name == 'write_cost':
            continue
        for phase, rounds in phases.items():
            for clients in meta['clients']:
                data = [c for r in rounds for c in r['concurrent'] if c['clients']==clients]
                lines.append(f'| {name} | {phase} | {clients} | {summary([v for c in data for v in c["latency_ms"]])} | {statistics.mean(c["tps"] for c in data):.2f} | {sum(c["failures"] for c in data)} |')
    if 'write_cost' in results:
        lines += ['', '## Custo de escrita', '',
                  'Duas cópias equivalentes, 1 cliente, 1.000 atualizações com a mesma semente, alterando a coluna de data indexada. Sem aquecimento de escrita. Ordem fixa baseline/optimized: esta medição é exploratória, não um teste de capacidade. WAL inclui atividade de todo o cluster na janela.', '',
                  '| Fase | Latência ms | TPS | WAL cluster bytes | Tabela + índices bytes |', '|---|---|---:|---:|---:|']
        for phase, data in results['write_cost'].items():
            lines.append(f'| {phase} | {summary(data["latency_ms"])} | {data["tps"]:.2f} | {data["wal_cluster_bytes"]} | {data["bytes"]} |')
    lines += ['', '## Limites', '',
              '- Cache aquecido; não há garantia de cache frio do sistema operacional.',
              '- Planos completos, consultas, snapshots e deltas estão nos arquivos desta execução. Estatísticas agregadas não fornecem p95.',
              '- Resultados valem para o perfil, máquina, parâmetros e janelas registrados. O perfil small é uma validação funcional.',
              '- Dados e consultas de leitura são fixos; os clientes repetem cada consulta em modo simple. Não representa uma aplicação com distribuição variada de parâmetros.',
              '- A duração pode ser reduzida na validação; use 60 segundos, três rodadas e 1/4/8 clientes para o experimento principal.',
              '- Arquivos de execuções interrompidas são preservados; ausência de finished_utc significa execução incompleta.', '']
    (folder/'report.md').write_text('\n'.join(lines))


if __name__ == '__main__':
    report(Path(sys.argv[1]).resolve())
