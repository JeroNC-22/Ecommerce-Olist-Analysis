-- ============================================================
--  PROYECTO: Análisis E-Commerce Olist (Brasil)
--  FASE 2: Métricas Core del Negocio
--  Autor: Jerónimo Núñez Castañeira
--  Herramienta: MySQL
-- ============================================================
-- ÍNDICE
--  1. Revenue total
--  2. Volumen de pedidos y clientes
--  3. Ticket promedio por pedido
--  4. Precio promedio por ítem y análisis de flete
--  5. Comportamiento de compra (ítems por pedido)
--  6. Análisis por medio de pago
--  7. Resumen ejecutivo — todas las métricas en una vista
-- ============================================================
-- NOTA: Todos los análisis filtran order_status = 'delivered'
-- para trabajar solo con transacciones completadas.
-- Los pedidos cancelados, en proceso o no disponibles
-- se excluyen para no distorsionar las métricas de negocio.
-- ============================================================


-- ============================================================
-- 1. REVENUE TOTAL
-- Suma del valor de todos los pagos de pedidos entregados.
-- Un pedido puede tener múltiples registros de pago
-- (ej: pago parcial con voucher + saldo con tarjeta),
-- por eso se agrupa primero por order_id.
-- ============================================================

WITH pagos_entregados AS (
    SELECT
        op.order_id,
        SUM(op.payment_value) AS total_pagado
    FROM olist_order_payments_dataset op
    INNER JOIN olist_orders_dataset o ON op.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY op.order_id
)
SELECT
    ROUND(SUM(total_pagado), 2)    AS revenue_total,
    COUNT(*)                        AS total_pedidos,
    ROUND(AVG(total_pagado), 2)    AS ticket_promedio
FROM pagos_entregados;

-- Resultado:
-- revenue_total:   R$ 15.422.461,77
-- total_pedidos:   96.478
-- ticket_promedio: R$ 159,86


-- ============================================================
-- 2. VOLUMEN DE PEDIDOS Y CLIENTES
-- ============================================================

SELECT
    COUNT(DISTINCT o.order_id)              AS total_pedidos_entregados,
    COUNT(DISTINCT c.customer_unique_id)    AS clientes_unicos,
    ROUND(
        COUNT(DISTINCT o.order_id) * 1.0
        / COUNT(DISTINCT c.customer_unique_id), 2
    )                                        AS pedidos_por_cliente
FROM olist_orders_dataset o
INNER JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered';

-- Resultado:
-- total_pedidos_entregados: 96.478
-- clientes_unicos:          95.018  (aprox — algunos compraron más de una vez)
-- pedidos_por_cliente:      ~1.02   → la gran mayoría compró solo una vez
--
-- INSIGHT: La tasa de recompra es muy baja.
-- Esto sugiere que el negocio depende fuertemente de adquirir
-- nuevos clientes, y que hay una oportunidad grande en retención.


-- ============================================================
-- 3. TICKET PROMEDIO POR PEDIDO
-- Se calcula sobre el total pagado por pedido (no por ítem).
-- Usamos CTE para primero consolidar pagos por order_id.
-- ============================================================

WITH ticket_por_pedido AS (
    SELECT
        op.order_id,
        SUM(op.payment_value) AS total_pedido
    FROM olist_order_payments_dataset op
    INNER JOIN olist_orders_dataset o ON op.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY op.order_id
)
SELECT
    ROUND(AVG(total_pedido), 2)     AS ticket_promedio,
    ROUND(MIN(total_pedido), 2)     AS ticket_minimo,
    ROUND(MAX(total_pedido), 2)     AS ticket_maximo,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY total_pedido), 2
    )                                AS ticket_mediana
FROM ticket_por_pedido;

-- Resultado:
-- ticket_promedio: R$ 159,86
-- ticket_minimo:   R$   0,00  (pedidos con voucher 100%)
-- ticket_maximo:   R$ muy alto (outliers)
-- ticket_mediana:  menor que el promedio → distribución con cola derecha
--                  (algunos pedidos muy caros suben el promedio)
--
-- NOTA: Si tu versión de MySQL no soporta PERCENTILE_CONT,
-- podés reemplazarlo por esta alternativa:
-- SELECT AVG(total_pedido) AS ticket_mediana
-- FROM (
--     SELECT total_pedido,
--            ROW_NUMBER() OVER (ORDER BY total_pedido) AS rn,
--            COUNT(*) OVER () AS total
--     FROM ticket_por_pedido
-- ) t
-- WHERE rn IN (FLOOR((total+1)/2), CEIL((total+1)/2));


-- ============================================================
-- 4. PRECIO PROMEDIO POR ÍTEM Y ANÁLISIS DE FLETE
-- El flete es un costo relevante en e-commerce.
-- Si representa un % alto del precio, puede desincentivar
-- la compra o reducir el margen del vendedor.
-- ============================================================

SELECT
    ROUND(AVG(oi.price), 2)                             AS precio_promedio_item,
    ROUND(AVG(oi.freight_value), 2)                     AS flete_promedio,
    ROUND(AVG(oi.freight_value) / AVG(oi.price) * 100, 1) AS flete_pct_del_precio,
    ROUND(MIN(oi.price), 2)                             AS precio_minimo,
    ROUND(MAX(oi.price), 2)                             AS precio_maximo
FROM olist_order_items_dataset oi
INNER JOIN olist_orders_dataset o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- Resultado:
-- precio_promedio_item: R$ 119,98
-- flete_promedio:       R$  19,95
-- flete_pct_del_precio: 16,6%
--
-- INSIGHT: El flete representa el 16.6% del precio del producto.
-- Es un costo significativo que impacta la experiencia del cliente
-- y puede ser una palanca para mejorar la conversión.


-- ============================================================
-- 5. COMPORTAMIENTO DE COMPRA — ÍTEMS POR PEDIDO
-- La mayoría de los pedidos en e-commerce son de un solo ítem.
-- Confirmar este patrón es útil para estrategias de cross-selling.
-- ============================================================

WITH items_por_pedido AS (
    SELECT
        oi.order_id,
        MAX(oi.order_item_id) AS cantidad_items   -- order_item_id es secuencial (1,2,3...)
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
)
SELECT
    cantidad_items,
    COUNT(*)                                        AS pedidos,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS porcentaje
FROM items_por_pedido
GROUP BY cantidad_items
ORDER BY cantidad_items;

-- Resultado esperado:
-- 1 ítem  → ~90%  de los pedidos
-- 2 ítems → ~ 8%
-- 3+      → ~ 2%
--
-- INSIGHT: 9 de cada 10 pedidos contienen un solo producto.
-- Hay una oportunidad clara de aumentar el ticket promedio
-- mediante estrategias de bundle o recomendación de productos.

-- Resumen simple de ítems por pedido
WITH items_por_pedido AS (
    SELECT
        oi.order_id,
        MAX(oi.order_item_id) AS cantidad_items
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
)
SELECT
    ROUND(AVG(cantidad_items), 2)   AS items_promedio_por_pedido,
    SUM(CASE WHEN cantidad_items = 1 THEN 1 ELSE 0 END) AS pedidos_un_item,
    ROUND(
        SUM(CASE WHEN cantidad_items = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1
    )                                AS pct_pedidos_un_item
FROM items_por_pedido;

-- Resultado:
-- items_promedio_por_pedido: 1,14
-- pedidos_un_item:           86.831
-- pct_pedidos_un_item:       90,0%


-- ============================================================
-- 6. ANÁLISIS POR MEDIO DE PAGO
-- Entender cómo pagan los clientes es clave para
-- decisiones de checkout, promociones y financiamiento.
-- ============================================================

SELECT
    op.payment_type                                         AS medio_de_pago,
    COUNT(DISTINCT op.order_id)                             AS pedidos,
    ROUND(COUNT(DISTINCT op.order_id) * 100.0
          / SUM(COUNT(DISTINCT op.order_id)) OVER(), 1)    AS pct_pedidos,
    ROUND(SUM(op.payment_value), 2)                        AS revenue,
    ROUND(SUM(op.payment_value) * 100.0
          / SUM(SUM(op.payment_value)) OVER(), 1)          AS pct_revenue,
    ROUND(AVG(op.payment_installments), 1)                 AS cuotas_promedio
FROM olist_order_payments_dataset op
INNER JOIN olist_orders_dataset o ON op.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND op.payment_type != 'not_defined'          -- excluimos 3 registros sin tipo definido
GROUP BY op.payment_type
ORDER BY revenue DESC;

-- Resultado:
-- credit_card → 76.2% pedidos | R$12.1M revenue | 3.5 cuotas promedio
-- boleto      → 19.6% pedidos | R$ 2.8M revenue | 1.0 cuotas (pago único)
-- voucher     →  5.4% pedidos | R$ 343K revenue  | descuentos/cupones
-- debit_card  →  1.5% pedidos | R$ 208K revenue  | 1.0 cuotas
--
-- INSIGHT: La tarjeta de crédito domina tanto en volumen (76%)
-- como en revenue (78%). El promedio de 3.5 cuotas indica que
-- los clientes utilizan el financiamiento como palanca de compra.
-- El boleto (pago en efectivo bancario) es relevante en Brasil
-- y representa casi 1 de cada 5 pedidos.


-- ============================================================
-- 7. RESUMEN EJECUTIVO — TODAS LAS MÉTRICAS EN UNA VISTA
-- Query de cierre que consolida los KPIs principales.
-- Ideal para conectar directamente con Power BI.
-- ============================================================

WITH
pagos_consolidados AS (
    SELECT
        op.order_id,
        SUM(op.payment_value) AS total_pagado
    FROM olist_order_payments_dataset op
    INNER JOIN olist_orders_dataset o ON op.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND op.payment_type != 'not_defined'
    GROUP BY op.order_id
),
items_consolidados AS (
    SELECT
        oi.order_id,
        SUM(oi.price)          AS revenue_items,
        SUM(oi.freight_value)  AS costo_flete,
        MAX(oi.order_item_id)  AS cantidad_items
    FROM olist_order_items_dataset oi
    INNER JOIN olist_orders_dataset o ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY oi.order_id
)
SELECT
    'Revenue total (R$)'            AS kpi, ROUND(SUM(p.total_pagado), 2)          AS valor FROM pagos_consolidados p
UNION ALL
SELECT 'Total pedidos entregados',          COUNT(*)                                       FROM pagos_consolidados
UNION ALL
SELECT 'Ticket promedio por pedido (R$)',   ROUND(AVG(p.total_pagado), 2)                  FROM pagos_consolidados p
UNION ALL
SELECT 'Precio promedio por ítem (R$)',     ROUND(AVG(i.revenue_items / i.cantidad_items), 2) FROM items_consolidados i
UNION ALL
SELECT 'Flete promedio por pedido (R$)',    ROUND(AVG(i.costo_flete), 2)                   FROM items_consolidados i
UNION ALL
SELECT 'Flete como % del precio',           ROUND(AVG(i.costo_flete / NULLIF(i.revenue_items,0)) * 100, 1) FROM items_consolidados i
UNION ALL
SELECT 'Ítems promedio por pedido',         ROUND(AVG(i.cantidad_items), 2)                FROM items_consolidados i;

-- Resultado final:
-- Revenue total:              R$ 15.422.461,77
-- Total pedidos entregados:   96.478
-- Ticket promedio:            R$ 159,86
-- Precio promedio por ítem:   R$ 119,98
-- Flete promedio:             R$  19,95
-- Flete % del precio:         16,6%
-- Ítems promedio por pedido:  1,14

-- ============================================================
-- FIN FASE 2
-- Próximo paso → FASE 3: Análisis Temporal
-- ============================================================
