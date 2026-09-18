-- =====================================================================
-- Проверка плана выполнения запроса табло (остановка 3 — Нижний Новгород).
-- EXPLAIN           — оценки оптимизатора;
-- EXPLAIN ANALYZE   — фактический план: реальные числа строк и время.
-- =====================================================================

EXPLAIN
WITH upcoming AS (
    SELECT t.id AS trip_id, t.bus_id, t.route_id, r.number AS route_number,
           r.destination_stop_id,
           DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE) AS departure_time
    FROM route_stops rs
    JOIN routes r  ON r.id = rs.route_id
    JOIN trips t
      ON t.route_id = rs.route_id
     AND t.departure_at >= DATE_SUB(NOW(), INTERVAL rs.travel_time_min MINUTE)
    WHERE rs.stop_id = 3
      AND rs.stop_id <> r.destination_stop_id
      AND DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE)
              < DATE_ADD(NOW(), INTERVAL 24 HOUR)
)
SELECT u.departure_time,
       TIMESTAMPDIFF(MINUTE, NOW(), u.departure_time) AS minutes_left,
       u.route_number AS route, dst.name AS destination, b.plate AS bus_plate
FROM upcoming u
JOIN stops dst  ON dst.id = u.destination_stop_id
JOIN buses b    ON b.id   = u.bus_id
ORDER BY u.departure_time, u.trip_id
LIMIT 15;

EXPLAIN ANALYZE
WITH upcoming AS (
    SELECT t.id AS trip_id, t.bus_id, t.route_id, r.number AS route_number,
           r.destination_stop_id,
           DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE) AS departure_time
    FROM route_stops rs
    JOIN routes r  ON r.id = rs.route_id
    JOIN trips t
      ON t.route_id = rs.route_id
     AND t.departure_at >= DATE_SUB(NOW(), INTERVAL rs.travel_time_min MINUTE)
    WHERE rs.stop_id = 3
      AND rs.stop_id <> r.destination_stop_id
      AND DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE)
              < DATE_ADD(NOW(), INTERVAL 24 HOUR)
)
SELECT u.departure_time,
       TIMESTAMPDIFF(MINUTE, NOW(), u.departure_time) AS minutes_left,
       u.route_number AS route, dst.name AS destination, b.plate AS bus_plate
FROM upcoming u
JOIN stops dst  ON dst.id = u.destination_stop_id
JOIN buses b    ON b.id   = u.bus_id
ORDER BY u.departure_time, u.trip_id
LIMIT 15;
