-- =====================================================================
--  queries.sql - 15+ demonstration queries (run after schema.sql + seed.sql)
-- =====================================================================
USE movie_booking;

-- 1. All movies
SELECT * FROM movies;
-- 2. Movies by genre (JOIN through the M:N table)
SELECT m.title, g.genre_name FROM movies m
JOIN movie_genres mg ON mg.movie_id = m.movie_id JOIN genres g ON g.genre_id = mg.genre_id
WHERE g.genre_name = 'Sci-Fi' ORDER BY m.title;
-- 3. Upcoming shows for one movie
SELECT s.show_id, s.show_date, s.show_time, s.ticket_price FROM shows s
JOIN movies m ON m.movie_id = s.movie_id WHERE m.title = 'Inception' AND s.show_date >= CURDATE()
ORDER BY s.show_date, s.show_time;
-- 4. Shows with movie, theatre and screen names (4-table INNER JOIN)
SELECT m.title, t.name AS theatre, sc.screen_name, s.show_date, s.show_time, s.ticket_price
FROM shows s JOIN movies m ON m.movie_id = s.movie_id JOIN screens sc ON sc.screen_id = s.screen_id
JOIN theatres t ON t.theatre_id = sc.theatre_id ORDER BY s.show_date, s.show_time;
-- 5. Bookings of one user (uses the VIEW)
SELECT booking_id, movie_title, theatre_name, show_date, seats, total_amount
FROM booking_details_view WHERE user_name = 'Rahul Sharma';
-- 6. Total revenue
SELECT SUM(amount) AS total_revenue FROM payments WHERE status = 'SUCCESS';
-- 7. Most booked movie (by tickets sold)
SELECT m.title, COUNT(bs.seat_id) AS tickets FROM movies m
JOIN shows s ON s.movie_id = m.movie_id JOIN booking_seats bs ON bs.show_id = s.show_id
GROUP BY m.movie_id, m.title ORDER BY tickets DESC LIMIT 1;
-- 8. Most popular theatre
SELECT t.name, COUNT(bs.seat_id) AS tickets FROM theatres t
JOIN screens sc ON sc.theatre_id = t.theatre_id JOIN shows s ON s.screen_id = sc.screen_id
JOIN booking_seats bs ON bs.show_id = s.show_id
GROUP BY t.theatre_id, t.name ORDER BY tickets DESC LIMIT 1;
-- 9. Bookings per movie (LEFT JOIN keeps movies with zero bookings)
SELECT m.title, COUNT(DISTINCT b.booking_id) AS bookings FROM movies m
LEFT JOIN shows s ON s.movie_id = m.movie_id
LEFT JOIN bookings b ON b.show_id = s.show_id AND b.status = 'CONFIRMED'
GROUP BY m.movie_id, m.title ORDER BY bookings DESC;
-- 10. Users with more than one booking (GROUP BY + HAVING)
SELECT u.full_name, COUNT(*) AS bookings FROM users u JOIN bookings b ON b.user_id = u.user_id
GROUP BY u.user_id, u.full_name HAVING COUNT(*) > 1;
-- 11. Full booking details through the VIEW (7 joined tables)
SELECT * FROM booking_details_view ORDER BY booking_time DESC;
-- 12. Shows that still have free seats (correlated subquery + HAVING-style filter)
SELECT * FROM (
  SELECT s.show_id, m.title, sc.total_rows * sc.seats_per_row
         - (SELECT COUNT(*) FROM booking_seats bs WHERE bs.show_id = s.show_id) AS available
  FROM shows s JOIN movies m ON m.movie_id = s.movie_id JOIN screens sc ON sc.screen_id = s.screen_id
) x WHERE available > 0;
-- 13. Average rating per language, only those above 8 (AVG + GROUP BY + HAVING)
SELECT language, AVG(rating) AS avg_rating FROM movies WHERE status = 'NOW_SHOWING'
GROUP BY language HAVING AVG(rating) > 8;
-- 14. Highest-selling movie by revenue (subquery inside a CTE)
WITH revenue AS (
  SELECT m.title, SUM(b.total_amount) AS rev FROM movies m JOIN shows s ON s.movie_id = m.movie_id
  JOIN bookings b ON b.show_id = s.show_id WHERE b.status = 'CONFIRMED' GROUP BY m.movie_id, m.title)
SELECT title, rev FROM revenue WHERE rev = (SELECT MAX(rev) FROM revenue);
-- 15. Revenue per theatre
SELECT t.name, SUM(b.total_amount) AS revenue FROM theatres t
JOIN screens sc ON sc.theatre_id = t.theatre_id JOIN shows s ON s.screen_id = sc.screen_id
JOIN bookings b ON b.show_id = s.show_id WHERE b.status = 'CONFIRMED'
GROUP BY t.theatre_id, t.name ORDER BY revenue DESC;
-- 16. Users who never booked (subquery with NOT IN)
SELECT full_name FROM users WHERE role = 'USER' AND user_id NOT IN (SELECT user_id FROM bookings);

-- 17. INSERT / UPDATE / DELETE with a transaction, then undone (ACID demo)
START TRANSACTION;
UPDATE shows SET ticket_price = ticket_price + 50 WHERE show_id = 1;
SELECT show_id, ticket_price FROM shows WHERE show_id = 1;
ROLLBACK;
SELECT show_id, ticket_price FROM shows WHERE show_id = 1;   -- back to the old price

-- 18. Double-booking is blocked by UNIQUE (show_id, seat_id): this FAILS with error 1062
-- INSERT INTO booking_seats (booking_id, seat_id, show_id)
--   SELECT 3, seat_id, 1 FROM seats WHERE screen_id = 1 AND row_label = 'C' AND seat_number = 4;

-- 19. Trigger + stored procedure: cancel booking 1 as user 2 (seats freed, payment refunded)
-- CALL sp_cancel_booking(1, 2);
-- SELECT * FROM booking_details_view WHERE booking_id = 1;
