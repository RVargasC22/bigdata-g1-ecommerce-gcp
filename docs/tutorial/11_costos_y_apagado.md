# 11. Costos y apagado

## 11.1 Qué cobra por hora y qué cobra por mes

| Recurso | Cobro | Cómo apagarlo |
|---|---|---|
| Jobs de Dataflow (plantilla y Beam) | Por hora de worker, mientras corren | `./streaming/stop_dataflow.sh` (drain) |
| VM de ingesta y VM de replay | Por hora, mientras existan | `gcloud compute instances delete …` |
| Consultas de BigQuery | 6,25 USD por TiB escaneado a precio de lista; el primer TiB del mes es gratis | Tope por llamada (`MAX_BYTES_BILLED`), consultas programadas en pausa |
| Almacenamiento (Cloud Storage y BigQuery) | Unos 2,2 USD al mes por ≈103 GB en BigQuery y 18 GiB en Cloud Storage | Ciclo de vida del bucket, vencimiento de snapshots |
| Pub/Sub | Por volumen publicado; centavos en la demostración | — |

## 11.2 Apagar todo lo que cobra por hora

```bash
./infra/99_teardown.sh
```

El script hace *drain* de los jobs activos en la región principal y en la alterna y borra `ingest-vm` y `replay-beam`.
Los datos (bucket y BigQuery) se conservan. Para borrar **todo**, incluidos los datos:
`gcloud projects delete <PROJECT_ID>`.

Comprobación: `gcloud compute instances list` y `gcloud dataflow jobs list --region=us-central1 --status=active` deben
salir vacías.

## 11.3 Costo real medido

Facturación del 1 al 6 de noviembre de 2026 (reporte de la cuenta de facturación, por SKU): S/ 8,75 brutos (Dataflow
4,32; Compute Engine 2,32; BigQuery 0,88 por *streaming insert*; Dataplex 0,87; redes 0,30; Pub/Sub 0,06). Los créditos
cubrieron todo, así que el neto fue S/ 0,00. Las consultas sumaron 0,88 TiB, dentro del TiB gratuito.

Costo unitario de la demostración: unos 0,0018 USD por cada 1 000 pedidos (`sql/08_cost_per_order.sql`).

## 11.4 Costo de repetir las pruebas de este tutorial

Relanzar la VM y los dos jobs de Dataflow para un replay de 30 minutos cuesta del orden de 1 a 3 soles por la hora
que duran los workers. Recuerda drenar los jobs y borrar las VM al terminar.
