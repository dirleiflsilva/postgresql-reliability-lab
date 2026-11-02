> Histórico: rascunho anterior à implementação. Consulte o [README atual](README.md) para executar o lab e conhecer as diferenças de escopo.

# Lab 07: Performance — rascunho de implementação

**Status: planejado.** Este documento descreve a implementação proposta; não há scripts executáveis, dados gerados ou resultados de benchmark neste lab. A geração de dados será uma etapa explícita posterior à revisão deste rascunho.

## Objetivo

Diagnosticar consultas custosas, formular hipóteses de otimização e comparar resultados antes e depois, preservando a correção das consultas. O resultado esperado é um experimento reproduzível com planos de execução, estatísticas e custos das mudanças, e não uma promessa de ganho fixo.

## Base existente e decisões propostas

- Evoluir a arquitetura do lab 06: PostgreSQL 16 com dois membros Patroni, etcd, HAProxy e observabilidade. Manter inicialmente as versões usadas naquele lab para reduzir variáveis no experimento.
- Criar um projeto Compose independente (`pgrl-lab07`), com volumes, rede, scope Patroni, namespace e identificadores próprios. Não conectar os scripts aos bancos dos labs anteriores.
- Propor portas locais distintas: PostgreSQL `5441`, Grafana `3001`, Prometheus `9091` e Loki `3101`, configuráveis por `.env`.
- Usar o modelo reduzido do lab 06 (`app.customers` e `app.orders`). O modelo completo do lab 02 fica fora da primeira versão para concentrar os experimentos em consultas e índices.
- Preservar os índices de chave primária, unicidade, `customer_id` e `ordered_at` como baseline. As otimizações serão incrementais sobre esse estado.
- Separar criação de roles, schemas e tabelas da carga. O bootstrap do lab 06 contém `INSERT`s automáticos: eles deverão ser removidos da adaptação do lab 07 antes da primeira subida.
- Reaproveitar `pg_stat_statements`, `track_io_timing`, logs JSON e telemetria do lab 06, verificando sua configuração nos dois membros.
- Usar uma role de aplicação para executar as consultas e uma conexão administrativa separada para carga, DDL e coleta privilegiada. Credenciais virão do `.env`, sem serem incluídas nas evidências.

O gerador atual do lab 06 inclui `pg_sleep` para produzir logs. Ele não será usado como benchmark de performance. A procedure do lab 02 usa loops e `ORDER BY random()`; a nova carga terá geração em conjunto e distribuição controlada.

## Escopo inicial

1. Preparar um ambiente vazio e verificar sua saúde.
2. Gerar uma massa sintética parametrizada, apenas por comando explícito.
3. Medir três consultas representativas sem as otimizações propostas.
4. Aplicar uma mudança por cenário e repetir as medições.
5. Executar uma carga concorrente curta para observar efeitos no serviço.
6. Consolidar resultados, custos, limitações e instruções para repetir o experimento.

Particionamento, pool de conexões, mudanças de versão, tuning global e failover durante o benchmark ficam para extensões posteriores. Configurações como `work_mem` poderão ser exploradas em uma segunda rodada, por sessão, somente se os planos demonstrarem necessidade.

## Massa de dados proposta — ainda não gerar

| Perfil | Clientes | Pedidos | Uso |
|---|---:|---:|---|
| `small` | 10.000 | 100.000 | Validar o fluxo e executar em máquina com menos recursos |
| `standard` | 100.000 | 1.000.000 | Experimento principal, condicionado à capacidade local |

Esses volumes são propostas iniciais. Antes da carga, registrar CPU, memória, espaço livre e limites dos containers. Estimar o espaço de tabelas, índices, WAL e réplica com uma carga piloto explícita; o tamanho real em disco será medido, sem assumir que a contagem de linhas prevê esse custo.

Contrato do futuro gerador:

- Parâmetros: perfil, semente, data de referência fixa e tamanho de lote. Registrar também a versão do algoritmo.
- Dados derivados de identificadores e semente por fórmulas determinísticas; evitar depender de `now()` e de aleatoriedade sem controle.
- Janela temporal de 180 dias, com limites e fuso UTC registrados no manifesto.
- Distribuição proposta: 80% dos pedidos `paid`, 10% `pending` e 10% `cancelled`; 60% dos pedidos concentrados em 10% dos clientes. Validar as proporções efetivas após a carga.
- Valores monetários não negativos, emails e números de pedido únicos, chaves estrangeiras válidas e datas coerentes com a janela.
- Inserções em conjunto, divididas em lotes com progresso e limites explícitos. Não incluir otimizações experimentais durante a carga.
- Rejeitar execução sobre tabelas já populadas. Se houver interrupção, identificar o estado incompleto e exigir recuperação explícita; não truncar nem continuar silenciosamente.
- Executar `ANALYZE` depois da carga e aguardar a réplica alcançar o ponto de WAL registrado ao final antes das medições.
- Emitir manifesto com parâmetros, contagens, distribuição, duração, tamanhos, versão do PostgreSQL e revisão Git.

O perfil `small` valida a execução; ele pode não evidenciar todos os gargalos. A escolha do plano e o ganho observado dependerão da distribuição e da máquina.

## Cenários de otimização

| Cenário | Consulta e hipótese | Mudança candidata | Evidência principal |
|---|---|---|---|
| Histórico de um cliente | Filtrar `customer_id`, ordenar por `ordered_at DESC, order_id DESC` e limitar a 50 pedidos | Índice composto `(customer_id, ordered_at DESC, order_id DESC)` | Linhas examinadas, ordenação, buffers e latência; testar cliente frequente e pouco frequente |
| Fila de pedidos pendentes | Filtrar `status = 'pending'`, ordenar por `ordered_at, order_id` e limitar a 100 | Índice parcial `(ordered_at, order_id) WHERE status = 'pending'` | Seletividade, buffers, latência e tamanho do índice |
| Faturamento diário | Somar `total_amount` de pedidos pagos em um dia usando inicialmente função sobre `ordered_at` | Reescrever o filtro como intervalo semiaberto, mantendo o índice existente em `ordered_at` | Equivalência do resultado, estimativas versus linhas reais, buffers e tempo |

No cenário diário, fixar a sessão em UTC e usar os mesmos limites para as duas consultas, incluindo casos exatamente na abertura e no fechamento do intervalo. No índice parcial, começar com predicado literal e documentar o modo de execução; consultas preparadas com parâmetros exigirão avaliação própria.

Cada cenário partirá do mesmo conjunto de dados e índices de baseline. Remover apenas os índices experimentais conhecidos ao encerrar o cenário, por ação explícita. Não forçar o planner com `enable_seqscan = off` nem tratar um sequential scan como falha por si só.

Depois dos cenários de leitura, medir separadamente o custo dos dois índices candidatos em uma carga curta de inserções/atualizações: throughput, latência, WAL e tamanho. Essa comparação usará bases equivalentes recriadas explicitamente, para que a primeira execução não altere os dados usados pela segunda.

## Protocolo de medição

1. Registrar ambiente, versões, configurações relevantes, índices, manifesto da carga, líder e estado da réplica. Manter iguais recursos, dados e serviços ativos entre as fases.
2. Validar a equivalência dos resultados com comparação SQL bidirecional, incluindo multiplicidade quando aplicável, e ordenação estável para consultas com `LIMIT`.
3. Coletar `EXPLAIN (ANALYZE, BUFFERS, SETTINGS, FORMAT JSON)` para consultas de leitura, antes e depois. `ANALYZE` executa a consulta; usar timeouts e não aplicar esse procedimento indiscriminadamente a escritas.
4. Aquecer cada consulta com cinco execuções descartadas e medir pelo menos 30 execuções por conjunto de parâmetros. Reportar mediana, p95, amostra e dispersão, separando tempo de execução no servidor da latência observada pelo cliente.
5. Coletar snapshots de `pg_stat_statements` em torno de cada janela. Comparar deltas de chamadas, tempo e blocos, verificando reset ou descarte de entradas. Não calcular p95 a partir dessa visão agregada.
6. Executar scripts customizados do `pgbench` sobre as tabelas da aplicação, sem `pgbench -i`. Proposta inicial: 1, 4 e 8 clientes, 15 segundos de aquecimento e três rodadas de 60 segundos por configuração. Guardar logs por transação para calcular percentis.
7. Correlacionar as janelas com conexões, transações, logs, lag da réplica e recursos dos containers. CPU e memória poderão ser coletadas separadamente com `docker stats`; o lab 06 não provisiona um exporter de sistema.
8. Repetir baseline e otimização em ordem alternada quando possível. Não atribuir ao índice o ganho causado apenas por cache aquecido pela construção do próprio índice.

O benchmark concorrente começará com leituras, sem tráfego adicional do gerador do lab 06. A carga de escrita será uma etapa separada. As estatísticas de consulta serão coletadas diretamente do líder identificado; uma troca de líder invalidará a rodada para comparação.

As primeiras execuções frias serão identificadas separadamente. Reiniciar o container não será apresentado como garantia de cache frio do sistema operacional. Os resultados iniciais representarão principalmente o comportamento com cache aquecido.

## Estrutura prevista

```text
labs/07-performance/
├── README.md                       # Este rascunho; depois, instruções executáveis
├── docker-compose.yml              # Ambiente isolado
├── Dockerfile
├── .env.example
├── config/                         # Patroni e HAProxy
├── init/                           # Roles, extensões e DDL, sem carga automática
├── sql/
│   ├── dataset.sql                 # Gerador parametrizado
│   ├── validate_dataset.sql
│   ├── queries/                    # Baseline e versões reescritas
│   ├── optimizations/              # Aplicação e reversão de cada índice
│   └── diagnostics/                # Estatísticas, planos e tamanhos
├── workloads/                      # Scripts customizados do pgbench
├── scripts/
│   ├── _common.sh
│   ├── bootstrap.sh
│   ├── entrypoint.sh
│   ├── status.sh
│   ├── check.sh
│   ├── generate_data.sh
│   ├── benchmark.sh
│   └── report.py
├── observability/                  # Provisionamento adaptado do lab 06
└── evidence/
    ├── runs/                       # Artefatos locais por execução; ignorados no Git
    └── validation.md               # Resultado curado, somente após execução real
```

`benchmark.sh` terá fases explícitas de baseline e otimização, validação de argumentos, limite de duração, timeouts e diretório de saída exclusivo. `check.sh` distinguirá ambiente vazio de dataset carregado e não gerará dados nem iniciará benchmarks implicitamente. O relatório poderá usar a biblioteca padrão do Python para reduzir dependências.

## Ordem de implementação

1. **Preparação sem dados:** criar Compose, configuração, bootstrap somente com DDL, credenciais parametrizadas e verificações estáticas. Confirmar ausência de chamadas de seed herdadas.
2. **Instrumentação:** implementar diagnósticos, consultas, workload, coleta e relatório; verificar sintaxe e disponibilidade de `pgbench` na imagem cliente.
3. **Gerador e validação:** implementar o contrato da carga e revisar limites, isolamento e comportamento em falha antes de executar qualquer geração.
4. **Execução futura:** subir o ambiente vazio, conferir recursos e identidade do lab, executar explicitamente o piloto/perfil escolhido e validar os dados.
5. **Experimentos:** coletar baseline, aplicar e reverter as mudanças por cenário, executar comparações concorrentes e medir custo de escrita.
6. **Entrega:** publicar evidências curadas, explicar resultados e atualizar o status no README principal somente após os critérios de conclusão.

Neste momento, a entrega termina no rascunho. Nenhuma dessas etapas operacionais foi executada.

## Critérios de conclusão do lab

- Ambiente reproduzível com armazenamento independente e bootstrap sem carga automática.
- Gerador explícito, parametrizado e protegido contra execução sobre uma base populada; manifesto e validações aprovados.
- Três cenários executados com resultados equivalentes e evidências de antes/depois.
- Relatório com planos JSON, estatísticas, latências, throughput, falhas, tamanhos e custos de escrita, com condições do experimento registradas.
- Comparações feitas sob as mesmas condições; falhas e timeouts expostos, sem serem excluídos silenciosamente do relatório.
- Pelo menos uma otimização com benefício mensurável e explicável na carga escolhida. Se não houver ganho, revisar a hipótese ou o cenário e registrar a conclusão, sem fabricar evidências nem impor um percentual universal.
- Scripts de diagnóstico e geração não apagam dados implicitamente. Operações de limpeza terão instruções separadas e escopo restrito ao lab 07.
- Documentação final permite reproduzir os resultados e distingue validação funcional de conclusão de performance.

## Referências técnicas

- [PostgreSQL 16 — Using EXPLAIN](https://www.postgresql.org/docs/16/using-explain.html): interpretação de planos e cuidados com a execução instrumentada.
- [PostgreSQL 16 — pg_stat_statements](https://www.postgresql.org/docs/16/pgstatstatements.html): configuração e estatísticas agregadas por consulta.
- [PostgreSQL 16 — pgbench](https://www.postgresql.org/docs/16/pgbench.html): workloads customizados, concorrência e logs das transações.
