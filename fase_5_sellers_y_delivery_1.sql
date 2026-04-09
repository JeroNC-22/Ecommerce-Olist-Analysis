-- ============================================================
--  PROYECTO: Análisis E-Commerce Olist (Brasil)
--  FASE 5: Análisis de Sellers y Delivery Performance
--  Autor: Jerónimo Núñez Castañeira
--  Herramienta: MySQL
-- ============================================================
-- ÍNDICE
--  1. Métricas generales de entrega
--  2. Distribución de tiempos de entrega
--  3. Impacto de las entregas tardías en el review score
--  4. Review score por rango de días de entrega
--  5. Segmentación de sellers por volumen
--  6. Performance individual de sellers (con volumen significativo)
--  7. Sellers con mejor y peor performance
--  8. Vistas consolidadas para Power BI
-- ============================================================


-- ============================================================
-- 1. MÉTRICAS GENERALES DE ENTREGA
-- Tiempo desde la compra hasta la entrega al cliente.
-- ============================================================

SELECT
    ROUND(AVG(DATEDIFF(order_delivered_customer_date,
                       order_purchase_timestamp)), 1)       AS dias_entrega_promedio,
    ROUND(MIN(DATEDIFF(order_delivered_customer_date,
                       order_purchase_timestamp)), 0)       AS dias_entrega_minimo,
    ROUND(MAX(DATEDIFF(order_delivered_customer_date,
                       order_purchase_timestamp)), 0)       AS dias_entrega_maximo,
    COUNT(*)                                                 AS total_entregados,
    SUM(CASE WHEN order_delivered_customer_date
                  > order_estimated_delivery_date
             THEN 1 ELSE 0 END)                             AS entregas_tardias,
    ROUND(SUM(CASE WHEN order_delivered_customer_date
                        > order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_tardias,
    ROUND(AVG(CASE WHEN order_delivered_customer_date
                        > order_estimated_delivery_date
                   THEN DATEDIFF(order_delivered_customer_date,
                                 order_estimated_delivery_date)
              END), 1)                                       AS desvio_prom_tardias
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

-- Resultado:
-- dias_entrega_promedio: 12.1 días
-- dias_entrega_minimo:    0 días  (mismo día — casos excepcionales)
-- dias_entrega_maximo:  209 días  (outlier extremo)
-- total_entregados:     96.476
-- entregas_tardias:      6.559  (6.8%)
-- desvio_prom_tardias:  10.6 días de retraso promedio en las tardías
--
-- INSIGHT: La mediana es 10 días — más representativa que el promedio
-- porque los outliers de 100+ días inflan la media.
-- Un retraso promedio de 10.6 días cuando se llega tarde
-- es significativo para la experiencia del cliente.


-- ============================================================
-- 2. DISTRIBUCIÓN DE TIEMPOS DE ENTREGA
-- Entender en qué rango cae la mayoría de los pedidos.
-- ============================================================

SELECT
    CASE
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) BETWEEN 0  AND 7  THEN '1. 1-7 días'
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) BETWEEN 8  AND 14 THEN '2. 8-14 días'
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) BETWEEN 15 AND 21 THEN '3. 15-21 días'
        WHEN DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) BETWEEN 22 AND 30 THEN '4. 22-30 días'
        ELSE                                                                                           '5. 30+ días'
    END                                                      AS rango_entrega,
    COUNT(*)                                                  AS pedidos,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)       AS pct_pedidos
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
ORDER BY rango_entrega;

-- Resultado:
-- 1-7 días:   33.683 (34.9%) ← entregas rápidas
-- 8-14 días:  36.397 (37.7%) ← rango más frecuente
-- 15-21 días: 15.369 (15.9%)
-- 22-30 días:  6.891 ( 7.1%)
-- 30+ días:    4.117 ( 4.3%) ← experiencia muy negativa
--
-- INSIGHT: El 72.6% de las entregas llega en menos de 14 días.
-- Sin embargo, el 4.3% (4.117 pedidos) supera los 30 días —
-- estos casos casi con certeza generan reviews negativos.


-- ============================================================
-- 3. IMPACTO DE LAS ENTREGAS TARDÍAS EN EL REVIEW SCORE
-- Este es el análisis más poderoso de la fase:
-- cuantificamos cuánto daña una entrega tardía la satisfacción.
-- ============================================================

SELECT
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date
        THEN 'A tiempo'
        ELSE 'Tardía'
    END                                                      AS tipo_entrega,
    COUNT(DISTINCT o.order_id)                               AS pedidos,
    ROUND(AVG(r.review_score), 2)                           AS score_promedio,
    SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END)    AS score_5,
    SUM(CASE WHEN r.review_score = 4 THEN 1 ELSE 0 END)    AS score_4,
    SUM(CASE WHEN r.review_score = 3 THEN 1 ELSE 0 END)    AS score_3,
    SUM(CASE WHEN r.review_score = 2 THEN 1 ELSE 0 END)    AS score_2,
    SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END)    AS score_1
FROM olist_orders_dataset o
INNER JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY tipo_entrega;

-- Resultado:
-- A tiempo: score promedio 4.29 ← satisfacción alta
-- Tardía:   score promedio 2.27 ← satisfacción muy baja
--
-- INSIGHT CLAVE: Una entrega tardía destruye la satisfacción.
-- La diferencia de 2 puntos en el score (4.29 vs 2.27) es enorme.
-- Esto significa que la logística no es solo un costo operativo —
-- es el principal driver de la experiencia del cliente.


-- ============================================================
-- 4. REVIEW SCORE POR RANGO DE DÍAS DE ENTREGA
-- Vemos cómo cae el score a medida que pasan más días.
-- ============================================================

SELECT
    CASE
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) BETWEEN 0  AND 7  THEN '1. 1-7 días'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) BETWEEN 8  AND 14 THEN '2. 8-14 días'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) BETWEEN 15 AND 21 THEN '3. 15-21 días'
        WHEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) BETWEEN 22 AND 30 THEN '4. 22-30 días'
        ELSE                                                                                               '5. 30+ días'
    END                                                      AS rango_entrega,
    COUNT(DISTINCT o.order_id)                               AS pedidos,
    ROUND(AVG(r.review_score), 2)                           AS score_promedio
FROM olist_orders_dataset o
INNER JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY rango_entrega
ORDER BY rango_entrega;

-- Resultado — degradación progresiva del score:
-- 1-7 días:   4.41 ⭐⭐⭐⭐⭐
-- 8-14 días:  4.29 ⭐⭐⭐⭐
-- 15-21 días: 4.10 ⭐⭐⭐⭐
-- 22-30 días: 3.49 ⭐⭐⭐
-- 30+ días:   2.18 ⭐⭐
--
-- INSIGHT: La caída más abrupta ocurre después de los 22 días.
-- Los pedidos que superan los 30 días promedian apenas 2.18/5 —
-- prácticamente garantizan una mala experiencia.
-- Existe un "punto de quiebre" claro entre 21 y 22 días.


-- ============================================================
-- 5. SEGMENTACIÓN DE SELLERS POR VOLUMEN
-- No todos los sellers son iguales — los clasificamos
-- según su nivel de actividad para entender la estructura
-- del marketplace.
-- ============================================================

WITH ventas_por_seller AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT oi.order_id)     AS pedidos,
        ROUND(SUM(oi.price), 2)         AS revenue,
        COUNT(oi.order_item_id)         AS unidades
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.seller_id
)
SELECT
    CASE
        WHEN pedidos BETWEEN 1   AND 10  THEN '1. Micro  (1-10 pedidos)'
        WHEN pedidos BETWEEN 11  AND 50  THEN '2. Pequeño (11-50 pedidos)'
        WHEN pedidos BETWEEN 51  AND 200 THEN '3. Mediano (51-200 pedidos)'
        ELSE                                   '4. Grande (200+ pedidos)'
    END                                                      AS segmento,
    COUNT(*)                                                  AS sellers,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1)       AS pct_sellers,
    ROUND(SUM(revenue), 2)                                   AS revenue_total,
    ROUND(SUM(revenue) * 100.0 / SUM(SUM(revenue)) OVER(), 1) AS pct_revenue
FROM ventas_por_seller
GROUP BY segmento
ORDER BY segmento;

-- Resultado:
-- Micro  (1-10):    1.794 sellers (60.4%) →  9.8% del revenue
-- Pequeño (11-50):   763 sellers (25.7%) → 22.8% del revenue
-- Mediano (51-200):  328 sellers (11.0%) → 31.2% del revenue
-- Grande (200+):      85 sellers ( 2.9%) → 36.2% del revenue
--
-- INSIGHT: Los sellers grandes (solo 85) generan el 36.2% del revenue.
-- El top 10% de sellers concentra el 67.1% del revenue total.
-- Clásica distribución de Pareto en marketplaces.


-- ============================================================
-- 6. PERFORMANCE INDIVIDUAL DE SELLERS
-- Para sellers con volumen significativo (20+ pedidos)
-- calculamos un scorecard completo de performance.
-- ============================================================

WITH seller_stats AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        COUNT(DISTINCT oi.order_id)                          AS pedidos,
        ROUND(SUM(oi.price), 2)                             AS revenue,
        ROUND(AVG(oi.price), 2)                             AS precio_prom,
        ROUND(AVG(r.review_score), 2)                       AS score_prom,
        ROUND(AVG(DATEDIFF(
            o.order_delivered_customer_date,
            o.order_purchase_timestamp)), 1)                 AS dias_entrega_prom,
        ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                            > o.order_estimated_delivery_date
                       THEN 1 ELSE 0 END) * 100.0
              / COUNT(*), 1)                                 AS pct_tardias
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o          ON oi.order_id  = o.order_id
    INNER JOIN olist_sellers_dataset s         ON oi.seller_id = s.seller_id
    LEFT  JOIN olist_order_reviews_dataset r   ON o.order_id   = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id, s.seller_state
    HAVING pedidos >= 20
)
SELECT
    seller_id,
    seller_state,
    pedidos,
    revenue,
    precio_prom,
    score_prom,
    dias_entrega_prom,
    pct_tardias,
    CASE
        WHEN score_prom >= 4.0 AND pct_tardias <= 5  THEN 'Top performer'
        WHEN score_prom >= 3.5 AND pct_tardias <= 15 THEN 'Buen performance'
        WHEN score_prom  < 3.0 OR  pct_tardias >  30 THEN 'Requiere atención'
        ELSE                                               'Performance medio'
    END                                                      AS clasificacion
FROM seller_stats
ORDER BY revenue DESC;

-- Clasificación de sellers:
-- Top performer:      score >= 4.0 y tardías <= 5%
-- Buen performance:   score >= 3.5 y tardías <= 15%
-- Requiere atención:  score < 3.0 O tardías > 30%
-- Performance medio:  el resto


-- ============================================================
-- 7. SELLERS CON MEJOR Y PEOR PERFORMANCE
-- Top 10 y bottom 10 para identificar benchmarks y alertas.
-- ============================================================

-- Top 10 sellers por score (mínimo 20 pedidos)
WITH seller_scores AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        COUNT(DISTINCT oi.order_id)                         AS pedidos,
        ROUND(AVG(r.review_score), 2)                       AS score_prom,
        ROUND(SUM(oi.price), 2)                             AS revenue,
        ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                            > o.order_estimated_delivery_date
                       THEN 1 ELSE 0 END) * 100.0
              / COUNT(*), 1)                                AS pct_tardias
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o        ON oi.order_id  = o.order_id
    INNER JOIN olist_sellers_dataset s       ON oi.seller_id = s.seller_id
    LEFT  JOIN olist_order_reviews_dataset r ON o.order_id   = r.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
    GROUP BY oi.seller_id, s.seller_state
    HAVING pedidos >= 20
)
-- Mejores sellers
SELECT 'Top 10 por score' AS ranking, seller_id, seller_state,
       pedidos, score_prom, pct_tardias, revenue
FROM seller_scores
ORDER BY score_prom DESC, pedidos DESC
LIMIT 10;

-- Sellers con más problemas
SELECT 'Bottom 10 por score' AS ranking, seller_id, seller_state,
       pedidos, score_prom, pct_tardias, revenue
FROM (
    SELECT seller_id, seller_state, pedidos, score_prom, pct_tardias, revenue
    FROM seller_scores
    ORDER BY score_prom ASC, pct_tardias DESC
    LIMIT 10
) bottom_sellers;


-- ============================================================
-- 8. VISTAS CONSOLIDADAS PARA POWER BI
-- ============================================================

-- 8a. Tabla de delivery performance mensual (para gráfico de línea)
SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')         AS mes,
    COUNT(*)                                                   AS total_entregas,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1)       AS dias_entrega_prom,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                        > o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_tardias,
    ROUND(AVG(r.review_score), 2)                             AS score_prom
FROM olist_orders_dataset o
LEFT JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp >= '2017-01-01'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY mes;

-- 8b. Scorecard de sellers (para tabla en Power BI)
SELECT
    oi.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id)                               AS pedidos,
    ROUND(SUM(oi.price), 2)                                  AS revenue,
    ROUND(AVG(r.review_score), 2)                            AS score_prom,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date,
                       o.order_purchase_timestamp)), 1)      AS dias_entrega_prom,
    ROUND(SUM(CASE WHEN o.order_delivered_customer_date
                        > o.order_estimated_delivery_date
                   THEN 1 ELSE 0 END) * 100.0
          / COUNT(*), 1)                                     AS pct_tardias
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o        ON oi.order_id  = o.order_id
INNER JOIN olist_sellers_dataset s       ON oi.seller_id = s.seller_id
LEFT  JOIN olist_order_reviews_dataset r ON o.order_id   = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY oi.seller_id, s.seller_state
HAVING COUNT(DISTINCT oi.order_id) >= 10
ORDER BY revenue DESC;

-- ============================================================
-- FIN FASE 5
-- SQL COMPLETO — 5 fases listas
-- Próximo paso → FASE 6: Dashboard en Power BI (paso a paso)
-- ============================================================
