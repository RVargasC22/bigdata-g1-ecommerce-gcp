#!/usr/bin/env bash
# Governance layer (Dataplex Universal Catalog):
#  1. Data Lineage API: from now on every BigQuery job records its source -> target lineage automatically
#     (events_raw -> fact_eventos -> agg_*; visible in BigQuery > table > Lineage).
#  2. Business glossary: one definition per KPI and concept used in the dashboards.
#  3. Layer labels and descriptions on tables and columns: sql/11_governance.sql.
# Idempotent.
set -euo pipefail
cd "$(dirname "$0")/.."
source config.env

gcloud services enable dataplex.googleapis.com datalineage.googleapis.com datacatalog.googleapis.com \
  --project="$PROJECT_ID"

G=glosario-ecommerce
L=global
gcloud dataplex glossaries describe "$G" --location="$L" --project="$PROJECT_ID" >/dev/null 2>&1 || \
  gcloud dataplex glossaries create "$G" --location="$L" --project="$PROJECT_ID" \
    --display-name="Glosario eCommerce (Grupo 1)" \
    --description="Definiciones de negocio comunes a REES46 y Olist usadas en los tableros."

term() {  # id, display name, definition
  gcloud dataplex glossaries terms describe "$1" --glossary="$G" --location="$L" --project="$PROJECT_ID" \
    >/dev/null 2>&1 && return
  gcloud dataplex glossaries terms create "$1" --glossary="$G" --location="$L" --project="$PROJECT_ID" \
    --parent="projects/$PROJECT_ID/locations/$L/glossaries/$G" --display-name="$2" --description="$3" >/dev/null
  echo "term $1"
}
term evento "Evento" \
  "Interacción de un usuario con un producto en REES46: view, cart, remove_from_cart o purchase. Columna events_raw.event_type."
term sesion "Sesión" \
  "Visita identificada por user_session: agrupa los eventos de un usuario durante una navegación."
term pedido "Pedido" \
  "REES46: sesión con al menos un evento purchase. Olist: un order_id. Es el denominador del costo por pedido."
term embudo-conversion "Embudo de conversión" \
  "Sesiones que llegan a cada etapa view -> cart -> purchase, por categoría común y día (agg_embudo_categoria_dia)."
term tasa-conversion "Tasa de conversión" \
  "Sesiones con purchase dividido entre sesiones con view, por categoría común."
term categoria-comun "Categoría común" \
  "Categoría unificada que permite cruzar REES46 y Olist; mapeo manual en dim_categoria. sin_categoria = producto REES46 sin category_code."
term tiempo-entrega "Tiempo de entrega" \
  "Días entre la compra y la entrega al cliente de un pedido Olist (fact_pedidos.dias_entrega); atrasado si supera la fecha estimada."
term quiebre-stock "Quiebre de stock" \
  "Producto cuya demanda semanal alcanza el stock inicial simulado de 50 unidades (fact_inventario.quiebre)."
term factor-pico "Factor de pico" \
  "Máximo de eventos por minuto de un día dividido entre la mediana por minuto de un día normal (1 al 20 de noviembre de 2019)."
term dato-personal "Dato personal" \
  "Identificador de una persona (events_raw.user_id, olist_customers.customer_unique_id). Protegido con policy tag: solo los lectores autorizados pueden consultarlo."

echo "Gobierno OK: lineage activo, glosario $G"
