# Validação — 25–26/09/2026

Ambiente local Linux, Docker Engine 29.8.1, Compose v5.5.1; PostgreSQL 16.15, Patroni 4.1.0, etcd 3.5.21 e HAProxy 3.0.28.

| Execução UTC | Líder anterior | Novo líder | Até escrita confirmada |
|---|---|---|---|
| 20260925T213217Z_19173 | pg1 | pg2 | 21 s |
| 20260925T213322Z_17206 | pg2 | pg1 | 24 s |
| 20260926T113651Z_16192 | pg1 | pg2 | 19 s |

As três execuções de `bash scripts/failover_demo.sh` terminaram com código zero. Foram confirmados:

- Escrita pelo HAProxy antes/depois da interrupção, sem alteração do endpoint.
- Um líder, uma réplica em recovery e streaming assíncrono antes/depois.
- Rejeição de escrita na réplica com SQLSTATE 25006.
- Base com 100 clientes e 500 pedidos; propagação de sentinelas.
- Preservação das sentinelas anterior/posterior e retorno do antigo líder como réplica.
- Saúde dos três membros etcd.

Na primeira execução, o log registrou `pg_rewind exit code=0`, divergência na timeline 1 e retorno de pg1 seguindo pg2. Também foi validada a recriação dos containers com os volumes existentes entre as execuções.

Os arquivos brutos `.txt` e `-containers.log` estão no diretório local `evidence/`, ignorados pelo Git. Este resumo fica versionado. Em 26/09, os cinco volumes do lab foram removidos e recriados: o bootstrap, a carga inicial, o `basebackup` com checkpoint rápido, o check completo e o failover passaram a partir desse estado limpo.

As sentinelas anteriores foram explicitamente reproduzidas antes da falha. Os tempos são medições locais de recuperação de escrita, incluindo reconexões, e não comprovam RPO zero nem constituem SLA. Não foram testadas partições de rede, perda de quorum, falha do host ou do HAProxy.
