-- =====================================================================
-- Электронное табло: следующие 15 рейсов с заданной остановки (:stop_id).
--
-- Логика:
--   - отправление с промежуточной остановки = departure_at (с начальной)
--     + travel_time_min этой остановки;
--   - рейс виден на табло, пока автобус ещё не уехал с остановки:
--     departure_at >= NOW() - travel_time_min  ⇔  departure_time >= NOW()
--     (неравенство записано в sargable форме — по departure_at работает индекс);
--   - если эта остановка для рейса КОНЕЧНАЯ, рейс на табло отправлений не
--     показывается (это прибытие, автобус завершает рейс);
--   - окно +24 часа ограничивает объём сортировки (на табло дальние рейсы не нужны);
--   - ORDER BY departure_time, trip_id — стабильная сортировка; LIMIT 15.
-- =====================================================================

WITH upcoming AS (
    SELECT t.id       AS trip_id,
           t.bus_id,
           t.route_id,
           r.number   AS route_number,
           r.destination_stop_id,
           DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE) AS departure_time
    FROM route_stops rs
    JOIN routes r
      ON r.id = rs.route_id
    JOIN trips t
      ON t.route_id = rs.route_id
     AND t.departure_at >= DATE_SUB(NOW(), INTERVAL rs.travel_time_min MINUTE)
    WHERE rs.stop_id = 3                                   -- ← параметр: заданная остановка
      AND rs.stop_id <> r.destination_stop_id              -- конечная остановка → это прибытие
      AND DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE)
              < DATE_ADD(NOW(), INTERVAL 24 HOUR)
)
SELECT
    u.departure_time                                       AS departure_time,
    TIMESTAMPDIFF(MINUTE, NOW(), u.departure_time)         AS minutes_left,
    u.route_number                                         AS route,
    dst.name                                               AS destination,
    b.plate                                                AS bus_plate
FROM upcoming u
JOIN stops dst  ON dst.id = u.destination_stop_id
JOIN buses  b   ON b.id   = u.bus_id
ORDER BY u.departure_time, u.trip_id
LIMIT 15;

-- Тот же запрос с плейсхолдером для драйвера:
--   ... WHERE rs.stop_id = ?  ...  (подготовленный оператор, Prepared Statements)
