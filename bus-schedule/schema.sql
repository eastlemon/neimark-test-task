-- =====================================================================
-- Расписание междугородних автобусов. Диалект: MySQL 8.0+ (MariaDB 10.5+).
-- Модель:
--   cities      — города (по условию: 5)
--   stops       — остановки/автовокзалы (у города их может быть несколько)
--   buses       — автобусы (по условию: 20)
--   routes      — маршруты: НАПРАВЛЕННАЯ пара «откуда → куда» (граф направленный)
--   route_stops — граф маршрутов: упорядоченный список остановок маршрута
--                 (seq=0 — начальная; travel_time_min — время в пути от начальной)
--   trips       — расписание: конкретный автобус на конкретном маршруте
--                 отправляется в конкретный момент времени
--
-- Время отправления с ЛЮБОЙ остановки маршрута — производная величина:
--   departure_at (с начальной) + travel_time_min этой остановки.
-- Поэтому оно не хранится отдельно (нормализация: не дублируем и не рассинхронизируем).
-- =====================================================================

SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS trips, route_stops, routes, buses, stops, cities;
SET FOREIGN_KEY_CHECKS = 1;

CREATE TABLE cities (
    id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_cities_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE stops (
    id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    city_id INT UNSIGNED NOT NULL,
    name    VARCHAR(150) NOT NULL,           -- «Автовокзал Щёлково», «АС Мурманск»
    PRIMARY KEY (id),
    UNIQUE KEY uq_stops_city_name (city_id, name),
    KEY ix_stops_city (city_id),             -- индекс под внешний ключ
    CONSTRAINT fk_stops_city FOREIGN KEY (city_id) REFERENCES cities (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE buses (
    id    INT UNSIGNED NOT NULL AUTO_INCREMENT,
    plate VARCHAR(15) NOT NULL,              -- госномер
    model VARCHAR(100) NULL,
    seats SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_buses_plate (plate)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE routes (
    id                  INT UNSIGNED NOT NULL AUTO_INCREMENT,
    number              VARCHAR(10)  NOT NULL,
    origin_stop_id      INT UNSIGNED NOT NULL,
    destination_stop_id INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_routes_number_origin (number, origin_stop_id), -- номер уникален в рамках направления
    KEY ix_routes_destination (destination_stop_id),             -- индекс под внешний ключ
    CONSTRAINT fk_routes_origin FOREIGN KEY (origin_stop_id)      REFERENCES stops (id),
    CONSTRAINT fk_routes_dest   FOREIGN KEY (destination_stop_id) REFERENCES stops (id),
    CONSTRAINT chk_routes_diff_stops CHECK (origin_stop_id <> destination_stop_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE route_stops (
    route_id        INT UNSIGNED NOT NULL,
    stop_id         INT UNSIGNED NOT NULL,
    seq             SMALLINT UNSIGNED NOT NULL,  -- порядок остановки на маршруте, с 0
    travel_time_min SMALLINT UNSIGNED NOT NULL,  -- минуты в пути от начальной остановки
    PRIMARY KEY (route_id, seq),
    -- Пара (route_id, stop_id) уникальна; порядок колонок (stop_id, route_id) выбран
    -- под запрос табло: точка входа — «все маршруты через заданную остановку».
    UNIQUE KEY uq_rs_stop_route (stop_id, route_id),
    CONSTRAINT fk_rs_route FOREIGN KEY (route_id) REFERENCES routes (id) ON DELETE CASCADE,
    CONSTRAINT fk_rs_stop  FOREIGN KEY (stop_id)  REFERENCES stops (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE trips (
    id           BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    route_id     INT UNSIGNED NOT NULL,
    bus_id       INT UNSIGNED NOT NULL,
    departure_at DATETIME NOT NULL,      -- отправление с начальной остановки, локальное время
    PRIMARY KEY (id),
    -- Ключевой индекс запроса табло: range-поиск по (route_id, departure_at),
    -- bus_id в хвосте делает индекс покрывающим (обращений к строкам таблицы нет;
    -- PK id в InnoDB неявно присутствует в каждом вторичном индексе).
    KEY ix_trips_route_dep_bus (route_id, departure_at, bus_id),
    CONSTRAINT fk_trips_route FOREIGN KEY (route_id) REFERENCES routes (id),
    CONSTRAINT fk_trips_bus   FOREIGN KEY (bus_id)   REFERENCES buses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
