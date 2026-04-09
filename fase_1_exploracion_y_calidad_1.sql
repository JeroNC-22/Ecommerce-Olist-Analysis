-- ============================================================
--  PROYECTO: Análisis E-Commerce Olist (Brasil)
--  FASE 1: Exploración y Calidad de Datos
--  Autor: Jerónimo Núñez Castañeira
--  Herramienta: MySQL
-- ============================================================
-- ÍNDICE
--  1. Volumen de tablas
--  2. Duplicados
--  3. Valores nulos por tabla
--  4. Integridad referencial entre tablas
--  5. Distribución de estados de pedidos
--  6. Distribución de medios de pago
--  7. Pedidos sin pago / sin review / sin ítems
--  8. Análisis de entregas tardías
--  9. Vista resumen de calidad
-- ============================================================


-- ============================================================
-- 1. VOLUMEN DE TABLAS
-- Verificamos que cada tabla tenga los registros esperados
-- ============================================================

SELECT 'orders'         AS tabla, COUNT(*) AS total_filas FROM olist_orders_dataset
UNION ALL
SELECT 'order_items',                COUNT(*)               FROM olist_order_items_dataset
UNION ALL
SELECT 'order_payments',             COUNT(*)               FROM olist_order_payments_dataset
UNION ALL
SELECT 'customers',                  COUNT(*)               FROM olist_customers_dataset
UNION ALL
SELECT 'order_reviews',              COUNT(*)               FROM olist_order_reviews_dataset
UNION ALL
SELECT 'products',                   COUNT(*)               FROM olist_products_dataset
UNION ALL
SELECT 'sellers',                    COUNT(*)               FROM olist_sellers_dataset;

-- Resultado esperado:
-- orders          → 99.441
-- order_items     → 112.650  (un pedido puede tener varios ítems)
-- order_payments  → 103.886  (un pedido puede tener varios pagos)
-- customers       → 99.441
-- order_reviews   → 99.224
-- products        → 32.951
-- sellers         → 3.095


-- ============================================================
-- 2. DUPLICADOS
-- Un order_id debe ser único en orders y customers.
-- En order_items puede repetirse (varios ítems por pedido).
-- ============================================================

-- Duplicados en orders
SELECT order_id, COUNT(*) AS cant
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1;
-- Resultado esperado: 0 filas (sin duplicados)

-- Duplicados en customers
SELECT customer_id, COUNT(*) AS cant
FROM olist_customers_dataset
GROUP BY customer_id
HAVING COUNT(*) > 1;
-- Resultado esperado: 0 filas

-- Clientes únicos vs registros totales
-- Un mismo comprador puede aparecer con distinto customer_id en cada compra.
-- customer_unique_id identifica al comprador real.
SELECT
    COUNT(*)                    AS total_registros,
    COUNT(DISTINCT customer_unique_id) AS clientes_unicos
FROM olist_customers_dataset;
-- total_registros: 99.441 | clientes_unicos: 96.096
-- → Hay ~3.345 clientes que compraron más de una vez


-- ============================================================
-- 3. VALORES NULOS POR TABLA
-- ============================================================

-- Nulos en orders (tabla de hechos principal)
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN order_approved_at           IS NULL THEN 1 ELSE 0 END) AS nulos_aprobacion,
    SUM(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 ELSE 0 END) AS nulos_fecha_carrier,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS nulos_fecha_entrega
FROM olist_orders_dataset;
-- nulos_aprobacion: 160 (0.2%) → pedidos que nunca fueron aprobados
-- nulos_fecha_carrier: 1.783 (1.8%) → aún no despachados al carrier
-- nulos_fecha_entrega: 2.965 (3.0%) → no entregados al cliente aún

-- Nulos en products
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS sin_categoria,
    SUM(CASE WHEN product_weight_g      IS NULL THEN 1 ELSE 0 END) AS sin_peso
FROM olist_products_dataset;
-- sin_categoria: 610 (1.9%) → productos sin categoría asignada
-- sin_peso: 2 (0.01%)       → impacto mínimo

-- Nulos en reviews
-- Nota: es normal que la mayoría no tenga comentario escrito,
-- ya que la review puede ser solo un puntaje numérico.
SELECT
    COUNT(*) AS total,
    SUM(CASE WHEN review_comment_title   IS NULL THEN 1 ELSE 0 END) AS sin_titulo,
    SUM(CASE WHEN review_comment_message IS NULL THEN 1 ELSE 0 END) AS sin_mensaje
FROM olist_order_reviews_dataset;
-- sin_titulo:  87.656 (88.3%) → esperado, el título es opcional
-- sin_mensaje: 58.247 (58.7%) → más de la mitad solo dejó puntaje


-- ============================================================
-- 4. INTEGRIDAD REFERENCIAL ENTRE TABLAS
-- Verificamos que las FK existan en las tablas relacionadas
-- ============================================================

-- Pedidos en order_items sin order_id en orders
SELECT COUNT(DISTINCT oi.order_id) AS items_sin_orden
FROM olist_order_items_dataset oi
LEFT JOIN olist_orders_dataset o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;
-- Resultado esperado: 0

-- Pedidos en payments sin order_id en orders
SELECT COUNT(DISTINCT op.order_id) AS pagos_sin_orden
FROM olist_order_payments_dataset op
LEFT JOIN olist_orders_dataset o ON op.order_id = o.order_id
WHERE o.order_id IS NULL;
-- Resultado esperado: 0

-- Pedidos en reviews sin order_id en orders
SELECT COUNT(DISTINCT r.order_id) AS reviews_sin_orden
FROM olist_order_reviews_dataset r
LEFT JOIN olist_orders_dataset o ON r.order_id = o.order_id
WHERE o.order_id IS NULL;
-- Resultado esperado: 0


-- ============================================================
-- 5. DISTRIBUCIÓN DE ESTADOS DE PEDIDOS
-- ============================================================

SELECT
    order_status,
    COUNT(*)                                   AS cantidad,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS porcentaje
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY cantidad DESC;

-- Resultado:
-- delivered    → 96.478 (97.0%) ← mayoría entregada con éxito
-- shipped      →  1.107 ( 1.1%)
-- canceled     →    625 ( 0.6%)
-- unavailable  →    609 ( 0.6%)
-- invoiced     →    314 ( 0.3%)
-- processing   →    301 ( 0.3%)
-- created      →      5 ( 0.0%)
-- approved     →      2 ( 0.0%)


-- ============================================================
-- 6. DISTRIBUCIÓN DE MEDIOS DE PAGO
-- ============================================================

SELECT
    payment_type,
    COUNT(DISTINCT order_id)                   AS pedidos,
    ROUND(COUNT(DISTINCT order_id) * 100.0
          / SUM(COUNT(DISTINCT order_id)) OVER(), 2) AS porcentaje,
    ROUND(AVG(payment_value), 2)               AS ticket_promedio
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY pedidos DESC;

-- Resultado:
-- credit_card → 76.795 (76.4%) | ticket: ~163
-- boleto      → 19.784 (19.7%) | ticket: ~146
-- voucher     →  5.775 ( 5.7%) | ticket:  ~65 (descuentos)
-- debit_card  →  1.529 ( 1.5%) | ticket: ~142
-- not_defined →      3 ( 0.0%) ← registros a ignorar en análisis


-- ============================================================
-- 7. PEDIDOS SIN PAGO / SIN REVIEW / SIN ÍTEMS
-- Detectamos registros huérfanos o incompletos
-- ============================================================

-- Pedidos sin ningún pago registrado
SELECT COUNT(*) AS pedidos_sin_pago
FROM olist_orders_dataset o
WHERE NOT EXISTS (
    SELECT 1
    FROM olist_order_payments_dataset op
    WHERE op.order_id = o.order_id
);
-- Resultado: 1 pedido → anomalía puntual, impacto mínimo

-- Pedidos sin review
SELECT COUNT(*) AS pedidos_sin_review
FROM olist_orders_dataset o
WHERE NOT EXISTS (
    SELECT 1
    FROM olist_order_reviews_dataset r
    WHERE r.order_id = o.order_id
);
-- Resultado: 768 pedidos → 0.8% del total, aceptable

-- Pedidos sin ítems
SELECT COUNT(*) AS pedidos_sin_items
FROM olist_orders_dataset o
WHERE NOT EXISTS (
    SELECT 1
    FROM olist_order_items_dataset oi
    WHERE oi.order_id = o.order_id
);
-- Resultado: 775 pedidos → coincide con pedidos en estados
-- no completados (canceled, unavailable, etc.)


-- ============================================================
-- 8. ANÁLISIS DE ENTREGAS TARDÍAS
-- Comparamos fecha real vs fecha estimada de entrega
-- Solo sobre pedidos efectivamente entregados
-- ============================================================

SELECT
    COUNT(*)                                             AS total_entregados,
    SUM(CASE WHEN order_delivered_customer_date
                  > order_estimated_delivery_date
             THEN 1 ELSE 0 END)                         AS entregas_tardias,
    ROUND(
        SUM(CASE WHEN order_delivered_customer_date
                      > order_estimated_delivery_date
                 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2
    )                                                    AS pct_tardias,
    ROUND(AVG(
        DATEDIFF(order_delivered_customer_date,
                 order_estimated_delivery_date)
    ), 1)                                                AS dias_desvio_promedio
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

-- Resultado:
-- total_entregados:    96.476
-- entregas_tardias:     7.827
-- pct_tardias:          8.1%  ← 1 de cada 12 pedidos llega tarde
-- dias_desvio_promedio: varía (a calcular en MySQL)

-- Desglose de tardías por magnitud del retraso
SELECT
    CASE
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) BETWEEN 1  AND 3  THEN '1-3 días'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) BETWEEN 4  AND 7  THEN '4-7 días'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) BETWEEN 8  AND 15 THEN '8-15 días'
        WHEN DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date) > 15             THEN 'más de 15 días'
    END AS rango_retraso,
    COUNT(*) AS cantidad
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date > order_estimated_delivery_date
GROUP BY rango_retraso
ORDER BY MIN(DATEDIFF(order_delivered_customer_date, order_estimated_delivery_date));


-- ============================================================
-- 9. VISTA RESUMEN DE CALIDAD
-- Tabla ejecutiva con los hallazgos principales de calidad
-- Útil para documentar y presentar en el portfolio
-- ============================================================

SELECT 'Total pedidos'                  AS metrica, COUNT(*)    AS valor, '' AS observacion
FROM olist_orders_dataset
UNION ALL
SELECT 'Pedidos entregados',            COUNT(*),   '97.0% del total'
FROM olist_orders_dataset WHERE order_status = 'delivered'
UNION ALL
SELECT 'Pedidos cancelados',            COUNT(*),   '0.6% — impacto bajo'
FROM olist_orders_dataset WHERE order_status = 'canceled'
UNION ALL
SELECT 'Pedidos sin pago',              COUNT(*),   'Anomalía puntual'
FROM olist_orders_dataset o
WHERE NOT EXISTS (SELECT 1 FROM olist_order_payments_dataset op WHERE op.order_id = o.order_id)
UNION ALL
SELECT 'Pedidos sin review',            COUNT(*),   '0.8% — aceptable'
FROM olist_orders_dataset o
WHERE NOT EXISTS (SELECT 1 FROM olist_order_reviews_dataset r WHERE r.order_id = o.order_id)
UNION ALL
SELECT 'Productos sin categoría',       COUNT(*),   '1.9% — excluir en análisis de categorías'
FROM olist_products_dataset WHERE product_category_name IS NULL
UNION ALL
SELECT 'Entregas tardías',              COUNT(*),   '8.1% de los entregados'
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date > order_estimated_delivery_date;

-- ============================================================
-- FIN FASE 1
-- Próximo paso → FASE 2: Métricas Core del Negocio
-- ============================================================
