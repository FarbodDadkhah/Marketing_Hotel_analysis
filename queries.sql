-----------------------START: Importing data, CREATING Tables, -----------------------------------
-- CLI command.
-- \COPY hotel_bookings FROM '/path/to/hotel_bookings.csv' DELIMITER ',' CSV HEADER;
-- Start: Creating foundational tables and inserting data

-- Create the guests table to store guest details
CREATE TABLE IF NOT EXISTS guests (
    id INT PRIMARY KEY,
    adults INT,
    children INT,
    babies INT,
    nationality VARCHAR(100),
    is_repeat_customer INT
);

-- Create the bookings table to store booking details
CREATE TABLE IF NOT EXISTS bookings (
    id INT PRIMARY KEY,
    guest_id INT,
    hotel TEXT,
    market_segment VARCHAR(100),
    lead_time INT,
    is_canceled INT,
    FOREIGN KEY (guest_id) REFERENCES guests(id)
);

-- Alter the guests table to fix data type inconsistencies
ALTER TABLE guests ALTER COLUMN is_repeat_customer TYPE INT;

-- Insert unique guest records into the guests table
INSERT INTO guests (id, adults, children, babies, nationality, is_repeat_customer)
SELECT DISTINCT
    ROW_NUMBER() OVER (ORDER BY country) AS id, -- Generate unique IDs
    adults,
    children,
    babies,
    country,
    is_repeated_guest
FROM hotel_bookings;

-- Insert unique booking records into the bookings table
INSERT INTO bookings (id, guest_id, hotel, market_segment, lead_time, is_canceled)
SELECT
    ROW_NUMBER() OVER (ORDER BY o.country) AS id, -- Generate unique IDs for bookings
    g.id,
    o.hotel,
    o.market_segment,
    o.lead_time,
    o.is_canceled
FROM hotel_bookings AS o
JOIN guests AS g
ON o.country = g.nationality AND o.id = g.id;

-- End: Creating foundational tables and inserting data

-- Highlight guest composition by nationality
SELECT country,  
       COUNT(*) AS total_bookings, 
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM hotel_bookings), 2) AS percentage
FROM hotel_bookings
WHERE country IN ('USA', 'GBR', 'ITA')
GROUP BY country
ORDER BY total_bookings DESC;

-- Add and calculate new columns for party type and revenue in hotel_bookings
ALTER TABLE hotel_bookings ADD COLUMN party_type VARCHAR(50) DEFAULT 'adult';
UPDATE hotel_bookings
SET party_type = CASE 
                    WHEN children + babies > 0 THEN 'family'
                    ELSE 'adults'
                END;

ALTER TABLE hotel_bookings ADD COLUMN revenue INT;
UPDATE hotel_bookings
SET revenue = (children + babies + adults) * adr;

-- Analyze booking counts by country and party type
SELECT country, 
       party_type, 
       COUNT(*) AS bookings_count
FROM hotel_bookings
GROUP BY country, party_type
ORDER BY country, bookings_count DESC;

-- Analyze market segments and cancellation rates
SELECT market_segment, 
       COUNT(*) AS total_bookings, 
       SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) AS cancellations, 
       ROUND(100.0 * SUM(CASE WHEN is_canceled = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS cancellation_rate
FROM hotel_bookings
GROUP BY market_segment
ORDER BY total_bookings DESC;

-- Analyze booking trends by month and party type
SELECT  arrival_date_month AS month, 
       party_type, 
       COUNT(*) AS bookings
FROM hotel_bookings
WHERE country = 'GBR'
GROUP BY arrival_date_month, party_type
ORDER BY bookings DESC, month;

-- Analyze revenue generation by country and party type
SELECT country, 
       party_type, 
       SUM(revenue) AS total_room_revenue, 
       COUNT(*) AS total_bookings 
FROM hotel_bookings 
WHERE is_canceled = 0 AND country IN ('GBR', 'USA', 'ITA')
GROUP BY country, party_type
ORDER BY SUM(revenue) DESC;

-- Identify records with missing nationalities in hotel_bookings
SELECT b.id, 
       COALESCE(o.country, 'Unknown') AS nationality, 
       b.market_segment, 
       o.revenue
FROM bookings AS b
LEFT JOIN hotel_bookings AS o ON o.id = b.id
WHERE o.country IS NULL;

-- Analyze guests and their associated bookings
SELECT 
    g.id, 
    g.nationality, 
    b.id, 
    b.hotel, 
    b.market_segment, 
    b.is_canceled  
FROM guests AS g
LEFT JOIN bookings AS b 
    ON g.id = b.guest_id
ORDER BY b.hotel;

-- Add revenue column to bookings and populate it from hotel_bookings
ALTER TABLE bookings ADD COLUMN revenue INT;
UPDATE bookings AS b
SET revenue = hb.revenue
FROM hotel_bookings AS hb
WHERE b.id = hb.id;

-- Use a CTE to calculate total revenue by nationality and filter by a threshold
WITH revenue_by_nationality AS (
    SELECT g.nationality, 
           SUM(b.revenue) AS total_revenue
    FROM bookings AS b
    JOIN guests AS g ON b.guest_id = g.id
    GROUP BY g.nationality
)
SELECT nationality, total_revenue
FROM revenue_by_nationality
WHERE total_revenue > 50000 
  AND nationality IN ('GBR', 'USA', 'ITA')
ORDER BY total_revenue DESC;

-- Rank guests by their total revenue within each nationality using a window function
SELECT g.nationality, 
       g.id, 
       SUM(b.revenue) AS total_revenue,
       RANK() OVER (PARTITION BY g.nationality ORDER BY SUM(b.revenue) DESC) AS rank_within_nationality
FROM bookings AS b
JOIN guests AS g ON b.guest_id = g.id
GROUP BY g.nationality, g.id
ORDER BY g.nationality, rank_within_nationality;
