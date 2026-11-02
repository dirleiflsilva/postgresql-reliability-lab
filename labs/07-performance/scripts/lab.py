#!/usr/bin/env python3
"""Lab 07 orchestration. Host dependencies: Python 3 stdlib, Docker Compose."""
import argparse
import datetime as dt
import hashlib
import fcntl
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import time

LAB = Path(__file__).resolve().parents[1]
ACTIVE_RUN = None
COMPOSE = ['docker', 'compose', '--project-directory', str(LAB), '-f', str(LAB / 'docker-compose.yml')]


def run(args, *, stdin=None, timeout=180):
    result = subprocess.run(args, input=stdin, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'Command failed ({result.returncode}): {args[:4]}\n{result.stderr}\n{result.stdout}')
    return result.stdout.strip()


def compose(*args, **kwargs):
    return run(COMPOSE + list(args), **kwargs)


def sql(query, *, app=False, node=None, variables=None, timeout=180):
    args = ['exec', '-T', 'client']
    if app:
        args += ['sh', '-c', 'export PGPASSWORD="$APP_PASSWORD"; exec psql "$@"', 'sh']
    else:
        args += ['psql']
    args += ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1']
    if app:
        args += ['-U', 'app_user']
    if node:
        args += ['-h', node]
    for key, value in (variables or {}).items():
        args += ['-v', f'{key}={value}']
    return compose(*args, stdin="SET timezone='UTC'; SET statement_timeout='120s';\n" + query, timeout=timeout)


def scalar(query, **kwargs):
    return sql(query, **kwargs).splitlines()[-1]


def js(query, **kwargs):
    return json.loads(sql(query, **kwargs))


def save(path, obj):
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n')


def new_run(kind):
    global ACTIVE_RUN
    folder = LAB / 'evidence/runs' / (dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ') + '_' + kind)
    folder.mkdir(parents=True)
    ACTIVE_RUN = folder
    return folder


def guard():
    if not (LAB / '.env').exists():
        raise RuntimeError('Crie .env a partir de .env.example.')
    # Prevent an override from redirecting the orchestrator to another lab.
    if any(os.environ.get(key) for key in ('COMPOSE_FILE', 'COMPOSE_PROJECT_NAME', 'PGHOST', 'PGDATABASE')):
        raise RuntimeError('Remova overrides COMPOSE_FILE/COMPOSE_PROJECT_NAME/PGHOST/PGDATABASE do ambiente.')
    config = json.loads(compose('config', '--format', 'json'))
    if config['name'] != 'pgrl-lab07' or config['services']['client']['environment']['PGDATABASE'] != 'appdb':
        raise RuntimeError('Identidade Compose inesperada.')
    for node in ('pg1', 'pg2'):
        scope = compose('exec', '-T', node, 'sh', '-c', "sed -n '1p' /etc/patroni.yml")
        if scope != 'scope: lab07':
            raise RuntimeError('Scope Patroni inesperado.')
    if scalar('SELECT NOT pg_is_in_recovery()') != 't':
        raise RuntimeError('HAProxy não aponta para o líder.')


def leader():
    nodes = [n for n in ('pg1', 'pg2') if scalar('SELECT NOT pg_is_in_recovery()', node=n) == 't']
    if len(nodes) != 1:
        raise RuntimeError('Esperado exatamente um líder.')
    return nodes[0]


def wait_replica(node):
    lsn = scalar('SELECT pg_current_wal_lsn()', node=node)
    replica = 'pg2' if node == 'pg1' else 'pg1'
    for _ in range(90):
        if scalar(f"SELECT coalesce(pg_last_wal_replay_lsn() >= '{lsn}'::pg_lsn,false)", node=replica) == 't':
            return
        time.sleep(1)
    raise RuntimeError(f'Réplica não alcançou {lsn}.')


def dataset():
    item = js('SELECT row_to_json(d) FROM perf.dataset d')
    if item['state'] != 'ready':
        raise RuntimeError('Dataset incompleto; consulte perf.dataset. Não há limpeza automática.')
    return item['manifest']


def validate(manifest):
    result = js((LAB / 'sql/validate_dataset.sql').read_text(), variables={
        'customers': manifest['customers'], 'reference': manifest['reference']})
    n = manifest['orders']
    if (result['customers'] != manifest['customers'] or result['orders'] != n or result['invalid'] != 0
            or result['statuses'] != {'paid': n * 8 // 10, 'pending': n // 10, 'cancelled': n // 10}
            or result['hot_orders'] != n * 6 // 10):
        raise RuntimeError(f'Dataset inválido: {result}')
    return result


def generate(args):
    guard()
    customers, orders = {'small': (10000, 100000), 'standard': (100000, 1000000)}[args.profile]
    reference = dt.datetime.fromisoformat(args.reference.replace('Z', '+00:00'))
    if reference.tzinfo is None or reference.utcoffset() != dt.timedelta(0) or any((reference.hour, reference.minute, reference.second, reference.microsecond)):
        raise ValueError('--reference deve representar meia-noite UTC.')
    folder = new_run('dataset')
    manifest = dict(profile=args.profile, customers=customers, orders=orders, seed=args.seed,
                    reference=reference.isoformat(), batch_size=args.batch_size, algorithm='integer-v1',
                    git_revision=run(['git', 'rev-parse', 'HEAD']),
                    git_dirty=bool(run(['git', 'status', '--porcelain'])),
                    source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    (folder / 'resources.txt').write_text(run(['sh', '-c', 'getconf _NPROCESSORS_ONLN; free -h; df -h .']) + '\n' + compose('stats', '--no-stream', '--no-trunc'))
    # The committed marker survives an interrupted load, preventing accidental append.
    sql('''BEGIN;
LOCK TABLE perf.dataset, app.customers, app.orders IN ACCESS EXCLUSIVE MODE;
DO $$ BEGIN
 IF EXISTS(SELECT FROM perf.dataset) OR EXISTS(SELECT FROM app.customers) OR EXISTS(SELECT FROM app.orders)
 THEN RAISE EXCEPTION 'Dataset já iniciado ou tabelas populadas; nenhuma alteração aplicada'; END IF;
END $$;
INSERT INTO perf.dataset(state,manifest) VALUES ('loading', :'manifest'::jsonb);
COMMIT;''', variables={'manifest': json.dumps(manifest)})
    save(folder / 'manifest.json', manifest)
    started = time.monotonic()
    sql('''INSERT INTO app.customers(customer_id,full_name,email,created_at) OVERRIDING SYSTEM VALUE
SELECT n, 'Customer '||n, 'customer'||n||'@example.com', :'reference'::timestamptz - interval '180 days'
FROM generate_series(1,:customers) n;''', variables=manifest)
    for lo in range(1, orders + 1, args.batch_size):
        hi = min(lo + args.batch_size - 1, orders)
        sql('''INSERT INTO app.orders(order_id,customer_id,order_number,status,total_amount,ordered_at) OVERRIDING SYSTEM VALUE
SELECT n,
 CASE WHEN (n-1)%10 < 6 THEN 1 + (((n-1)/10*6+(n-1)%10+:seed) % (:customers/10))
 ELSE 1 + :customers/10 + (((n-1)/10*4+(n-1)%10-6+:seed) % (:customers*9/10)) END,
 'ORD-'||lpad(n::text,12,'0'),
 CASE WHEN (n-1)%10 < 8 THEN 'paid' WHEN (n-1)%10 = 8 THEN 'pending' ELSE 'cancelled' END,
 (1000 + ((n*104729+:seed)%99000))::numeric/100,
 CASE WHEN n=1 THEN :'reference'::timestamptz - interval '1 day'
 WHEN n=2 THEN :'reference'::timestamptz
 ELSE :'reference'::timestamptz - make_interval(secs => 1+((n*7919+:seed)%15552000)::integer) END
FROM generate_series(:lo::bigint,:hi::bigint) n;''', variables={**manifest, 'lo': lo, 'hi': hi})
        print(f'Pedidos: {hi}/{orders}', flush=True)
    sql("SELECT setval(pg_get_serial_sequence('app.customers','customer_id'), (SELECT max(customer_id) FROM app.customers)); SELECT setval(pg_get_serial_sequence('app.orders','order_id'), (SELECT max(order_id) FROM app.orders)); ANALYZE app.customers; ANALYZE app.orders;")
    result = validate(manifest)
    wait_replica(leader())
    result['duration_seconds'] = time.monotonic() - started
    result['server_version'] = scalar('SELECT version()')
    save(folder / 'validation.json', result)
    sql("UPDATE perf.dataset SET state='ready',finished_at=clock_timestamp() WHERE id;")
    print(f'Dataset validado: {folder}')


def check(args):
    guard()
    node = leader()
    if scalar("SELECT count(*) FROM pg_stat_replication WHERE state='streaming'", node=node) != '1':
        raise RuntimeError('Streaming replication indisponível.')
    for member in ('pg1', 'pg2'):
        if scalar("SELECT current_setting('shared_preload_libraries') LIKE '%pg_stat_statements%' AND current_setting('track_io_timing')='on' AND EXISTS(SELECT FROM pg_extension WHERE extname='pg_stat_statements')", node=member) != 't':
            raise RuntimeError('Instrumentação ausente.')
    count = int(scalar('SELECT count(*) FROM perf.dataset'))
    if count:
        manifest = dataset()
        print(json.dumps(validate(manifest), indent=2))
        wait_replica(node)
    elif scalar('SELECT (SELECT count(*) FROM app.orders)+(SELECT count(*) FROM app.customers)') != '0':
        raise RuntimeError('Dados sem manifesto.')
    else:
        print('Ambiente vazio: nenhuma geração executada.')
    # Reuse lab06 end-to-end telemetry checks without its assumptions about seed counts.
    compose('exec', '-T', 'client', 'pgbench', '--version')
    def http(url, *params):
        return compose('exec', '-T', 'client', 'curl', '-fsS', '--retry', '20', '--retry-delay', '2', '--retry-connrefused', '--max-time', '5', *params, url)
    for _ in range(45):
        metrics = json.loads(http('http://prometheus:9090/api/v1/query', '--get', '--data-urlencode', 'query=count(pg_up == 1)'))
        leaders = json.loads(http('http://prometheus:9090/api/v1/query', '--get', '--data-urlencode', 'query=sum(patroni_primary)'))
        if metrics['data']['result'] and leaders['data']['result'] and metrics['data']['result'][0]['value'][1] == '2' and leaders['data']['result'][0]['value'][1] == '1':
            break
        time.sleep(2)
    else:
        raise RuntimeError('Métricas indisponíveis.')
    rules = http('http://prometheus:9090/api/v1/rules')
    if not all(rule in rules for rule in ('PostgreSQLExporterDown', 'PatroniLeaderMissing', 'ReplicationLagHigh')):
        raise RuntimeError('Regras ausentes.')
    http('http://loki:3100/ready')
    health = json.loads(http('http://grafana:3000/api/health'))
    if health['database'] != 'ok':
        raise RuntimeError('Grafana indisponível.')
    dashboard = compose('exec', '-T', 'client', 'sh', '-c', 'curl -fsS --max-time 10 -u "admin:$GRAFANA_ADMIN_PASSWORD" http://grafana:3000/api/dashboards/uid/postgresql-reliability-overview')
    if 'postgresql-reliability-overview' not in dashboard:
        raise RuntimeError('Dashboard ausente.')
    token = 'lab07_check_' + str(time.time_ns())
    sql(f'SELECT pg_sleep(0.35) /* {token} */;')
    for _ in range(45):
        logs = http('http://loki:3100/loki/api/v1/query_range', '--get', '--data-urlencode', 'query={job="postgresql"} |= "' + token + '"', '--data-urlencode', 'limit=10')
        if token in logs:
            break
        time.sleep(2)
    else:
        raise RuntimeError('Log de verificação ausente no Loki.')
    print(f'OK: líder={node}, réplica, instrumentação, métricas, regras, dashboard e log {token}.')


def queries(manifest):
    day = (dt.datetime.fromisoformat(manifest['reference']) - dt.timedelta(days=1)).date().isoformat()
    cases = {}
    for label, customer in [('history_hot', 1), ('history_cold', manifest['customers'])]:
        q = f'SELECT order_id,customer_id,status,total_amount,ordered_at FROM app.orders WHERE customer_id={customer} ORDER BY ordered_at DESC,order_id DESC LIMIT 50'
        cases[label] = (q, q, 'history')
    q = "SELECT order_id,customer_id,status,total_amount,ordered_at FROM app.orders WHERE status='pending' ORDER BY ordered_at,order_id LIMIT 100"
    cases['pending'] = (q, q, 'pending')
    prefix = "SELECT coalesce(sum(total_amount),0) AS revenue FROM app.orders WHERE status='paid' AND "
    cases['daily'] = (prefix + f"ordered_at::date=DATE '{day}'", prefix + f"ordered_at >= TIMESTAMPTZ '{day} 00:00:00+00' AND ordered_at < TIMESTAMPTZ '{day} 00:00:00+00' + interval '1 day'", None)
    return cases


def snapshot(node):
    return js((LAB / 'sql/diagnostics/snapshot.sql').read_text(), node=node)


def plans(query, samples, node):
    # A single connection avoids process/connection startup in server samples.
    explain = 'EXPLAIN (ANALYZE,BUFFERS,SETTINGS,FORMAT JSON) ' + query + ';\n'
    sql('\\o /dev/null\n' + (query + ';\n') * 5, app=True, node=node)
    output = sql(explain * samples, app=True, node=node)
    decoder = json.JSONDecoder()
    records = []
    pos = 0
    while pos < len(output):
        obj, end = decoder.raw_decode(output, pos)
        records.append(obj[0])
        pos = end
        while pos < len(output) and output[pos].isspace():
            pos += 1
    return records


def pgbench(folder, name, query, node, clients, seconds, transactions=None, seed=42, warmup=15):
    workload = folder / (name + '.sql')
    workload.write_text(query + ';\n')
    prefix = '/evidence/' + folder.name + '/' + name
    args = ['exec', '-T', 'client', 'sh', '-c',
            'export PGPASSWORD="$APP_PASSWORD" PGOPTIONS="-c timezone=UTC -c statement_timeout=5000"; exec pgbench "$@"', 'sh',
            '-h', node, '-U', 'app_user', '-d', 'appdb', '-n', '-M', 'simple', '-c', str(clients), '-j', str(min(clients, 4)),
            '--random-seed=' + str(seed), '-f', prefix + '.sql']
    warm = compose(*args, '-T', str(warmup), timeout=warmup+30)
    (folder / (name + '.warmup.txt')).write_text(warm)
    # Writes use zero warmup mutations: warmup must be read-only for equivalent bases.
    command = args + ['-l', '--log-prefix=' + prefix]
    command += ['-t', str(transactions)] if transactions else ['-T', str(seconds)]
    started = time.monotonic()
    output = compose(*command, timeout=max(180, seconds + 60))
    (folder / (name + '.txt')).write_text(output)
    if not re.search(r'number of failed transactions:\s+0\b', output):
        raise RuntimeError(f'Falhas no pgbench: {name}; veja {folder}')
    latencies = []
    for path in folder.glob(name + '.*'):
        if not path.name.rsplit('.', 1)[-1].isdigit():
            continue
        for line in path.read_text().splitlines():
            fields = line.split()
            if len(fields) >= 3:
                latencies.append(float(fields[2]) / 1000)
    if not latencies:
        raise RuntimeError('pgbench não produziu amostras de latência.')
    return dict(clients=clients, elapsed_seconds=time.monotonic()-started, latency_ms=latencies,
                tps=float(re.search(r'tps = ([0-9.]+)', output).group(1)), failures=0)


def benchmark(args):
    guard()
    manifest = dataset()
    validate(manifest)
    node = leader()
    wait_replica(node)
    if scalar("SELECT count(*) FROM pg_indexes WHERE schemaname='app' AND indexname LIKE 'perf_%'") != '0':
        raise RuntimeError('Reverta os índices experimentais antes de começar: sql/optimizations/revert.sql')
    folder = new_run('benchmark')
    metadata = dict(source_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), git_revision=run(['git','rev-parse','HEAD']), manifest=manifest, leader=node, samples=args.samples, seconds=args.seconds, rounds=args.rounds,
                    clients=args.clients, warmup_seconds=args.warmup_seconds, started_utc=dt.datetime.now(dt.timezone.utc).isoformat())
    save(folder / 'metadata.json', metadata)
    (folder / 'resources.txt').write_text(compose('stats', '--no-stream', '--no-trunc'))
    save(folder / 'environment.json', snapshot(node))
    (folder / 'images.json').write_text(compose('images', '--format', 'json'))
    results = {}
    digests = {}
    for name, (before, after, index) in queries(manifest).items():
        results[name] = {}
        # Alternating order across rounds counteracts warm-cache ordering bias.
        for round_no in range(args.rounds):
            for phase in (['baseline', 'optimized'] if round_no % 2 == 0 else ['optimized', 'baseline']):
                sql((LAB / 'sql/optimizations/revert.sql').read_text(), node=node)
                if phase == 'optimized' and index:
                    sql((LAB / f'sql/optimizations/{index}.sql').read_text(), node=node)
                wait_replica(node)
                q = after if phase == 'optimized' else before
                equivalent = scalar(f'SELECT NOT EXISTS ((({before}) EXCEPT ALL ({after})) UNION ALL (({after}) EXCEPT ALL ({before})))', app=True, node=node)
                if equivalent != 't':
                    raise RuntimeError(f'Resultados diferentes: {name}')
                rows = sql(f'SELECT row_to_json(q) FROM ({q}) q', app=True, node=node)
                digest = hashlib.sha256(rows.encode()).hexdigest()
                if name in digests and digests[name] != digest:
                    raise RuntimeError(f'Resultado mudou entre fases: {name}')
                digests[name] = digest
                save(folder / 'result_digests.json', digests)
                label = f'{name}_{phase}_{round_no+1}'
                (folder / (label + '.query.sql')).write_text(q + ';\n')
                save(folder / (label + '.before.json'), snapshot(node))
                records = plans(q, args.samples, node)
                save(folder / (label + '.plans.json'), records)
                concurrent = [pgbench(folder, label + f'_c{c}', q, node, c, args.seconds, seed=manifest['seed'], warmup=args.warmup_seconds) for c in args.clients]
                save(folder / (label + '.after.json'), snapshot(node))
                results[name].setdefault(phase, []).append(dict(round=round_no+1, plans=records, concurrent=concurrent))
                if leader() != node:
                    raise RuntimeError('Líder mudou: rodada inválida.')
                save(folder / 'results.json', results)
                print(f'OK: {label}', flush=True)
        sql((LAB / 'sql/optimizations/revert.sql').read_text(), node=node)
    if args.writes:
        results['write_cost'] = write_cost(folder, node, manifest)
        save(folder / 'results.json', results)
    save(folder / 'final.json', snapshot(node))
    metadata['finished_utc'] = dt.datetime.now(dt.timezone.utc).isoformat()
    save(folder / 'metadata.json', metadata)
    run([sys.executable, str(LAB / 'scripts/report.py'), str(folder)])
    print(f'Relatório: {folder / "report.md"}')


def write_cost(folder, node, manifest):
    # Separate equivalent logged tables; original application data is preserved.
    result = {}
    for phase in ('baseline', 'optimized'):
        table = 'write_' + phase
        if scalar(f"SELECT to_regclass('perf.{table}') IS NOT NULL", node=node) == 't':
            raise RuntimeError('Tabelas de escrita já existem; remova-as explicitamente antes de repetir.')
    for phase in ('baseline', 'optimized'):
        table = 'write_' + phase
        sql(f'''CREATE TABLE perf.{table} (LIKE app.orders INCLUDING ALL);
INSERT INTO perf.{table} OVERRIDING SYSTEM VALUE SELECT * FROM app.orders;
GRANT SELECT,UPDATE ON perf.{table} TO app_user;
ANALYZE perf.{table};''', node=node)
        if phase == 'optimized':
            sql(f"CREATE INDEX ON perf.{table}(customer_id,ordered_at DESC,order_id DESC); CREATE INDEX ON perf.{table}(ordered_at,order_id) WHERE status='pending';", node=node)
        wait_replica(node)
        name = 'write_' + phase
        q = f'\\set oid random(1,{manifest["orders"]})\nUPDATE perf.{table} SET ordered_at=ordered_at+interval \'1 second\' WHERE order_id=:oid'
        # Fixed transaction count and seed; read-only warmup, no timed write warmup.
        result[phase] = pgbench_write(folder, name, q, node, manifest['seed'])
        result[phase]['bytes'] = int(scalar(f"SELECT pg_total_relation_size('perf.{table}')", node=node))
        if leader() != node:
            raise RuntimeError('Líder mudou durante teste de escrita.')
    return result


def pgbench_write(folder, name, query, node, seed):
    (folder / (name + '.sql')).write_text(query + ';\n')
    prefix = '/evidence/' + folder.name + '/' + name
    wal_before = scalar('SELECT pg_current_wal_insert_lsn()', node=node)
    started = time.monotonic()
    output = compose('exec', '-T', 'client', 'sh', '-c', 'export PGPASSWORD="$APP_PASSWORD" PGOPTIONS="-c timezone=UTC -c statement_timeout=5000"; exec pgbench "$@"', 'sh',
                     '-h', node, '-U', 'app_user', '-d', 'appdb', '-n', '-M', 'simple', '-c', '1', '-j', '1', '-t', '1000',
                     '--random-seed=' + str(seed), '-l', '--log-prefix=' + prefix, '-f', prefix + '.sql', timeout=180)
    (folder / (name + '.txt')).write_text(output)
    if not re.search(r'number of failed transactions:\s+0\b', output):
        raise RuntimeError('Falhas na carga de escrita.')
    wal = int(scalar(f"SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),'{wal_before}'::pg_lsn)", node=node))
    values = [float(line.split()[2])/1000 for p in folder.glob(name + '.*') if p.suffix[1:].isdigit() for line in p.read_text().splitlines()]
    return dict(tps=float(re.search(r'tps = ([0-9.]+)', output).group(1)), latency_ms=values,
                transactions=1000, failures=0, wal_cluster_bytes=wal, elapsed_seconds=time.monotonic()-started)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    gen = sub.add_parser('generate')
    gen.add_argument('profile', choices=['small', 'standard'])
    gen.add_argument('--seed', type=int, default=42)
    gen.add_argument('--reference', default='2026-11-01T00:00:00+00:00')
    gen.add_argument('--batch-size', type=int, default=10000)
    sub.add_parser('check')
    bench = sub.add_parser('benchmark')
    bench.add_argument('--samples', type=int, default=30)
    bench.add_argument('--seconds', type=int, default=60)
    bench.add_argument('--rounds', type=int, default=3)
    bench.add_argument('--clients', type=int, nargs='+', default=[1,4,8])
    bench.add_argument('--warmup-seconds', type=int, default=15)
    bench.add_argument('--writes', action='store_true')
    args = parser.parse_args()
    if args.command == 'generate':
        if not 0 <= args.seed <= 1000000 or not 100 <= args.batch_size <= 100000:
            parser.error('seed: 0..1000000; batch-size: 100..100000')
        generate(args)
    elif args.command == 'check':
        check(args)
    else:
        if not 1 <= args.warmup_seconds <= 60 or not 30 <= args.samples <= 1000 or not 1 <= args.seconds <= 300 or not 1 <= args.rounds <= 5 or not args.clients or any(c not in range(1,17) for c in args.clients):
            parser.error('warmup-seconds: 1..60; samples: 30..1000; seconds: 1..300; rounds: 1..5; clients: 1..16')
        benchmark(args)


if __name__ == '__main__':
    try:
        (LAB / 'evidence/runs').mkdir(parents=True, exist_ok=True)
        with (LAB / 'evidence/runs/.operation.lock').open('w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('Outra operação do lab 07 está em execução.')
            main()
    except (RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        if ACTIVE_RUN:
            save(ACTIVE_RUN / 'failure.json', {'error': str(exc), 'time_utc': dt.datetime.now(dt.timezone.utc).isoformat()})
        print(f'ERRO: {exc}', file=sys.stderr)
        sys.exit(1)
