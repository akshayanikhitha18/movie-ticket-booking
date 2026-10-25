# Movie Ticket Booking System (DBMS Mini Project)
Flask + MySQL + HTML/CSS/JS. Logins: `admin@cinema.com / Admin@123`, `rahul@example.com / User@123`.

## Run on Windows
1. Install Python 3 (tick "Add to PATH") and MySQL Server 8.x (remember the root password).
2. Open Command Prompt in this folder:
   ```
   python -m venv venv
   venv\Scripts\activate
   pip install -r requirements.txt
   mysql -u root -p < schema.sql
   mysql -u root -p movie_booking < seed.sql
   ```
   (If `mysql` is not recognised, add `C:\Program Files\MySQL\MySQL Server 8.0\bin` to PATH.)
3. Open `database.py`, set your MySQL password, then `python app.py` and visit http://127.0.0.1:5000

## Test cases (fill the last column while testing)
| # | Test | Steps | Expected | Status |
|---|---|---|---|---|
| 1 | Registration | Register a new email | Redirect to login, row in `users` with hashed password | |
| 2 | Duplicate registration | Register same email | "already registered" message | |
| 3 | Login | rahul@example.com / User@123 | Home page, "Hi, Rahul" in navbar | |
| 4 | Invalid login | Wrong password | "Invalid email or password" | |
| 5 | Movie search | Search "sci" | Inception, Interstellar shown | |
| 6 | Show selection | Open Inception | Table of shows with theatre, date, time | |
| 7 | Seat selection | Click 3 seats | Count 3, total = 3 × price, booked seats greyed | |
| 8 | Booking + payment | Proceed, choose UPI, pay | Confirmation page; rows in bookings, booking_seats, payments | |
| 9 | Duplicate seat booking | Open seats page in two tabs, select same seat, confirm in both | Second one rolls back with "just booked" message | |
| 10 | Cancellation | My Bookings, Cancel | Status CANCELLED, payment REFUNDED, seats free again | |
| 11 | Admin add movie | Admin, Add Movie | Appears on home page | |
| 12 | Admin delete movie | Delete it | Gone from home; its shows deleted (CASCADE) | |
| 13 | Admin create show | Create Show | Appears on the movie page; same screen+date+time again gives an error | |
| 14 | Access control | Log in as user, open /admin | Redirected to login | |

## DBMS concepts demonstrated (only what is implemented)
- **Database / DBMS / RDBMS:** `movie_booking` is the database. MySQL is the DBMS, and it is relational because data lives in related tables.
- **Primary key:** every table has one (`booking_id`, `show_id`...). **Composite key:** `movie_genres(movie_id, genre_id)` and `booking_seats(booking_id, seat_id)`.
- **Candidate key:** `users.email` and `payments.booking_id` are UNIQUE, so they could identify a row as well as the primary key does.
- **Foreign key / referential integrity:** `shows.movie_id → movies`, `bookings.user_id → users` and others. You cannot book a non-existent show. ON DELETE CASCADE removes dependent rows.
- **Entity integrity:** primary keys are NOT NULL and unique.
- **Constraints:** NOT NULL, UNIQUE, CHECK (price > 0, rating 0–10), DEFAULT (status, timestamps), ENUM.
- **Normalization:** 1NF (atomic values), 2NF (no partial dependency in composite-key tables), 3NF (no movie/theatre names in bookings). The one documented exception is `booking_seats.show_id`, kept to enforce uniqueness.
- **SQL / CRUD:** DML in `app.py`, 15+ queries in `queries.sql`.
- **Joins:** INNER JOIN and LEFT JOIN. **Aggregates, GROUP BY, HAVING:** queries 6–10, 13, 15. **Subqueries:** 12, 14, 16.
- **Transaction + ACID:** `/confirm` in `app.py`.
  - Atomicity: booking, seats and payment commit together, or ROLLBACK.
  - Consistency: constraints leave the database valid.
  - Isolation: `SELECT ... FOR UPDATE` on the show row.
  - Durability: COMMIT persists.
- **Concurrency:** the show-row lock, plus `UNIQUE (show_id, seat_id)` as the final guard.
- **Indexing:** `idx_shows_movie_date`, `idx_bookings_user`, plus the automatic indexes on PK, UNIQUE and FK columns.
- **View:** `booking_details_view`. **Trigger:** `trg_booking_cancelled`. **Stored procedure:** `sp_cancel_booking`.

## Viva Q&A (this project)
1. **How do you stop double booking?** `booking_seats` has `UNIQUE (show_id, seat_id)`. `/confirm` also locks the show row with `FOR UPDATE` and re-checks seat availability. If anything fails, it rolls back.
2. **Why is `booking_seats` a separate table?** A booking has many seats and a seat belongs to many bookings over time (different shows). That is a many-to-many relationship, which needs a junction table (1NF).
3. **Why does `movie_genres` exist?** Movie and genre are M:N. Storing "Sci-Fi, Thriller" in one column would break 1NF.
4. **Which normal form is the schema in?** 3NF. The only deliberate exception is `show_id` in `booking_seats`.
5. **Why store `total_amount` if it can be calculated?** It is a price snapshot. If the admin changes the ticket price later, old bookings stay correct.
6. **What does the trigger do?** On cancellation it frees the seats and marks the payment REFUNDED, so this happens whoever cancels the booking.
7. **Why a stored procedure for cancel?** It centralises the rules (owner only, still confirmed, show not started) in the database.
8. **What is the view for?** It hides a 7-table join. My Bookings, the confirmation page and the admin list all use it.
9. **Atomicity example?** If the payment insert fails after the booking insert, ROLLBACK removes the booking and its seats too.
10. **Why password hashing?** Passwords are stored as salted hashes (`werkzeug`), so a database leak does not reveal them.
11. **ON DELETE CASCADE?** Deleting a movie deletes its shows, and deleting a show deletes its bookings, so no orphan rows remain.
12. **Why LEFT JOIN in `/api/seats`?** It lists every seat, and `booked` is true only where a `booking_seats` row exists.
