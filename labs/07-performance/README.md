# Lab 07: Performance

Este lab evolui o ambiente do lab 06 para investigar consultas, índices e otimização com evidências de antes/depois. Usa PostgreSQL 16, Patroni, etcd e HAProxy, com Prometheus, Grafana e Loki. Os containers, a rede e os volumes pertencem ao projeto **`pgrl-lab07`**; os dados dos labs anteriores não são reutilizados.

O [rascunho original](PLAN.md) foi preservado como histórico de planejamento. Este README descreve o comportamento implementado.

## Preparar o ambiente

Pré-requisitos: Linux, Docker com Compose, Bash, Python 3 no host e recursos para 13 containers. O primeiro build requer internet. Não é necessário instalar bibliotecas Python adicionais. Verifique memória e espaço disponíveis antes de escolher o perfil; não há limites de CPU/memória impostos pelo Compose, então os recursos da máquina influenciam os resultados.

A partir deste diretório:

```bash
cp .env.example .env
# Substitua todas as senhas de exemplo; preserve um .env já existente.
mkdir -p evidence/runs
docker compose config --quiet
docker compose build
docker compose up -d --wait --wait-timeout 300
bash scripts/check.sh
bash scripts/status.sh
```

O bootstrap cria roles, schemas, tabelas e índices de baseline, **sem inserir clientes ou pedidos**. `check.sh` identifica o estado vazio, verifica líder/réplica, instrumentação nos dois membros, exporters, regras de alerta, Grafana/dashboard e ingestão de um log no Loki. Esse check emite uma consulta de 350 ms para verificar os logs; não é um benchmark.

| Serviço | Endereço padrão |
|---|---|
| PostgreSQL via HAProxy | `127.0.0.1:5441`, banco `appdb` |
| Grafana | `http://127.0.0.1:3001`, usuário `admin` |
| Prometheus | `http://127.0.0.1:9091` |
| Loki | `http://127.0.0.1:3101/ready` |

As portas são configuráveis em `.env`. A autenticação PostgreSQL usa as roles `postgres`, `app_user`, `readonly` e `monitor_user`, com senhas do `.env`. A role `app_user` mantém o modelo de permissões herdado do lab 06, incluindo associação a `app_owner`; este não é um exemplo de aplicação com privilégios mínimos.

## Gerar dados explicitamente

```bash
bash scripts/generate_data.sh small
bash scripts/check.sh
```

| Perfil | Clientes | Pedidos |
|---|---:|---:|
| `small` | 10.000 | 100.000 |
| `standard` | 100.000 | 1.000.000 |

Para usar `standard`, comece com um ambiente vazio. A primeira carga pequena serve também como piloto para observar tamanho e consumo de recursos; não é necessário gerar o perfil maior para validar o funcionamento do lab.

Parâmetros opcionais:

```bash
bash scripts/generate_data.sh small \
  --seed 42 --reference 2026-11-01T00:00:00+00:00 --batch-size 10000
```

A data de referência deve ser meia-noite UTC. A semente aceita valores de 0 a 1.000.000; o lote, de 100 a 100.000 linhas. A versão `integer-v1` usa fórmulas inteiras, identificadores explícitos e datas fixas, sem depender de `now()` ou `random()` para gerar os registros.

A carga tem 80% de pedidos `paid`, 10% `pending` e 10% `cancelled`; 60% dos pedidos pertencem aos primeiros 10% dos clientes. São dados didáticos com correlações entre campos, não uma simulação estatística de tráfego real. A janela cobre os 180 dias anteriores à referência, com dois registros de fronteira: um à meia-noite do dia anterior e outro exatamente na referência.

O gerador:

- Registra recursos, parâmetros, revisão Git, estado de alterações locais e hash do script.
- Trava as tabelas durante a admissão da carga e grava um marcador `loading` em `perf.dataset` antes dos lotes.
- Rejeita uma segunda carga se existir manifesto ou qualquer cliente/pedido; não faz append nem limpeza automática.
- Valida contagens, distribuição, datas, valores e integridade; atualiza as sequences de identidade e executa `ANALYZE`.
- Aguarda a réplica alcançar o WAL da carga e só então marca o dataset como `ready`.

Se houver interrupção, o marcador permanece e bloqueia novas cargas/benchmarks. Consulte `perf.dataset` e os artefatos da execução. Para uma nova tentativa limpa, use o procedimento explícito de remoção ao final deste documento. Nenhum script trunca os dados implicitamente.

## Executar os experimentos

Validação curta, com duas rodadas em ordem alternada:

```bash
bash scripts/benchmark.sh \
  --seconds 3 --warmup-seconds 2 --rounds 2 --clients 1 4 --writes
```

Experimento mais longo:

```bash
bash scripts/benchmark.sh --writes
```

Por padrão, são 30 amostras de plano por fase e rodada, três rodadas, 15 segundos de aquecimento e 60 segundos medidos para cada configuração de 1, 4 e 8 clientes. São quatro casos, duas fases e três configurações de concorrência por rodada; reserve pelo menos 90 minutos para a configuração padrão completa. A execução curta valida o fluxo, mas não estabelece capacidade nem SLO.

| Caso | Baseline | Otimização |
|---|---|---|
| `history_hot` | Histórico do cliente 1, até 50 pedidos | Índice `(customer_id, ordered_at DESC, order_id DESC)` |
| `history_cold` | Mesmo histórico para o último cliente | Mesmo índice composto |
| `pending` | Até 100 pendentes, em ordem de data/ID | Índice parcial `(ordered_at, order_id) WHERE status='pending'` |
| `daily` | Receita paga no dia anterior à referência, com `ordered_at::date` | Intervalo semiaberto sobre `ordered_at`, usando o índice existente |

Cada cenário parte dos índices do bootstrap, preservando PKs, unicidade e índices individuais de cliente e data. Os scripts aplicam e removem apenas os índices experimentais `app.perf_orders_history` e `app.perf_orders_pending`. As alterações de índice são feitas pela conexão administrativa. Consultas e `pgbench` usam `app_user` e se conectam diretamente ao líder identificado para evitar que estatísticas sejam divididas entre membros.

O benchmark compara resultados com `EXCEPT ALL` nas duas direções e verifica o hash da saída ordenada entre fases e rodadas. A sessão fica em UTC. A construção do índice e a espera pela réplica ocorrem fora da janela medida. Não se força o planner a escolher índices.

Cada consulta recebe cinco execuções de aquecimento antes dos planos instrumentados. O `pgbench` usa arquivos customizados, modo `simple` e consultas com parâmetros fixos; não executa `pgbench -i`. A fila de pendentes usa predicado literal. O comportamento de prepared statements com planos genéricos não faz parte deste experimento.

Com `--writes`, duas cópias equivalentes dos pedidos são criadas em `perf.write_baseline` e `perf.write_optimized`. A segunda recebe os dois índices candidatos. Cada cópia recebe 1.000 atualizações de data, com um cliente e a mesma semente, sem aquecimento de escrita. São medidos TPS, latência, tamanho e WAL do cluster na janela. Os pedidos originais são preservados. Essa comparação exploratória usa ordem fixa e não mede inserções nem uma carga mista completa.

Operações de geração/check/benchmark são serializadas por um lock local. Não execute cargas externas ou mudanças de configuração durante o experimento. Uma troca de líder detectada invalida a execução. Não há retomada automática de benchmark interrompido.

## Evidências e relatório

Cada execução cria `evidence/runs/<UTC>_<tipo>/`, ignorado pelo Git. Os arquivos incluem:

- `manifest.json` e `validation.json` da geração.
- `metadata.json`, ambiente, imagens Docker e recursos do benchmark.
- Consultas executadas, hashes de resultado e planos JSON completos.
- Snapshots de `pg_stat_statements` e deltas por janela; mudanças de reset/evicção ou contadores decrescentes invalidam o delta.
- Saída e logs por transação do `pgbench`, com amostras de latência.
- `results.json` e `report.md`, com mediana, p95 por nearest-rank, desvio padrão, buffers e throughput.
- `failure.json` em falhas capturadas. A ausência de `finished_utc` no benchmark identifica execução incompleta; os artefatos são preservados.

Para reconstruir um relatório concluído:

```bash
python3 scripts/report.py evidence/runs/<diretorio-do-benchmark>
```

`EXPLAIN ANALYZE` executa e instrumenta a consulta: seus tempos são do servidor e incluem esse custo. As latências do `pgbench` incluem comunicação com o cliente. Não se calcula p95 a partir de `pg_stat_statements`, que contém estatísticas agregadas. Os snapshots também incluem consultas de monitoramento, identificadas pelo texto e pela role; seus deltas não equivalem exclusivamente ao workload.

Os timestamps dos snapshots delimitam as janelas para correlação no Grafana. O dashboard herdado mostra transações, conexões, tamanho, lag e logs; `resources.txt` registra uma amostra de `docker stats`, sem alegar medição contínua de CPU/memória. Prometheus/Loki não incluem aqui um exporter de sistema.

Os resultados iniciais são de cache aquecido. Reiniciar containers não garante cache frio do sistema operacional. Compare condições iguais e avalie custos de escrita/armazenamento junto com ganhos de leitura; um sequential scan pode ser a melhor escolha para a distribuição consultada.

O resultado curado da execução local está em [evidence/validation.md](evidence/validation.md).

## Verificações locais sem containers

```bash
python3 -m unittest discover -s scripts -p 'test_*.py'
python3 -m py_compile scripts/lab.py scripts/report.py
for file in scripts/*.sh; do bash -n "$file"; done
docker compose config --quiet
```

Os testes cobrem cálculo de percentis, deltas de contadores, reset de estatísticas e leitura de JSON multilinha. A execução real valida SQL, geração, replicação, consultas, índices e integração de observabilidade.

## Repetir e limpar

Após uma execução concluída, os índices experimentais são removidos. Se o processo foi interrompido, reverta-os explicitamente antes de repetir:

```bash
docker compose exec -T client psql -X -v ON_ERROR_STOP=1 \
  -f /lab07/sql/optimizations/revert.sql
```

Para repetir somente o teste de escrita, remova explicitamente suas duas cópias. Isto descarta as tabelas de teste de escrita:

```bash
docker compose exec -T client psql -X -v ON_ERROR_STOP=1 \
  -c 'DROP TABLE IF EXISTS perf.write_baseline, perf.write_optimized;'
```

Para parar preservando os dados:

```bash
docker compose stop
```

Para apagar **todos os volumes do lab 07**, incluindo banco, métricas e logs, e depois começar com um ambiente vazio:

```bash
docker compose down -v
docker compose up -d --wait --wait-timeout 300
bash scripts/check.sh
```

Os artefatos em `evidence/runs` ficam no host e são preservados. Não há necessidade de remover volumes para repetir benchmarks de leitura.

## Limites operacionais

As portas publicadas ficam em loopback. Prometheus e Loki não têm autenticação, e os serviços não têm TLS. `.env` e artefatos locais não são versionados; Docker Compose não substitui um gerenciador de secrets. Logs podem conter texto de consultas. O lab mantém a stack do lab 06, incluindo Promtail, para continuidade didática; não pretende definir uma nova arquitetura de coleta de logs para produção.

## Referências

- [PostgreSQL 16 — Using EXPLAIN](https://www.postgresql.org/docs/16/using-explain.html)
- [PostgreSQL 16 — pg_stat_statements](https://www.postgresql.org/docs/16/pgstatstatements.html)
- [PostgreSQL 16 — pgbench](https://www.postgresql.org/docs/16/pgbench.html)
