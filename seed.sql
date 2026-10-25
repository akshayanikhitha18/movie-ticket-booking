-- =====================================================================
--  seed.sql  -  sample data.  Run AFTER schema.sql:
--  mysql -u root -p movie_booking < seed.sql
--  Logins:  admin@cinema.com / Admin@123      rahul@example.com, priya@example.com,
--           arjun@example.com / User@123
-- =====================================================================
USE movie_booking;

INSERT INTO users (user_id, full_name, email, password_hash, role) VALUES
(1,'Admin','admin@cinema.com','scrypt:32768:8:1$KNbnwWFWnxBZp3gf$aacd683ec7ed3fe6a371536329f7d13c11dbcad3cce66704dd030f8c391e2bc1838a4e7d1f060071f9e02b2483c92e2688e9cadc63f12dfa6f414b0d2021b013','ADMIN'),
(2,'Rahul Sharma','rahul@example.com','scrypt:32768:8:1$deOB94cI1U0d5exU$18c3187dd918467b1cd21c4d4a562c21d3c51d062a47c2c34b1c4ff88b1d63925967b3d7cda21ba2714555480f5aacd452d1ba0eb7718d546f03ca7da56799da','USER'),
(3,'Priya Nair','priya@example.com','scrypt:32768:8:1$deOB94cI1U0d5exU$18c3187dd918467b1cd21c4d4a562c21d3c51d062a47c2c34b1c4ff88b1d63925967b3d7cda21ba2714555480f5aacd452d1ba0eb7718d546f03ca7da56799da','USER'),
(4,'Arjun Rao','arjun@example.com','scrypt:32768:8:1$deOB94cI1U0d5exU$18c3187dd918467b1cd21c4d4a562c21d3c51d062a47c2c34b1c4ff88b1d63925967b3d7cda21ba2714555480f5aacd452d1ba0eb7718d546f03ca7da56799da','USER');

INSERT INTO genres (genre_id, genre_name) VALUES
(1,'Sci-Fi'),(2,'Thriller'),(3,'Drama'),(4,'Action'),(5,'Comedy'),(6,'Biography'),(7,'Adventure');

INSERT INTO movies (movie_id, title, description, duration_min, language, rating, release_date, poster_url, status) VALUES
(1,'Inception','A thief who steals secrets through dream-sharing is offered a chance to erase his criminal past by planting an idea in a target''s mind.',148,'English',8.8,'2010-07-16','https://placehold.co/300x450/1a1a2e/e94560?text=Inception','NOW_SHOWING'),
(2,'Interstellar','A team of explorers travels through a wormhole in space to ensure humanity''s survival.',169,'English',8.7,'2014-11-07','https://placehold.co/300x450/0f3460/e94560?text=Interstellar','NOW_SHOWING'),
(3,'3 Idiots','Three engineering students navigate friendship, pressure and the true meaning of education.',170,'Hindi',8.4,'2009-12-25','https://placehold.co/300x450/16213e/e94560?text=3+Idiots','NOW_SHOWING'),
(4,'RRR','Two revolutionaries form an unlikely friendship while fighting for their people against colonial rule.',182,'Telugu',7.8,'2022-03-25','https://placehold.co/300x450/533483/ffffff?text=RRR','NOW_SHOWING'),
(5,'Dangal','A former wrestler trains his daughters to become world-class wrestlers.',161,'Hindi',8.3,'2016-12-23','https://placehold.co/300x450/1a1a2e/f5a623?text=Dangal','NOW_SHOWING'),
(6,'Avatar: Fire and Ash','The Na''vi story continues with a new threat on Pandora.',190,'English',0.0,'2026-12-19','https://placehold.co/300x450/0f3460/ffffff?text=Avatar','UPCOMING'),
(7,'Project Hail Mary','A lone astronaut wakes up on a spacecraft with no memory and a mission to save Earth.',156,'English',0.0,'2027-03-20','https://placehold.co/300x450/16213e/ffffff?text=Hail+Mary','UPCOMING');

INSERT INTO movie_genres (movie_id, genre_id) VALUES
(1,1),(1,2),(2,1),(2,3),(3,5),(3,3),(4,4),(4,7),(5,6),(5,3),(6,1),(6,7),(7,1),(7,7);

INSERT INTO theatres (theatre_id, name, city, address) VALUES
(1,'PVR Cinemas Orion Mall','Bengaluru','Dr Rajkumar Road, Rajajinagar'),
(2,'INOX Garuda Mall','Bengaluru','Magrath Road, Ashok Nagar'),
(3,'Cinepolis Nexus Shantiniketan','Bengaluru','Whitefield Main Road');

INSERT INTO screens (screen_id, theatre_id, screen_name, total_rows, seats_per_row) VALUES
(1,1,'Screen 1',6,8),
(2,1,'Screen 2',5,10),
(3,2,'Screen 1',6,8),
(4,3,'Screen 1',5,10);

-- Seats are GENERATED from each screen's rows x seats_per_row (A1..A8, B1..B8 ...)
INSERT INTO seats (screen_id, row_label, seat_number)
SELECT sc.screen_id, CHAR(64 + r.n), c.n
FROM screens sc
JOIN (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
      UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8) r ON r.n <= sc.total_rows
JOIN (SELECT 1 n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
      UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
      UNION ALL SELECT 10) c ON c.n <= sc.seats_per_row;

-- Shows use CURDATE() so the sample data is always current.
INSERT INTO shows (show_id, movie_id, screen_id, show_date, show_time, ticket_price) VALUES
(1,1,1,CURDATE() + INTERVAL 1 DAY,'10:00:00',250.00),
(2,1,1,CURDATE() + INTERVAL 1 DAY,'18:30:00',300.00),
(3,2,2,CURDATE() + INTERVAL 1 DAY,'14:00:00',280.00),
(4,3,3,CURDATE() + INTERVAL 1 DAY,'11:00:00',200.00),
(5,4,3,CURDATE() + INTERVAL 2 DAY,'19:00:00',320.00),
(6,5,4,CURDATE() + INTERVAL 1 DAY,'16:00:00',220.00),
(7,2,1,CURDATE() + INTERVAL 2 DAY,'21:00:00',300.00),
(8,3,4,CURDATE() + INTERVAL 2 DAY,'13:00:00',200.00),
(9,4,2,CURDATE() + INTERVAL 3 DAY,'18:00:00',300.00);

-- Sample bookings (total_amount = ticket_price x number of seats)
INSERT INTO bookings (booking_id, user_id, show_id, total_amount, status) VALUES
(1,2,1,500.00,'CONFIRMED'),
(2,3,2,900.00,'CONFIRMED'),
(3,2,4,400.00,'CONFIRMED'),
(4,4,5,640.00,'CONFIRMED'),
(5,3,6,440.00,'CONFIRMED');

INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT 1, 1, seat_id FROM seats WHERE screen_id = 1 AND (row_label, seat_number) IN (('C',4),('C',5));
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT 2, 2, seat_id FROM seats WHERE screen_id = 1 AND (row_label, seat_number) IN (('D',3),('D',4),('D',5));
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT 3, 4, seat_id FROM seats WHERE screen_id = 3 AND (row_label, seat_number) IN (('A',1),('A',2));
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT 4, 5, seat_id FROM seats WHERE screen_id = 3 AND (row_label, seat_number) IN (('B',5),('B',6));
INSERT INTO booking_seats (booking_id, show_id, seat_id)
SELECT 5, 6, seat_id FROM seats WHERE screen_id = 4 AND (row_label, seat_number) IN (('E',9),('E',10));

INSERT INTO payments (booking_id, method, amount, status) VALUES
(1,'UPI',500.00,'SUCCESS'),
(2,'CARD',900.00,'SUCCESS'),
(3,'UPI',400.00,'SUCCESS'),
(4,'CARD',640.00,'SUCCESS'),
(5,'CASH',440.00,'SUCCESS');
