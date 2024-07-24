-- Create table
DROP TABLE IF EXISTS cyclistic_bike;
CREATE TABLE cyclistic_bike (
    ride_id VARCHAR(50) PRIMARY KEY,
    rideable_type VARCHAR(50),
    started_at TIMESTAMP,
    ended_at TIMESTAMP,
    started_station_name TEXT,
    start_station_id VARCHAR(50),
    end_station_name TEXT,
    end_station_id VARCHAR(50),
    start_lat FLOAT,
    start_lng FLOAT,
    end_lat FLOAT,
    end_lng FLOAT,
    member_casual VARCHAR(50)
);

-- DATA WRANGLING

-- Drop start_station_id and end_station_id
ALTER TABLE cyclistic_bike
DROP COLUMN start_station_id,
DROP COLUMN end_station_id;

-- Replace the "docked_bike" with "classic_bike"
UPDATE cyclistic_bike
SET rideable_type = CASE
    WHEN rideable_type = 'docked_bike' THEN 'classic_bike'
    ELSE rideable_type
END;

-- Remove rows with maintenance stations
DELETE FROM cyclistic_bike
WHERE UPPER(TRIM(start_station_name)) IN ('DIVVY CASSETTE REPAIR MOBILE STATION', 'LYFT DRIVER CENTER PRIVATE RACK', '351', 'BASE - 2132 W HUBBARD WAREHOUSE', 'HUBBARD BIKE-CHECKING (LBS-WH-TEST)', 'WEST CHI-WATSON')
   OR UPPER(TRIM(end_station_name)) IN ('DIVVY CASSETTE REPAIR MOBILE STATION', 'LYFT DRIVER CENTER PRIVATE RACK', '351', 'BASE - 2132 W HUBBARD WAREHOUSE', 'HUBBARD BIKE-CHECKING (LBS-WH-TEST)', 'WEST CHI-WATSON');

-- Remove classic_bike trips with null values in start or end docking station
DELETE FROM cyclistic_bike
WHERE rideable_type = 'classic_bike'
  AND (start_station_name IS NULL OR end_station_name IS NULL);

-- Replace null values in start_station_name and end_station_name with 'On bike lock' with electric_bike trips
UPDATE cyclistic_bike
SET start_station_name = COALESCE(start_station_name, 'On bike lock'),
    end_station_name = COALESCE(end_station_name, 'On bike lock')
WHERE rideable_type = 'electric_bike';

-- Only focus on trip durations within day (0-1440 minutes)
---- create new metris: ride_time_minutes, weakday_started, month_started, hours
ALTER TABLE cyclistic_bike
ADD COLUMN ride_time_minutes NUMERIC;

UPDATE cyclistic_bike
SET ride_time_minutes = ROUND(EXTRACT(EPOCH FROM (ended_at - started_at)) / 60, 2);

DELETE FROM cyclistic_bike
WHERE ride_time_minutes <= 0 OR ride_time_minutes >= 1440;

ALTER TABLE cyclistic_bike
ADD COLUMN weekday_started INT,
ADD COLUMN month_started INT,
ADD COLUMN hours INT;

UPDATE cyclistic_bike
SET weekday_started = EXTRACT(DOW FROM started_at),
    month_started = EXTRACT(MONTH FROM started_at),
    hours = EXTRACT(HOUR FROM started_at);

-- Double check
---- check null values
SELECT     
	SUM(CASE WHEN member_casual IS NULL THEN 1 ELSE 0 END) AS member_casual_nulls,
	SUM(CASE WHEN end_lng IS NULL THEN 1 ELSE 0 END) AS end_lng_nulls,
	SUM(CASE WHEN end_lat IS NULL THEN 1 ELSE 0 END) AS end_lat_nulls,
	SUM(CASE WHEN start_lng IS NULL THEN 1 ELSE 0 END) AS start_lng_nulls,
	SUM(CASE WHEN start_lat IS NULL THEN 1 ELSE 0 END) AS start_lat_nulls,
	SUM(CASE WHEN rideable_type IS NULL THEN 1 ELSE 0 END) AS rideable_type_nulls,
    SUM(CASE WHEN start_station_name IS NULL THEN 1 ELSE 0 END) AS start_station_name_nulls,
    SUM(CASE WHEN end_station_name IS NULL THEN 1 ELSE 0 END) AS end_station_name_nulls,
    SUM(CASE WHEN rideable_type IS NULL THEN 1 ELSE 0 END) AS rideable_type_nulls,
    SUM(CASE WHEN started_at IS NULL THEN 1 ELSE 0 END) AS started_at_nulls,
    SUM(CASE WHEN ended_at IS NULL THEN 1 ELSE 0 END) AS ended_at_nulls,
    SUM(CASE WHEN ride_time_minutes IS NULL THEN 1 ELSE 0 END) AS ride_time_minutes_nulls,
    SUM(CASE WHEN weekday_started IS NULL THEN 1 ELSE 0 END) AS weekday_started_nulls,
    SUM(CASE WHEN month_started IS NULL THEN 1 ELSE 0 END) AS month_started_nulls,
    SUM(CASE WHEN hours IS NULL THEN 1 ELSE 0 END) AS hours_nulls
FROM cyclistic_bike;

---- check duplicates
SELECT ride_id, count(ride_id)
FROM cyclistic_bike
GROUP BY ride_id
HAVING count(ride_id) > 1;

-- DATA ANALYSIS

---- Preference bike types of casual riders and annual members.
WITH counts AS (
    SELECT
        member_casual,
        rideable_type,
        COUNT(ride_id) AS ride_count
    FROM cyclistic_bike
    GROUP BY member_casual, rideable_type
),
totals AS (
    SELECT
        member_casual,
        SUM(ride_count) AS total_count
    FROM counts
    GROUP BY member_casual
)
SELECT
    c.member_casual,
    c.rideable_type,
    c.ride_count,
    t.total_count,
    ROUND((c.ride_count::decimal / t.total_count * 100), 2) AS percentage
FROM counts c
JOIN totals t
ON c.member_casual = t.member_casual
ORDER BY c.member_casual, c.rideable_type;

---- percentage of rides per hours/days/months. Replace "hours" with "weekday_started", "month_started"
WITH counts AS (
    SELECT
        member_casual,
        rideable_type,
        hours ,
        COUNT(ride_id) AS ride_count
    FROM cyclistic_bike
    GROUP BY member_casual, rideable_type, hours
),
total_counts AS (
    SELECT
        member_casual,
        SUM(ride_count) AS total_count
    FROM counts
    GROUP BY member_casual
),
percentage AS (
    SELECT
        c.member_casual,
        c.rideable_type,
        c.hours,
        c.ride_count,
        t.total_count,
        ROUND((c.ride_count::decimal / t.total_count * 100), 4) AS percentage
    FROM counts c
    JOIN total_counts t
    ON c.member_casual = t.member_casual
)
SELECT
    member_casual,
    rideable_type,
    hours,
    SUM(ride_count) AS ride_count,
    total_count,
    ROUND(SUM(percentage), 4) AS percentage
FROM percentage
GROUP BY member_casual, rideable_type, hours, total_count
ORDER BY member_casual, hours, rideable_type;

---- Average Ride Time per hours/days/months. Replace "hours" with "weekday_started", "month_started"
SELECT
    member_casual,
    rideable_type,
    hours,
    ROUND(AVG(ride_time_minutes),2) AS average_ride_time_minutes
FROM cyclistic_bike
GROUP BY member_casual, rideable_type, hours
ORDER BY member_casual, rideable_type, hours;


-- Spatial analysis

----start station
WITH station_map AS (
    SELECT DISTINCT ON (started_station_name)
        started_station_name,
        start_lat,
        start_lng
    FROM
        cyclistic_bike
    WHERE
        started_station_name <> 'On bike lock'
    ORDER BY
        started_station_name
),
top_100_casual_classic_bike AS (
    SELECT
        started_station_name AS station_name,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        started_station_name <> 'On bike lock'
        AND member_casual = 'casual'
        AND rideable_type = 'classic_bike'
    GROUP BY
        started_station_name
    ORDER BY
        count DESC
    LIMIT 100
),
top_100_casual_electric_bike AS (
    SELECT
        start_lat,
        start_lng,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        started_station_name = 'On bike lock'
        AND member_casual = 'casual'
        AND rideable_type = 'electric_bike'
    GROUP BY
        start_lat, start_lng
    ORDER BY
        count DESC
    LIMIT 100
),
top_100_member_classic_bike AS (
    SELECT
        started_station_name AS station_name,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        started_station_name <> 'On bike lock'
        AND member_casual = 'member'
        AND rideable_type = 'classic_bike'
    GROUP BY
        started_station_name
    ORDER BY
        count DESC
    LIMIT 100
),
top_100_member_electric_bike AS (
    SELECT
        start_lat,
        start_lng,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        started_station_name = 'On bike lock'
        AND member_casual = 'member'
        AND rideable_type = 'electric_bike'
    GROUP BY
        start_lat, start_lng
    ORDER BY
        count DESC
    LIMIT 100
)
SELECT
    b.station_name,
    b.count,
    s.start_lat,
    s.start_lng,
    'classic_bike' AS bike_type,
    'casual' AS member_casual
FROM
    top_100_casual_classic_bike b
JOIN
    station_map s ON b.station_name = s.started_station_name

UNION ALL

SELECT
    'On bike lock' AS station_name,
    count,
    start_lat,
    start_lng,
    'electric_bike' AS bike_type,
    'casual' AS member_casual
FROM
    top_100_casual_electric_bike

UNION ALL

SELECT
    b.station_name,
    b.count,
    s.start_lat,
    s.start_lng,
    'classic_bike' AS bike_type,
    'member' AS member_casual
FROM
    top_100_member_classic_bike b
JOIN
    station_map s ON b.station_name = s.started_station_name

UNION ALL

SELECT
    'On bike lock' AS station_name,
    count,
    start_lat,
    start_lng,
    'electric_bike' AS bike_type,
    'member' AS member_casual
FROM
    top_100_member_electric_bike;


---- end station
WITH station_map AS (
    SELECT DISTINCT ON (end_station_name)
        end_station_name,
        end_lat,
        end_lng
    FROM
        cyclistic_bike
    WHERE
        end_station_name <> 'On bike lock'
    ORDER BY
        end_station_name
),
top_100_casual_classic_bike AS (
    SELECT
        end_station_name AS station_name,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        end_station_name <> 'On bike lock'
        AND member_casual = 'casual'
        AND rideable_type = 'classic_bike'
    GROUP BY
        end_station_name
    ORDER BY
        count DESC
    LIMIT 100
),
top_100_casual_electric_bike AS (
    SELECT
        end_lat,
        end_lng,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        end_station_name = 'On bike lock'
        AND member_casual = 'casual'
        AND rideable_type = 'electric_bike'
    GROUP BY
        end_lat, end_lng
    ORDER BY
        count DESC
    LIMIT 100
),
top_100_member_classic_bike AS (
    SELECT
        end_station_name AS station_name,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        end_station_name <> 'On bike lock'
        AND member_casual = 'member'
        AND rideable_type = 'classic_bike'
    GROUP BY
        end_station_name
    ORDER BY
        count DESC
    LIMIT 100
),
top_100_member_electric_bike AS (
    SELECT
        end_lat,
        end_lng,
        COUNT(*) AS count
    FROM
        cyclistic_bike
    WHERE
        end_station_name = 'On bike lock'
        AND member_casual = 'member'
        AND rideable_type = 'electric_bike'
    GROUP BY
        end_lat, end_lng
    ORDER BY
        count DESC
    LIMIT 100
)
SELECT
    b.station_name,
    b.count,
    s.end_lat,
    s.end_lng,
    'classic_bike' AS bike_type,
    'casual' AS member_casual
FROM
    top_100_casual_classic_bike b
JOIN
    station_map s ON b.station_name = s.end_station_name

UNION ALL

SELECT
    'On bike lock' AS station_name,
    count,
    end_lat,
    end_lng,
    'electric_bike' AS bike_type,
    'casual' AS member_casual
FROM
    top_100_casual_electric_bike

UNION ALL

SELECT
    b.station_name,
    b.count,
    s.end_lat,
    s.end_lng,
    'classic_bike' AS bike_type,
    'member' AS member_casual
FROM
    top_100_member_classic_bike b
JOIN
    station_map s ON b.station_name = s.end_station_name

UNION ALL

SELECT
    'On bike lock' AS station_name,
    count,
    end_lat,
    end_lng,
    'electric_bike' AS bike_type,
    'member' AS member_casual
FROM
    top_100_member_electric_bike;
