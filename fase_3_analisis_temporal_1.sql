-- ============================================================
--  PROYECTO: Análisis E-Commerce Olist (Brasil)
--  FASE 3: Análisis Temporal
--  Autor: Jerónimo Núñez Castañeira
--  Herramienta: MySQL
-- ============================================================
-- ÍNDICE
--  1. Evolución mensual de pedidos y revenue
--  2. Crecimiento mes a mes (MoM)
--  3. Comparación anual 2017 vs 2018
--  4. Estacionalidad — día de la semana
--  5. Estacionalidad — hora del día
--  6. Detección del pico de noviembre 2017 (Black Friday)
--  7. Vista consolidada para Power BI
-- ============================================================
-- CONTEXTO DEL DATASET
-- El dataset cubre: oct 2016 → ago 2018
-- Oct-dic 2016: datos parciales, volumen muy bajo (arranque)
-- 2017: primer año completo de operación
-- 2018: datos hasta agosto (año incompleto)
-- → Para comparaciones YoY usaremos ene-ago de cada año
-- ============================================================


-- ============================================================
-- 1. EVOLUCIÓN MENSUAL DE PEDIDOS Y REVENUE
-- Base de todo el análisis temporal.
-- Excluimos oct-dic 2016 por ser datos de arranque (outliers).
-- ============================================================

SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')    AS mes,
    COUNT(DISTINCT o.order_id)                           AS pedidos,
    ROUND(SUM(op.payment_value), 2)                     AS revenue,
    ROUND(AVG(op.payment_value), 2)                     AS ticket_promedio
FROM olist_orders_dataset o
INNER JOIN olist_order_payments_dataset op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'   -- excluimos arranque 2016
  AND op.payment_type != 'not_defined'
GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
ORDER BY mes;

-- Resultado destacado:
-- 2017-01:  750 pedidos | R$  127.545
-- 2017-11: 7.289 pedidos | R$1.153.528  ← pico máximo (Black Friday)
-- 2018-01: 7.069 pedidos | R$1.078.606
-- 2018-08: 6.351 pedidos | R$  985.414  ← último mes disponible
--
-- TENDENCIA: crecimiento sostenido durante 2017, estabilización
-- en la primera mitad de 2018 entre R$1M y R$1.1M mensuales.


-- ============================================================
-- 2. CRECIMIENTO MES A MES (MoM)
-- Usamos LAG() para comparar cada mes con el anterior
-- y calcular la variación porcentual.
-- ============================================================

WITH revenue_mensual AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS mes,
        ROUND(SUM(op.payment_value), 2)                   AS revenue
    FROM olist_orders_dataset o
    INNER JOIN olist_order_payments_dataset op ON o.order_id = op.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND op.payment_type != 'not_defined'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    mes,
    revenue,
    LAG(revenue) OVER (ORDER BY mes)                              AS revenue_mes_anterior,
    ROUND(
        (revenue - LAG(revenue) OVER (ORDER BY mes))
        / LAG(revenue) OVER (ORDER BY mes) * 100, 1
    )                                                              AS crecimiento_pct
FROM revenue_mensual
ORDER BY mes;

-- Resultado destacado:
-- 2017-11: +53.6% vs octubre → pico de Black Friday
-- 2017-12: -26.9% vs noviembre → caída post-Black Friday (esperada)
-- 2018-01: +27.9% → fuerte recuperación en enero
-- 2018-06 a 2018-08: ligera desaceleración (-4% a -10%)
--
-- INSIGHT: La caída de dic 2017 no es preocupante — es el efecto
-- de normalización después de un pico promocional. Lo relevante
-- es que el piso de 2018 (~R$1M/mes) está muy por encima
-- del piso de 2017 (~R$400-500K/mes).


-- ============================================================
-- 3. COMPARACIÓN ANUAL 2017 vs 2018
-- Para comparar años completos usamos ene-ago de cada uno,
-- ya que 2018 solo tiene datos hasta agosto.
-- ============================================================

SELECT
    YEAR(o.order_purchase_timestamp)                    AS anio,
    COUNT(DISTINCT o.order_id)                           AS pedidos,
    ROUND(SUM(op.payment_value), 2)                     AS revenue,
    ROUND(AVG(op.payment_value), 2)                     AS ticket_promedio
FROM olist_orders_dataset o
INNER JOIN olist_order_payments_dataset op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
  AND YEAR(o.order_purchase_timestamp) IN (2017, 2018)
  AND MONTH(o.order_purchase_timestamp) BETWEEN 1 AND 8  -- período comparable
  AND op.payment_type != 'not_defined'
GROUP BY YEAR(o.order_purchase_timestamp)
ORDER BY anio;

-- Resultado (ene-ago, período comparable):
-- 2017: 25.397 pedidos | R$ 3.987.864
-- 2018: 52.783 pedidos | R$ 8.452.975
--
-- INSIGHT: En el mismo período (ene-ago), el negocio creció
-- +108% en pedidos y +112% en revenue año contra año.
-- Prácticamente se duplicó en 12 meses.


-- ============================================================
-- 4. ESTACIONALIDAD — DÍA DE LA SEMANA
-- ¿Cuándo compran más los clientes?
-- Útil para definir cuándo lanzar campañas o promociones.
-- ============================================================

SELECT
    DAYNAME(o.order_purchase_timestamp)                  AS dia_semana,
    DAYOFWEEK(o.order_purchase_timestamp)                AS dia_num,   -- para ordenar
    COUNT(DISTINCT o.order_id)                            AS pedidos,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0
          / SUM(COUNT(DISTINCT o.order_id)) OVER(), 1)   AS pct_pedidos
FROM olist_orders_dataset o
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
GROUP BY dia_semana, dia_num
ORDER BY dia_num;

-- Resultado:
-- Lunes:    15.701 (16.5%) ← día pico
-- Martes:   15.503 (16.3%)
-- Miércoles:15.076 (15.9%)
-- Jueves:   14.323 (15.1%)
-- Viernes:  13.685 (14.4%)
-- Sábado:   10.555 (11.1%) ← mínimo
-- Domingo:  11.635 (12.2%)
--
-- INSIGHT: Los días de semana concentran el 78% de las compras.
-- El lunes es el día pico, probablemente por compras
-- decididas durante el fin de semana y ejecutadas el lunes.
-- El sábado es el día de menor actividad.


-- ============================================================
-- 5. ESTACIONALIDAD — HORA DEL DÍA
-- Permite entender los momentos de mayor intención de compra.
-- ============================================================

SELECT
    HOUR(o.order_purchase_timestamp)                     AS hora,
    COUNT(DISTINCT o.order_id)                            AS pedidos,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0
          / SUM(COUNT(DISTINCT o.order_id)) OVER(), 1)   AS pct_pedidos,
    CASE
        WHEN HOUR(o.order_purchase_timestamp) BETWEEN 6  AND 11 THEN 'Mañana'
        WHEN HOUR(o.order_purchase_timestamp) BETWEEN 12 AND 17 THEN 'Tarde'
        WHEN HOUR(o.order_purchase_timestamp) BETWEEN 18 AND 23 THEN 'Noche'
        ELSE 'Madrugada'
    END                                                   AS franja_horaria
FROM olist_orders_dataset o
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
GROUP BY hora
ORDER BY hora;

-- Resultado destacado:
-- Pico principal: 16hs (6.476 pedidos) — tarde laboral
-- Segundo pico:   11hs y 14hs — horario de almuerzo
-- Valle nocturno: 3-5hs (menos de 300 pedidos/hora)
-- Madrugada 0hs:  2.321 — compras nocturnas relevantes
--
-- Resumen por franja:
-- Mañana (6-11):   ~25% de las compras
-- Tarde (12-17):   ~38% ← franja dominante
-- Noche (18-23):   ~29%
-- Madrugada (0-5): ~ 8%

-- Resumen por franja horaria (query simplificada)
SELECT
    CASE
        WHEN HOUR(o.order_purchase_timestamp) BETWEEN 6  AND 11 THEN '1. Mañana (6-11hs)'
        WHEN HOUR(o.order_purchase_timestamp) BETWEEN 12 AND 17 THEN '2. Tarde (12-17hs)'
        WHEN HOUR(o.order_purchase_timestamp) BETWEEN 18 AND 23 THEN '3. Noche (18-23hs)'
        ELSE '4. Madrugada (0-5hs)'
    END                                                    AS franja,
    COUNT(DISTINCT o.order_id)                             AS pedidos,
    ROUND(COUNT(DISTINCT o.order_id) * 100.0
          / SUM(COUNT(DISTINCT o.order_id)) OVER(), 1)    AS pct_pedidos
FROM olist_orders_dataset o
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
GROUP BY franja
ORDER BY franja;


-- ============================================================
-- 6. DETECCIÓN DEL PICO — NOVIEMBRE 2017 (BLACK FRIDAY)
-- Noviembre 2017 fue el mes de mayor revenue del dataset.
-- Analizamos qué semana concentró el pico.
-- ============================================================

SELECT
    WEEK(o.order_purchase_timestamp, 1)                  AS semana_del_anio,
    MIN(DATE(o.order_purchase_timestamp))                 AS inicio_semana,
    COUNT(DISTINCT o.order_id)                            AS pedidos,
    ROUND(SUM(op.payment_value), 2)                       AS revenue
FROM olist_orders_dataset o
INNER JOIN olist_order_payments_dataset op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-11-01'
  AND o.order_purchase_timestamp  < '2017-12-01'
  AND op.payment_type != 'not_defined'
GROUP BY semana_del_anio
ORDER BY semana_del_anio;

-- Black Friday 2017 fue el 24 de noviembre.
-- La semana que lo contiene debería mostrar el pico más alto.
--
-- INSIGHT: El pico de nov 2017 (+53.6% vs oct) confirma
-- que el negocio es sensible a eventos promocionales.
-- Esto es una señal para planificar stock, logística
-- y capacidad operativa en esas fechas.


-- ============================================================
-- 7. VISTA CONSOLIDADA PARA POWER BI
-- Esta query devuelve una fila por mes con todas las métricas
-- temporales. Es la base ideal para el dashboard de tendencias.
-- ============================================================

SELECT
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')     AS mes,
    YEAR(o.order_purchase_timestamp)                      AS anio,
    MONTH(o.order_purchase_timestamp)                     AS nro_mes,
    DATE_FORMAT(o.order_purchase_timestamp, '%b %Y')     AS mes_label,
    COUNT(DISTINCT o.order_id)                            AS pedidos,
    ROUND(SUM(op.payment_value), 2)                       AS revenue,
    ROUND(AVG(op.payment_value), 2)                       AS ticket_promedio,
    COUNT(DISTINCT o.customer_id)                         AS clientes
FROM olist_orders_dataset o
INNER JOIN olist_order_payments_dataset op ON o.order_id = op.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND op.payment_type != 'not_defined'
GROUP BY
    DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m'),
    YEAR(o.order_purchase_timestamp),
    MONTH(o.order_purchase_timestamp),
    DATE_FORMAT(o.order_purchase_timestamp, '%b %Y')
ORDER BY mes;

-- Esta tabla la exportás desde MySQL como CSV
-- y la importás directamente en Power BI para
-- construir el gráfico de líneas de evolución mensual.

-- ============================================================
-- FIN FASE 3
-- Próximo paso → FASE 4: Análisis Geográfico y de Productos
-- ============================================================
