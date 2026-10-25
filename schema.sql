-- =====================================================================
--  Movie Ticket Booking System  -  schema.sql   (MySQL 8.0+)
--  Run:  mysql -u root -p < schema.sql
-- =====================================================================
DROP DATABASE IF EXISTS movie_booking;
CREATE DATABASE movie_booking CHARACTER SET utf8mb4;
USE movie_booking;

-- ---------- 1. USERS ----------
CREATE TABLE users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(120) NOT NULL UNIQUE,          -- candidate key
    password_hash VARCHAR(255) NOT NULL,                 -- never plain text
    role          ENUM('USER','ADMIN') NOT NULL DEFAULT 'USER',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------- 2. GENRES and MOVIES (M:N through movie_genres) ----------
CREATE TABLE genres (
    genre_id   INT AUTO_INCREMENT PRIMARY KEY,
    genre_name VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE movies (
    movie_id     INT AUTO_INCREMENT PRIMARY KEY,
    title        VARCHAR(150) NOT NULL,
    description  TEXT,
    duration_min INT NOT NULL,
    language     VARCHAR(30) NOT NULL,
    rating       DECIMAL(3,1) NOT NULL DEFAULT 0.0,
    release_date DATE NOT NULL,
    poster_url   VARCHAR(255),
    status       ENUM('NOW_SHOWING','UPCOMING') NOT NULL DEFAULT 'NOW_SHOWING',
    CONSTRAINT chk_movie_duration CHECK (duration_min > 0),
    CONSTRAINT chk_movie_rating   CHECK (rating BETWEEN 0 AND 10)
);

CREATE TABLE movie_genres (
    movie_id INT NOT NULL,
    genre_id INT NOT NULL,
    PRIMARY KEY (movie_id, genre_id),                    -- composite key
    FOREIGN KEY (movie_id) REFERENCES movies(movie_id) ON DELETE CASCADE,
    FOREIGN KEY (genre_id) REFERENCES genres(genre_id) ON DELETE CASCADE
);

-- ---------- 3. THEATRES -> SCREENS -> SEATS (1:N chain) ----------
CREATE TABLE theatres (
    theatre_id INT AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(100) NOT NULL,
    city       VARCHAR(60)  NOT NULL,
    address    VARCHAR(200) NOT NULL,
    UNIQUE (name, city)
);

CREATE TABLE screens (
    screen_id      INT AUTO_INCREMENT PRIMARY KEY,
    theatre_id     INT NOT NULL,
    screen_name    VARCHAR(30) NOT NULL,
    total_rows     INT NOT NULL,
    seats_per_row  INT NOT NULL,
    UNIQUE (theatre_id, screen_name),
    CONSTRAINT chk_screen_size CHECK (total_rows BETWEEN 1 AND 26 AND seats_per_row BETWEEN 1 AND 20),
    FOREIGN KEY (theatre_id) REFERENCES theatres(theatre_id) ON DELETE CASCADE
);

CREATE TABLE seats (
    seat_id     INT AUTO_INCREMENT PRIMARY KEY,
    screen_id   INT NOT NULL,
    row_label   CHAR(1) NOT NULL,
    seat_number INT NOT NULL,
    UNIQUE (screen_id, row_label, seat_number),          -- a physical seat exists once
    FOREIGN KEY (screen_id) REFERENCES screens(screen_id) ON DELETE CASCADE
);

-- ---------- 4. SHOWS ----------
CREATE TABLE shows (
    show_id      INT AUTO_INCREMENT PRIMARY KEY,
    movie_id     INT NOT NULL,
    screen_id    INT NOT NULL,
    show_date    DATE NOT NULL,
    show_time    TIME NOT NULL,
    ticket_price DECIMAL(8,2) NOT NULL,
    UNIQUE (screen_id, show_date, show_time),            -- no two shows on one screen at once
    CONSTRAINT chk_price CHECK (ticket_price > 0),
    FOREIGN KEY (movie_id)  REFERENCES movies(movie_id)   ON DELETE CASCADE,
    FOREIGN KEY (screen_id) REFERENCES screens(screen_id) ON DELETE CASCADE
);
CREATE INDEX idx_shows_movie_date ON shows (movie_id, show_date);

-- ---------- 5. BOOKINGS, BOOKING_SEATS, PAYMENTS ----------
CREATE TABLE bookings (
    booking_id   INT AUTO_INCREMENT PRIMARY KEY,
    user_id      INT NOT NULL,
    show_id      INT NOT NULL,
    booking_time DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) NOT NULL,
    status       ENUM('CONFIRMED','CANCELLED') NOT NULL DEFAULT 'CONFIRMED',
    CONSTRAINT chk_total CHECK (total_amount >= 0),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (show_id) REFERENCES shows(show_id) ON DELETE CASCADE
);
CREATE INDEX idx_bookings_user ON bookings (user_id);

-- Junction table for Bookings <-> Seats (M:N).
-- show_id is stored here on purpose: UNIQUE (show_id, seat_id) is what makes
-- double booking impossible at the database level.
CREATE TABLE booking_seats (
    booking_id INT NOT NULL,
    seat_id    INT NOT NULL,
    show_id    INT NOT NULL,
    PRIMARY KEY (booking_id, seat_id),
    UNIQUE KEY uq_show_seat (show_id, seat_id),
    FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE,
    FOREIGN KEY (seat_id)    REFERENCES seats(seat_id),
    FOREIGN KEY (show_id)    REFERENCES shows(show_id) ON DELETE CASCADE
);

CREATE TABLE payments (
    payment_id INT AUTO_INCREMENT PRIMARY KEY,
    booking_id INT NOT NULL UNIQUE,                      -- 1 booking : 1 payment
    method     ENUM('UPI','CARD','CASH') NOT NULL,
    amount     DECIMAL(10,2) NOT NULL,
    status     ENUM('SUCCESS','FAILED','REFUNDED') NOT NULL DEFAULT 'SUCCESS',
    paid_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_pay_amount CHECK (amount >= 0),
    FOREIGN KEY (booking_id) REFERENCES bookings(booking_id) ON DELETE CASCADE
);

-- =====================================================================
--  VIEW: one row per booking with everything an admin / user needs
-- =====================================================================
CREATE VIEW booking_details_view AS
SELECT  b.booking_id, b.booking_time, b.status AS booking_status, b.total_amount,
        u.user_id, u.full_name AS user_name, u.email,
        m.movie_id, m.title AS movie_title,
        t.theatre_id, t.name AS theatre_name, sc.screen_name,
        s.show_id, s.show_date, s.show_time,
        GROUP_CONCAT(CONCAT(se.row_label, se.seat_number)
                     ORDER BY se.row_label, se.seat_number SEPARATOR ', ') AS seats,
        p.method AS payment_method, p.status AS payment_status
FROM bookings b
JOIN users    u  ON u.user_id    = b.user_id
JOIN shows    s  ON s.show_id    = b.show_id
JOIN movies   m  ON m.movie_id   = s.movie_id
JOIN screens  sc ON sc.screen_id = s.screen_id
JOIN theatres t  ON t.theatre_id = sc.theatre_id
LEFT JOIN payments      p  ON p.booking_id  = b.booking_id
LEFT JOIN booking_seats bs ON bs.booking_id = b.booking_id
LEFT JOIN seats         se ON se.seat_id    = bs.seat_id
GROUP BY b.booking_id, b.booking_time, b.status, b.total_amount, u.user_id, u.full_name,
         u.email, m.movie_id, m.title, t.theatre_id, t.name, sc.screen_name,
         s.show_id, s.show_date, s.show_time, p.method, p.status;

-- =====================================================================
--  TRIGGER: when a booking becomes CANCELLED, free its seats and mark
--  the payment REFUNDED automatically (keeps data consistent no matter
--  which program does the cancelling).
-- =====================================================================
DELIMITER $$
CREATE TRIGGER trg_booking_cancelled
AFTER UPDATE ON bookings
FOR EACH ROW
BEGIN
    IF OLD.status = 'CONFIRMED' AND NEW.status = 'CANCELLED' THEN
        DELETE FROM booking_seats WHERE booking_id = NEW.booking_id;
        UPDATE payments SET status = 'REFUNDED' WHERE booking_id = NEW.booking_id;
    END IF;
END$$

-- =====================================================================
--  STORED PROCEDURE: cancel a booking safely. Only the owner can cancel,
--  and only a CONFIRMED booking for a show that has not started yet.
--  The trigger above then releases seats and refunds the payment.
-- =====================================================================
CREATE PROCEDURE sp_cancel_booking(IN p_booking_id INT, IN p_user_id INT)
BEGIN
    DECLARE v_count INT;
    SELECT COUNT(*) INTO v_count
    FROM bookings b JOIN shows s ON s.show_id = b.show_id
    WHERE b.booking_id = p_booking_id AND b.user_id = p_user_id
      AND b.status = 'CONFIRMED'
      AND TIMESTAMP(s.show_date, s.show_time) > NOW();

    IF v_count = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Booking cannot be cancelled';
    END IF;

    UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking_id;
END$$
DELIMITER ;
