-- ============================================================
--  PROYECTO: Análisis E-Commerce Olist (Brasil)
--  FASE 4: Análisis Geográfico y de Productos
--  Autor: Jerónimo Núñez Castañeira
--  Herramienta: MySQL
-- ============================================================
-- ÍNDICE
--  1. Revenue y pedidos por estado (clientes)
--  2. Concentración geográfica — regla 80/20
--  3. Revenue por estado (vendedores)
--  4. Flujo comprador vs vendedor por estado
--  5. Top categorías por revenue
--  6. Top categorías por volumen de unidades
--  7. Categorías de ticket alto vs volumen alto
--  8. Top productos individuales
--  9. Vistas consolidadas para Power BI
-- ============================================================


-- ============================================================
-- 1. REVENUE Y PEDIDOS POR ESTADO (CLIENTES)
-- Analizamos desde dónde compran los clientes.
-- ============================================================

SELECT
    c.customer_state                                        AS estado,
    COUNT(DISTINCT o.order_id)                              AS pedidos,
    COUNT(DISTINCT c.customer_unique_id)                    AS clientes_unicos,
    ROUND(SUM(op.payment_value), 2)                        AS revenue,
    ROUND(AVG(op.payment_value), 2)                        AS ticket_promedio,
    ROUND(SUM(op.payment_value) * 100.0
          / SUM(SUM(op.payment_value)) OVER(), 1)          AS pct_revenue
FROM olist_orders_dataset o
INNER JOIN olist_customers_dataset c       ON o.customer_id  = c.customer_id
INNER JOIN olist_order_payments_dataset op ON o.order_id     = op.order_id
WHERE o.order_status = 'delivered'
  AND op.payment_type != 'not_defined'
GROUP BY c.customer_state
ORDER BY revenue DESC;

-- Resultado top 10:
-- SP → R$5.77M (37.4%) | 40.500 pedidos
-- RJ → R$2.06M (13.3%) | 12.350 pedidos
-- MG → R$1.82M (11.8%) | 11.354 pedidos
-- RS → R$  862K ( 5.6%) |  5.345 pedidos
-- PR → R$  782K ( 5.1%) |  4.923 pedidos
-- SC → R$  595K ( 3.9%) |  3.546 pedidos
-- BA → R$  591K ( 3.8%) |  3.256 pedidos
-- DF → R$  346K ( 2.2%) |  2.080 pedidos
-- GO → R$  334K ( 2.2%) |  1.957 pedidos
-- ES → R$  318K ( 2.1%) |  1.995 pedidos


-- ============================================================
-- 2. CONCENTRACIÓN GEOGRÁFICA — REGLA 80/20
-- ¿Cuántos estados concentran el 80% del revenue?
-- ============================================================

WITH revenue_por_estado AS (
    SELECT
        c.customer_state                                    AS estado,
        ROUND(SUM(op.payment_value), 2)                    AS revenue
    FROM olist_orders_dataset o
    INNER JOIN olist_customers_dataset c       ON o.customer_id = c.customer_id
    INNER JOIN olist_order_payments_dataset op ON o.order_id    = op.order_id
    WHERE o.order_status = 'delivered'
      AND op.payment_type != 'not_defined'
    GROUP BY c.customer_state
),
acumulado AS (
    SELECT
        estado,
        revenue,
        SUM(revenue) OVER (ORDER BY revenue DESC)           AS revenue_acumulado,
        SUM(revenue) OVER ()                                AS revenue_total
    FROM revenue_por_estado
)
SELECT
    estado,
    revenue,
    ROUND(revenue * 100.0 / revenue_total, 1)              AS pct_individual,
    ROUND(revenue_acumulado * 100.0 / revenue_total, 1)    AS pct_acumulado
FROM acumulado
ORDER BY revenue DESC;

-- INSIGHT: Los primeros 5 estados (SP, RJ, MG, RS, PR)
-- concentran el 73.2% del revenue total.
-- Solo SP representa el 37.4% — una dependencia muy alta
-- de un único mercado. El sur y sudeste dominan completamente.
-- Los estados del norte y nordeste tienen penetración mínima,
-- lo que puede representar una oportunidad de expansión.


-- ============================================================
-- 3. REVENUE POR ESTADO (VENDEDORES)
-- ¿Desde dónde venden los sellers?
-- ============================================================

SELECT
    s.seller_state                                          AS estado_vendedor,
    COUNT(DISTINCT s.seller_id)                             AS sellers,
    ROUND(SUM(oi.price), 2)                                AS revenue_generado,
    ROUND(SUM(oi.price) * 100.0
          / SUM(SUM(oi.price)) OVER(), 1)                  AS pct_revenue,
    ROUND(AVG(oi.price), 2)                                AS precio_prom_item
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o  ON oi.order_id  = o.order_id
INNER JOIN olist_sellers_dataset s ON oi.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_state
ORDER BY revenue_generado DESC;

-- Resultado top 5:
-- SP → 1.769 sellers | R$8.51M (55.2%) ← altísima concentración
-- PR →   335 sellers | R$1.23M ( 8.0%)
-- MG →   236 sellers | R$  978K ( 6.3%)
-- RJ →   163 sellers | R$  821K ( 5.3%)
-- SC →   184 sellers | R$  614K ( 4.0%)


-- ============================================================
-- 4. FLUJO COMPRADOR VS VENDEDOR POR ESTADO
-- Comparamos dónde se origina la demanda vs la oferta.
-- Estados "importadores": compran más de lo que venden.
-- Estados "exportadores": venden más de lo que compran.
-- ============================================================

WITH compradores AS (
    SELECT c.customer_state AS estado,
           ROUND(SUM(op.payment_value), 2) AS revenue_compras
    FROM olist_orders_dataset o
    INNER JOIN olist_customers_dataset c       ON o.customer_id = c.customer_id
    INNER JOIN olist_order_payments_dataset op ON o.order_id    = op.order_id
    WHERE o.order_status = 'delivered'
      AND op.payment_type != 'not_defined'
    GROUP BY c.customer_state
),
vendedores AS (
    SELECT s.seller_state AS estado,
           ROUND(SUM(oi.price), 2) AS revenue_ventas
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o  ON oi.order_id  = o.order_id
    INNER JOIN olist_sellers_dataset s ON oi.seller_id = s.seller_id
    WHERE o.order_status = 'delivered'
    GROUP BY s.seller_state
)
SELECT
    COALESCE(c.estado, v.estado)    AS estado,
    COALESCE(c.revenue_compras, 0)  AS revenue_compras,
    COALESCE(v.revenue_ventas, 0)   AS revenue_ventas,
    ROUND(COALESCE(c.revenue_compras, 0)
        - COALESCE(v.revenue_ventas, 0), 2) AS balance
FROM compradores c
LEFT JOIN vendedores v ON c.estado = v.estado
ORDER BY balance DESC;

-- INSIGHT:
-- Estados con balance POSITIVO (importadores netos — compran más de lo que venden):
--   RJ, MG, RS, PR, SC → son grandes mercados consumidores
-- Estados con balance NEGATIVO (exportadores netos — venden más de lo que compran):
--   SP → genera mucho más revenue como vendedor que como comprador
-- Esto confirma que SP es el hub logístico y comercial del e-commerce brasileño.


-- ============================================================
-- 5. TOP CATEGORÍAS POR REVENUE
-- ============================================================

SELECT
    COALESCE(t.product_category_name_english, 'Sin categoría') AS categoria,
    COUNT(oi.order_item_id)                                      AS unidades_vendidas,
    ROUND(SUM(oi.price), 2)                                     AS revenue,
    ROUND(SUM(oi.price) * 100.0
          / SUM(SUM(oi.price)) OVER(), 1)                       AS pct_revenue,
    ROUND(AVG(oi.price), 2)                                     AS precio_promedio
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o             ON oi.order_id   = o.order_id
INNER JOIN olist_products_dataset p           ON oi.product_id = p.product_id
LEFT  JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY categoria
ORDER BY revenue DESC
LIMIT 15;

-- Top 5 por revenue:
-- health_beauty        → R$1.23M (8.0%) | precio prom R$130
-- watches_gifts        → R$1.17M (7.6%) | precio prom R$199  ← ticket alto
-- bed_bath_table       → R$1.02M (6.6%) | precio prom R$ 93
-- sports_leisure       → R$  955K (6.2%) | precio prom R$113
-- computers_accessories→ R$  889K (5.8%) | precio prom R$116
--
-- INSIGHT: Las top 5 categorías concentran el 40.4% del revenue.
-- "watches_gifts" tiene el precio promedio más alto entre las top 5 (R$199),
-- lo que la hace estratégicamente importante a pesar de menor volumen.


-- ============================================================
-- 6. TOP CATEGORÍAS POR VOLUMEN DE UNIDADES
-- El ranking por unidades es diferente al de revenue.
-- Esto revela qué categorías tienen alta rotación pero bajo margen.
-- ============================================================

SELECT
    COALESCE(t.product_category_name_english, 'Sin categoría') AS categoria,
    COUNT(oi.order_item_id)                                      AS unidades_vendidas,
    ROUND(AVG(oi.price), 2)                                     AS precio_promedio,
    ROUND(SUM(oi.price), 2)                                     AS revenue
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o             ON oi.order_id   = o.order_id
INNER JOIN olist_products_dataset p           ON oi.product_id = p.product_id
LEFT  JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY categoria
ORDER BY unidades_vendidas DESC
LIMIT 10;

-- Top 5 por unidades:
-- bed_bath_table   → 10.953 unidades | R$ 93 prom
-- health_beauty    →  9.465 unidades | R$130 prom  ← aparece en ambos rankings
-- sports_leisure   →  8.431 unidades | R$113 prom
-- furniture_decor  →  8.160 unidades | R$ 87 prom
-- computers_acc.   →  7.644 unidades | R$116 prom
--
-- INSIGHT: "watches_gifts" tiene alto revenue pero baja cantidad
-- de unidades (5.859) — confirma que es una categoría de ticket alto.
-- "bed_bath_table" es líder en volumen pero con precio menor.


-- ============================================================
-- 7. CATEGORÍAS DE TICKET ALTO VS VOLUMEN ALTO
-- Segmentamos categorías en 4 cuadrantes estratégicos:
-- Alto precio + alto volumen  → estrella
-- Alto precio + bajo volumen  → nicho premium
-- Bajo precio + alto volumen  → commodity / rotación
-- Bajo precio + bajo volumen  → larga cola
-- ============================================================

WITH metricas_cat AS (
    SELECT
        COALESCE(t.product_category_name_english, 'Sin categoría') AS categoria,
        COUNT(oi.order_item_id)                                      AS unidades,
        ROUND(AVG(oi.price), 2)                                     AS precio_prom,
        ROUND(SUM(oi.price), 2)                                     AS revenue
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o             ON oi.order_id   = o.order_id
    INNER JOIN olist_products_dataset p           ON oi.product_id = p.product_id
    LEFT  JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
    GROUP BY categoria
    HAVING unidades > 100   -- excluimos categorías con volumen marginal
)
SELECT
    categoria,
    unidades,
    precio_prom,
    revenue,
    CASE
        WHEN precio_prom >= 130 AND unidades >= 4000 THEN 'Estrella (precio alto + volumen alto)'
        WHEN precio_prom >= 130 AND unidades  < 4000 THEN 'Nicho premium (precio alto + volumen bajo)'
        WHEN precio_prom  < 130 AND unidades >= 4000 THEN 'Commodity (precio bajo + volumen alto)'
        ELSE                                               'Larga cola (precio bajo + volumen bajo)'
    END AS segmento
FROM metricas_cat
ORDER BY revenue DESC
LIMIT 20;

-- INSIGHT: Este análisis de cuadrantes es muy valioso para
-- decisiones de negocio:
-- → Las categorías "Estrella" merecen mayor inversión en marketing
-- → Las "Nicho premium" tienen potencial de escala
-- → Las "Commodity" necesitan eficiencia logística para proteger margen


-- ============================================================
-- 8. TOP PRODUCTOS INDIVIDUALES POR REVENUE
-- ============================================================

SELECT
    oi.product_id,
    COALESCE(t.product_category_name_english, 'Sin categoría') AS categoria,
    COUNT(oi.order_item_id)                                      AS unidades_vendidas,
    ROUND(SUM(oi.price), 2)                                     AS revenue,
    ROUND(AVG(oi.price), 2)                                     AS precio_promedio
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o             ON oi.order_id   = o.order_id
INNER JOIN olist_products_dataset p           ON oi.product_id = p.product_id
LEFT  JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY oi.product_id, categoria
ORDER BY revenue DESC
LIMIT 10;

-- Nota: los product_id son hashes anónimos (privacidad del dataset).
-- Lo relevante es la categoría a la que pertenecen y su revenue.
-- El producto top genera R$63.560 con 194 unidades vendidas.


-- ============================================================
-- 9. VISTAS CONSOLIDADAS PARA POWER BI
-- Una query por tabla — exportar como CSV e importar en Power BI
-- ============================================================

-- 9a. Tabla geográfica (para mapa de calor por estado)
SELECT
    c.customer_state                                        AS estado,
    COUNT(DISTINCT o.order_id)                              AS pedidos,
    COUNT(DISTINCT c.customer_unique_id)                    AS clientes,
    ROUND(SUM(op.payment_value), 2)                        AS revenue,
    ROUND(AVG(op.payment_value), 2)                        AS ticket_promedio
FROM olist_orders_dataset o
INNER JOIN olist_customers_dataset c       ON o.customer_id = c.customer_id
INNER JOIN olist_order_payments_dataset op ON o.order_id    = op.order_id
WHERE o.order_status = 'delivered'
  AND op.payment_type != 'not_defined'
GROUP BY c.customer_state
ORDER BY revenue DESC;

-- 9b. Tabla de categorías (para gráfico de barras y treemap)
SELECT
    COALESCE(t.product_category_name_english, 'Sin categoría') AS categoria,
    COUNT(oi.order_item_id)                                      AS unidades,
    ROUND(SUM(oi.price), 2)                                     AS revenue,
    ROUND(AVG(oi.price), 2)                                     AS precio_promedio,
    ROUND(AVG(oi.freight_value), 2)                             AS flete_promedio
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o             ON oi.order_id   = o.order_id
INNER JOIN olist_products_dataset p           ON oi.product_id = p.product_id
LEFT  JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY categoria
ORDER BY revenue DESC;

-- ============================================================
-- FIN FASE 4
-- Próximo paso → FASE 5: Análisis de Sellers & Delivery Performance
-- ============================================================
