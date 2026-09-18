# Задание 2: расписание междугородних автобусов

Диалект: **MySQL 8.0+** (совместимо с MariaDB 10.5+). Всё проверено на реальном MySQL 8.4 в контейнере — DDL, сид, запрос и план выполнения ниже — фактический вывод.

## Модель данных

```
cities (5) ──< stops ──< route_stops >── routes ──< trips >── buses (20)
                             (граф маршрутов: порядок и время от начала)
```

| Таблица | Что хранит | Ключевые решения |
| --- | --- | --- |
| `cities` | города (по условию — 5) | уникальность имени |
| `stops` | остановки/автовокзалы | у города может быть несколько остановок, поэтому остановка ≠ город |
| `buses` | автобусы (по условию — 20) | госномер уникален |
| `routes` | маршруты: **направленные** пары «откуда → куда» | граф направленный: 101 и 102 — разные маршруты; CHECK, что начало ≠ конец |
| `route_stops` | граф маршрутов: упорядоченный список остановок, `travel_time_min` — минуты в пути **от начальной остановки** | маршрут может проходить через промежуточные города; пара (маршрут, остановка) уникальна |
| `trips` | расписание: конкретный автобус на конкретном маршруте и времени | время отправления хранится **только для начальной остановки** |

**Главное нормализационное решение:** время отправления с промежуточной остановки — производная величина `departure_at + travel_time_min`, оно не хранится отдельно и не может рассинхронизироваться. `DATETIME` — это локальное время вокзала (расписание не должно сдвигаться при смене часового пояса сервера).

## Запрос для табло (`board.sql`)

Следующие 15 рейсов с заданной остановки. Семантика:

- рейс виден, пока автобус ещё не уехал с остановки: `departure_at >= NOW() - travel_time_min` — то есть `departure_time >= NOW()`;
- неравенство записано в **sargable форме** (граница вынесена на колонку), чтобы по `departure_at` работал индекс;
- если остановка для рейса **конечная** — это прибытие, на табло отправлений его нет (`rs.stop_id <> r.destination_stop_id`);
- окно +24 часа ограничивает объём сортировки — на табло дальние рейсы не нужны;
- стабильная сортировка `ORDER BY departure_time, trip_id` + `LIMIT 15`.

```sql
WITH upcoming AS (
    SELECT t.id AS trip_id, t.bus_id, t.route_id, r.number AS route_number,
           r.destination_stop_id,
           DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE) AS departure_time
    FROM route_stops rs
    JOIN routes r  ON r.id = rs.route_id
    JOIN trips t
      ON t.route_id = rs.route_id
     AND t.departure_at >= DATE_SUB(NOW(), INTERVAL rs.travel_time_min MINUTE)
    WHERE rs.stop_id = ?                       -- параметр: заданная остановка
      AND rs.stop_id <> r.destination_stop_id  -- конечная остановка → прибытие
      AND DATE_ADD(t.departure_at, INTERVAL rs.travel_time_min MINUTE)
              < DATE_ADD(NOW(), INTERVAL 24 HOUR)
)
SELECT u.departure_time,
       TIMESTAMPDIFF(MINUTE, NOW(), u.departure_time) AS minutes_left,
       u.route_number AS route, dst.name AS destination, b.plate AS bus_plate
FROM upcoming u
JOIN stops dst ON dst.id = u.destination_stop_id
JOIN buses b   ON b.id   = u.bus_id
ORDER BY u.departure_time, u.trip_id
LIMIT 15;
```

Пример фактического вывода (остановка 3 — Нижний Новгород, сквозные 301/302 идут через неё, местные 104/105/202/203 — начинаются):

```
departure_time       | minutes_left | route | destination                | bus_plate
2026-09-18 14:30:00  | 45           | 301   | Автовокзал «Столичный» (Казань) | К016СК50
2026-09-18 15:00:00  | 75           | 202   | Автовокзал «Центральный» (Москва) | М017МК50
2026-09-18 15:00:00  | 75           | 104   | Автовокзал (Владимир)      | Х011ХХ50
...
```

## Сид (`seed.sql`)

5 городов (Москва — Владимир — Нижний Новгород — Чебоксары — Казань), по автовокзалу, 20 автобусов, 14 направленных маршрутов (сегменты магистрали + сквозные 201/202/301/302 в обе стороны), 504 рейса на трое суток. Расписание генерируется **рекурсивным CTE** — 12 рейсов на маршрут в сутки с 06:00 каждые 90 минут.

## Индексы: какие и зачем

| Индекс | Таблица | Роль в запросе |
| --- | --- | --- |
| `uq_rs_stop_route (stop_id, route_id)` | `route_stops` | **Точка входа**: ref-доступ «все маршруты через остановку», `route_id` для join'а берётся прямо из индекса |
| `ix_trips_route_dep_bus (route_id, departure_at, bus_id)` | `trips` | Основной индекс: поиск рейсов маршрута по `(route_id, departure_at)`; `bus_id` в хвосте делает его **покрывающим** — к строкам таблицы обращений нет (`Using index`) |
| `PRIMARY KEY (id)` | `routes`, `stops`, `buses` | eq_ref-лукапы: ровно одна строка на каждый join по PK |
| `ix_routes_destination (destination_stop_id)`, `ix_stops_city (city_id)` | `routes`, `stops` | индексы под внешние ключи (требование InnoDB) |
| `uq_cities_name`, `uq_buses_plate`, `uq_stops_city_name` | справочники | целостность данных |

Важно: составной индекс `trips` начинается с `route_id`, потому что доступ идёт «от маршрутов остановки к рейсам», а не «по всем рейсам и фильтрация».

## Ожидаемый план и что получилось на самом деле

Ожидания: `ref` по `uq_rs_stop_route` (десятки строк — маршруты через остановку) → для каждого маршрута покрывающий `ref`/`range` по `ix_trips_route_dep_bus` → `eq_ref` по PK справочников → filesort только по будущим рейсам в окне → **top-15 priority queue** (MySQL сортирует с LIMIT как кучу, а не полную сортировку). Чего быть не должно: `ALL` (full scan) по `trips`, `Using join buffer (BNL)`, filesort по всей таблице.

Фактический план (`EXPLAIN ANALYZE`, MySQL 8.4, полный вывод в `explain.sql`):

```
-> Limit: 15 row(s)  (actual time=0.211..0.213 rows=15 loops=1)
    -> Sort: u.departure_time, u.trip_id, limit input to 15 row(s) per chunk
       (actual time=0.211..0.212 rows=15 loops=1)                       ← top-15 куча
        -> Stream results  (cost=65.5 rows=108) (actual rows=72 loops=1)
            -> Nested loop inner join
                -> Nested loop inner join
                    -> Nested loop inner join
                        -> Inner hash join (no condition)  (actual rows=40 loops=1)
                            -> Covering index scan on dst using uq_stops_city_name (rows=5)
                            -> Hash
                                -> Index lookup on rs using uq_rs_stop_route (stop_id=3)
                                   (rows=10)                            ← точка входа
                        -> Filter: (r.destination_stop_id = dst.id)
                            -> Single-row index lookup on r using PRIMARY
                               (rows=1 loops=40)                        ← eq_ref
                    -> Filter: (окно отправлений)
                        -> Covering index lookup on t using ix_trips_route_dep_bus
                           (route_id=rs.route_id) (rows=36 → 12 loops=6) ← покрывающий, без строк
                -> Single-row index lookup on b using PRIMARY (rows=1 loops=72)
```

Итого: **~0.2 мс** на выборке 504 рейса. Оптимизатор переставил join: маленький справочник `stops` (5 строк) подтянул hash join'ом, всё остальное — nested loop по индексам. Обратите внимание на `loops=6`: только 6 маршрутов реально проходят через остановку не конечной, по каждому — 36 рейсов читаются **из одного индекса** и сужаются фильтром до 12.

**Честная деталь для обсуждения:** граница окна `NOW() - rs.travel_time_min` зависит от внешней строки, поэтому MySQL применил её как *фильтр поверх* покрывающего индекса, а не как range-условие внутри него (range-доступ требует константных границ неравенства). На нашей глубине расписания (3 суток) это неважно — читаются только рейсы конкретного маршрута. При расписании на годы я бы вынес табло на витрину: денормализованная таблица `board_departures(stop_id, departure_at, route_id, bus_id)`, наполняемая при публикации расписания, с индексом `(stop_id, departure_at)` — тогда запрос сводится к чистому range-скану + `LIMIT 15` вообще без сортировки, план предсказуем под высокой нагрузкой (табло опрашивается каждые несколько секунд).

## Воспроизведение

```bash
podman run -d --name neimark-mysql -e MYSQL_ROOT_PASSWORD=test -e MYSQL_DATABASE=schedule mysql:8.4
# дождаться "mysqld is alive":
podman exec neimark-mysql mysqladmin ping -uroot -ptest

podman exec -i neimark-mysql mysql -uroot -ptest -D schedule < schema.sql
podman exec -i neimark-mysql mysql -uroot -ptest -D schedule < seed.sql
podman exec -i neimark-mysql mysql -uroot -ptest -D schedule -t < board.sql     # табло
podman exec -i neimark-mysql mysql -uroot -ptest -D schedule < explain.sql      # планы
```

## Переносимость

На PostgreSQL запрос переносится почти дословно: `DATE_ADD(x, INTERVAL n MINUTE)` → `x + n * INTERVAL '1 minute'`, `TIMESTAMPDIFF` → `EXTRACT(EPOCH FROM ...)/60`, рекурсивный CTE тот же. Особенность PG: сортировка по выражению тоже не индексная, вывод про витрину применяется в той же мере.
