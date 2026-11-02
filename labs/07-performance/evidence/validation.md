# Validação do Lab 07

Data: 02/11/2026 (America/Sao_Paulo).

## Ambiente e parâmetros

- Execução local com Docker Compose, projeto `pgrl-lab07`, 13 containers.
- 12 processadores lógicos e aproximadamente 62 GiB de RAM disponíveis no host; sem quotas de recursos nos containers.
- PostgreSQL 16.15 (Debian), Patroni 4.1.0, etcd 3.5.21.
- Stack de observabilidade herdada do lab 06: PostgreSQL Exporter 0.17.1, Prometheus 3.1.0, Grafana 11.4.0, Loki/Promtail 3.3.2.
- Dataset `small`: 10.000 clientes e 100.000 pedidos; semente 42, algoritmo `integer-v1`, referência `2026-11-01T00:00:00+00:00`, lotes de 10.000.
- Distribuição validada: 80.000 pagos, 10.000 pendentes, 10.000 cancelados; 60.000 pedidos nos primeiros 1.000 clientes.
- Tamanho do banco após a carga: 28.752.919 bytes. Após as duas cópias do teste de escrita e demais artefatos: 71.064.599 bytes.
- Líder durante o experimento: `pg1`; réplica em streaming, sem troca de líder detectada.

## Procedimento executado

```bash
docker compose build
docker compose up -d --wait --wait-timeout 300
bash scripts/check.sh                    # Confirma ambiente vazio
bash scripts/generate_data.sh small
bash scripts/check.sh
bash scripts/benchmark.sh --seconds 3 --warmup-seconds 2 --rounds 2 --clients 1 4 --writes
```

Janela do benchmark: **13:10:00 a 13:13:32 UTC**, equivalente a **10:10:00 a 10:13:32 em America/Sao_Paulo**.

Foram feitas duas rodadas por fase, alternando baseline/optimized e optimized/baseline, com 30 planos instrumentados por rodada e cinco consultas de aquecimento antes de cada conjunto de planos. Cada configuração de concorrência teve dois segundos de aquecimento e três segundos medidos. Consultas em UTC e modo simple do pgbench.

## Resultados de leitura

Mediana do tempo de execução instrumentado no servidor, em ms, com 60 amostras por fase. Buffers são blocos compartilhados encontrados em cache; a mediana de blocos lidos foi zero nestas janelas.

| Caso | Baseline ms | Otimizado ms | Buffers hit, mediana |
|---|---:|---:|---|
| history_hot | 0.059 | 0.062 | 62 → 62 |
| history_cold | 0.018 | 0.018 | 6 → 6 |
| pending | 0.285 | 0.045 | 1017 → 102 |
| daily | 12.157 | 0.150 | 1042 → 61 |

O índice parcial reduziu o trabalho da consulta de pendentes. A reescrita do filtro diário permitiu restringir o acesso por intervalo, com queda nos buffers e no tempo observado. O índice composto de histórico não apresentou benefício relevante neste perfil: o conjunto por cliente já era pequeno. Esses resultados não justificam manter esse índice apenas com base nesta carga.

Os resultados das consultas foram equivalentes nas comparações SQL bidirecionais e nos hashes entre fases/rodadas. Não houve falhas nas transações medidas pelo pgbench. Todos os 16 deltas de estatísticas foram válidos, sem reset/evicção detectado nas janelas.

## Custo de escrita

Duas tabelas inicialmente equivalentes, com e sem os dois índices candidatos; 1.000 atualizações de data por tabela, um cliente e semente 42. A comparação após as atualizações confirmou que as duas tabelas terminaram com o mesmo conteúdo.

| Fase | Mediana cliente ms | TPS | WAL cluster bytes | Tabela + índices bytes |
|---|---:|---:|---:|---:|
| baseline | 1.921 | 512.44 | 500224 | 18874368 |
| optimized | 1.993 | 490.60 | 587832 | 23289856 |

A execução com índices produziu mais WAL e ocupou mais espaço. A diferença de throughput foi pequena nesta amostra. A ordem de escrita foi fixa, sem aquecimento, e WAL inclui atividade de todo o cluster; não se atribui toda a diferença exclusivamente aos índices.

## Verificações adicionais

- Segunda tentativa de geração rejeitada com `Dataset já iniciado ou tabelas populadas`; nenhum cliente/pedido adicional foi inserido.
- Dados originais preservados em 10.000 clientes e 100.000 pedidos após o benchmark de escrita.
- Índices experimentais removidos ao final; índices de baseline preservados.
- Check final aprovado para banco, réplica, instrumentação, dois exporters, líder observado, regras de alerta, Loki, Grafana e dashboard.
- Consulta de verificação encontrada no Loki com token `lab07_check_1793625391542596984`.
- Cinco testes unitários aprovados para percentis, deltas, resets, contadores decrescentes e JSON multilinha.
- Sintaxe Python/Bash e configuração Compose validadas; argumentos de lote, amostras e clientes inválidos rejeitados antes de acessar o Docker.

## Artefatos e limites

Artefatos locais completos em `evidence/runs/20261102T131000.678818Z_benchmark/`: relatório Markdown, resultados JSON, planos, consultas, snapshots/deltas, imagens Docker, logs por transação e verificações finais. Manifesto da carga em `evidence/runs/20261102T130835.988699Z_dataset/`. Os diretórios são ignorados pelo Git; este registro é a evidência curada versionada.

Esta validação é curta e usa o perfil pequeno, cache aquecido e parâmetros de consulta fixos. Não valida capacidade sustentada, o perfil `standard`, concorrência de oito clientes ou comportamento sob failover durante a carga. O experimento padrão de 60 segundos por configuração e três rodadas continua disponível para investigação mais longa.

O lab foi deixado ativo após a validação, com os dados, as duas tabelas de escrita e os serviços de observabilidade preservados. As instruções para parar, repetir e remover o ambiente estão no README.
