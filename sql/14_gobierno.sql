-- Governance metadata: layer label (bronze / silver / gold) and business descriptions on every table and on
-- the key columns. Dataplex Universal Catalog harvests BigQuery metadata automatically, so these labels and
-- descriptions are searchable there and sit next to the glossary terms (infra/05_gobierno.sh).
-- CREATE OR REPLACE drops descriptions, so this script runs after every rebuild (bq_load.sh, scheduled query).

-- Bronze: data as received
ALTER TABLE ecommerce.events_raw SET OPTIONS (
  labels = [('capa', 'bronze'), ('fuente', 'rees46')],
  description = 'Eventos de navegación REES46 (oct-dic 2019) tal como llegan: carga batch desde GCS y streaming Pub/Sub -> Dataflow. Particionada por día, clustering por event_type y category_code.');
ALTER TABLE ecommerce.events_raw ALTER COLUMN event_type SET OPTIONS (description = 'Tipo de interacción: view, cart, remove_from_cart o purchase (glosario: Evento).');
ALTER TABLE ecommerce.events_raw ALTER COLUMN user_id SET OPTIONS (description = 'Identificador del usuario. Dato personal: protegido con policy tag; solo lo consultan los lectores autorizados (Fine-Grained Reader).');
ALTER TABLE ecommerce.events_raw ALTER COLUMN user_session SET OPTIONS (description = 'Identificador de la sesión de navegación (glosario: Sesión).');
ALTER TABLE ecommerce.events_raw ALTER COLUMN source SET OPTIONS (description = 'Ruta de ingesta: batch o stream.');
ALTER TABLE ecommerce.events_deadletter SET OPTIONS (
  labels = [('capa', 'bronze'), ('fuente', 'rees46')],
  description = 'Cola de errores (dead-letter) del streaming: mensaje original, error y fecha de los eventos que el UDF rechazó.');
ALTER TABLE ecommerce.olist_orders SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Pedidos Olist (Brasil, 2016-2018), horas en America/Sao_Paulo.');
ALTER TABLE ecommerce.olist_order_items SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Ítems de cada pedido Olist con precio y flete.');
ALTER TABLE ecommerce.olist_products SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Catálogo de productos Olist.');
ALTER TABLE ecommerce.olist_customers SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Clientes Olist. customer_unique_id es dato personal (policy tag).');
ALTER TABLE ecommerce.olist_order_payments SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Pagos de pedidos Olist.');
ALTER TABLE ecommerce.olist_order_reviews SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Reseñas de pedidos Olist.');
ALTER TABLE ecommerce.olist_sellers SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Vendedores Olist.');
ALTER TABLE ecommerce.olist_geolocation SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Códigos postales de Brasil con coordenadas.');
ALTER TABLE ecommerce.olist_category_translation SET OPTIONS (labels = [('capa', 'bronze'), ('fuente', 'olist')], description = 'Traducción de categorías Olist portugués -> inglés.');

-- Silver: cleaned and integrated model
ALTER TABLE ecommerce.dim_categoria SET OPTIONS (labels = [('capa', 'silver')], description = 'Mapeo manual de categorías REES46 y Olist a una categoría común (glosario: Categoría común).');
ALTER TABLE ecommerce.dim_fecha SET OPTIONS (labels = [('capa', 'silver')], description = 'Calendario 2016-2019 con fin de semana y eventos comerciales (Black Friday, Cyber Monday).');
ALTER TABLE ecommerce.dim_producto SET OPTIONS (labels = [('capa', 'silver'), ('fuente', 'rees46')], description = 'Productos REES46 con categoría común y precio mediano.');
ALTER TABLE ecommerce.fact_pedidos SET OPTIONS (labels = [('capa', 'silver'), ('fuente', 'olist')], description = 'Pedidos Olist por categoría con tiempos de entrega en días y horas en UTC. Grano: pedido x categoría. Con row access policy.');
ALTER TABLE ecommerce.fact_pedidos ALTER COLUMN dias_entrega SET OPTIONS (description = 'Días entre la compra y la entrega al cliente (glosario: Tiempo de entrega).');
ALTER TABLE ecommerce.fact_pedidos ALTER COLUMN dias_vs_estimado SET OPTIONS (description = 'Días de entrega real menos estimada; > 0 = pedido atrasado.');
ALTER TABLE ecommerce.fact_inventario SET OPTIONS (labels = [('capa', 'silver'), ('fuente', 'rees46')], description = 'Inventario derivado por producto y día: stock inicial 50 cada lunes menos compras (glosario: Quiebre de stock).');
ALTER TABLE ecommerce.fact_inventario ALTER COLUMN quiebre SET OPTIONS (description = 'true cuando la demanda de la semana alcanza el stock inicial.');

-- Gold: tables read by the dashboards
ALTER TABLE ecommerce.agg_pedidos_hora SET OPTIONS (labels = [('capa', 'gold')], description = 'Pedidos, compras, ingresos y eventos por hora (tablero Pedidos e ingresos).');
ALTER TABLE ecommerce.agg_pedidos_hora ALTER COLUMN pedidos SET OPTIONS (description = 'Sesiones con al menos una compra (glosario: Pedido).');
ALTER TABLE ecommerce.agg_embudo_categoria_dia SET OPTIONS (labels = [('capa', 'gold')], description = 'Embudo view -> cart -> purchase en sesiones por día y categoría (glosario: Embudo de conversión).');
ALTER TABLE ecommerce.agg_entregas_categoria SET OPTIONS (labels = [('capa', 'gold')], description = 'Tiempos de entrega, atrasos y flete por categoría Olist.');
ALTER TABLE ecommerce.agg_demanda_vs_inventario SET OPTIONS (labels = [('capa', 'gold')], description = 'Productos en quiebre y demanda no atendida por día.');
ALTER TABLE ecommerce.agg_conversion_vs_cumplimiento SET OPTIONS (labels = [('capa', 'gold')], description = 'Cruce por categoría común: conversión REES46 vs cumplimiento de entregas Olist.');
ALTER TABLE ecommerce.agg_conversion_vs_cumplimiento ALTER COLUMN tasa_conversion SET OPTIONS (description = 'Sesiones con compra / sesiones con vista (glosario: Tasa de conversión).');
ALTER TABLE ecommerce.agg_patron_horario SET OPTIONS (labels = [('capa', 'gold')], description = 'Pedidos por hora del día y día de la semana en ambas tiendas.');
ALTER MATERIALIZED VIEW ecommerce.mv_eventos_hora SET OPTIONS (labels = [('capa', 'gold')], description = 'Eventos y monto por hora, tipo y fuente (batch/stream); se refresca sola para el tablero en vivo.');
