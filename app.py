"""Movie Ticket Booking System - Flask routes."""
from functools import wraps
import mysql.connector
from flask import (Flask, render_template, request, redirect, url_for,
                   session, flash, jsonify, abort)
from werkzeug.security import generate_password_hash, check_password_hash
from database import get_connection, query, execute

app = Flask(__name__)
app.secret_key = "change-this-secret-key"

# ---------- template filters (format dates / times) ----------
@app.template_filter("dt")
def fmt_date(d):
    return d.strftime("%d %b %Y")

@app.template_filter("tm")
def fmt_time(t):                      # MySQL TIME arrives as timedelta
    h, m = divmod(int(t.total_seconds()) // 60, 60)
    return f"{(h % 12) or 12}:{m:02d} {'AM' if h < 12 else 'PM'}"

@app.template_filter("tm24")
def fmt_time24(t):
    h, m = divmod(int(t.total_seconds()) // 60, 60)
    return f"{h:02d}:{m:02d}"

# ---------- access control ----------
def login_required(f):
    @wraps(f)
    def wrapper(*a, **k):
        if "user_id" not in session:
            flash("Please login first.")
            return redirect(url_for("login"))
        return f(*a, **k)
    return wrapper

def admin_required(f):
    @wraps(f)
    def wrapper(*a, **k):
        if session.get("role") != "ADMIN":
            flash("Admin access only.")
            return redirect(url_for("login"))
        return f(*a, **k)
    return wrapper

# ---------- authentication ----------
@app.route("/register", methods=["GET", "POST"])
def register():
    if request.method == "POST":
        try:
            execute("INSERT INTO users (full_name, email, password_hash) VALUES (%s,%s,%s)",
                    (request.form["name"], request.form["email"].lower(),
                     generate_password_hash(request.form["password"])))
            flash("Registered! Please login.")
            return redirect(url_for("login"))
        except mysql.connector.IntegrityError:      # UNIQUE(email) violated
            flash("That email is already registered.")
    return render_template("register.html")

@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        user = query("SELECT * FROM users WHERE email=%s", (request.form["email"].lower(),), one=True)
        if user and check_password_hash(user["password_hash"], request.form["password"]):
            session.update(user_id=user["user_id"], name=user["full_name"], role=user["role"])
            return redirect(url_for("admin" if user["role"] == "ADMIN" else "index"))
        flash("Invalid email or password.")
    return render_template("login.html")

@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("index"))

# ---------- movies ----------
MOVIE_SQL = """SELECT m.*, GROUP_CONCAT(g.genre_name SEPARATOR ', ') AS genres
               FROM movies m
               LEFT JOIN movie_genres mg ON mg.movie_id = m.movie_id
               LEFT JOIN genres g ON g.genre_id = mg.genre_id
               {where} GROUP BY m.movie_id ORDER BY m.title"""

@app.route("/")
def index():
    like = "%" + request.args.get("q", "").strip() + "%"
    where = "WHERE m.status=%s AND (m.title LIKE %s OR g.genre_name LIKE %s)"
    sql = MOVIE_SQL.format(where=where)
    now = query(sql, ("NOW_SHOWING", like, like))
    upcoming = query(sql, ("UPCOMING", like, like))
    return render_template("index.html", now=now, upcoming=upcoming)

@app.route("/movie/<int:movie_id>")
def movie_details(movie_id):
    movie = query(MOVIE_SQL.format(where="WHERE m.movie_id=%s"), (movie_id,), one=True)
    if not movie:
        abort(404)
    shows = query("""SELECT s.show_id, s.show_date, s.show_time, s.ticket_price,
                            t.name AS theatre, sc.screen_name,
                            sc.total_rows * sc.seats_per_row
                              - (SELECT COUNT(*) FROM booking_seats bs WHERE bs.show_id = s.show_id) AS available
                     FROM shows s
                     JOIN screens sc ON sc.screen_id = s.screen_id
                     JOIN theatres t ON t.theatre_id = sc.theatre_id
                     WHERE s.movie_id = %s AND TIMESTAMP(s.show_date, s.show_time) > NOW()
                     ORDER BY s.show_date, t.name, s.show_time""", (movie_id,))
    return render_template("movie_details.html", movie=movie, shows=shows)

# ---------- seats ----------
SHOW_SQL = """SELECT s.show_id, s.show_date, s.show_time, s.ticket_price, s.screen_id,
                     m.title, t.name AS theatre, sc.screen_name
              FROM shows s JOIN movies m ON m.movie_id = s.movie_id
              JOIN screens sc ON sc.screen_id = s.screen_id
              JOIN theatres t ON t.theatre_id = sc.theatre_id
              WHERE s.show_id = %s"""

@app.route("/seats/<int:show_id>")
def seats(show_id):
    show = query(SHOW_SQL, (show_id,), one=True) or abort(404)
    return render_template("seats.html", show=show)

@app.route("/api/seats/<int:show_id>")
def api_seats(show_id):
    """JSON used by script.js. LEFT JOIN marks seats already in booking_seats as booked."""
    return jsonify(query("""SELECT se.seat_id, se.row_label, se.seat_number,
                                   (bs.seat_id IS NOT NULL) AS booked
                            FROM shows s
                            JOIN seats se ON se.screen_id = s.screen_id
                            LEFT JOIN booking_seats bs ON bs.seat_id = se.seat_id AND bs.show_id = s.show_id
                            WHERE s.show_id = %s ORDER BY se.row_label, se.seat_number""", (show_id,)))

# ---------- booking + payment ----------
@app.route("/book", methods=["POST"])
@login_required
def book():
    """Booking summary + mock payment form (nothing is saved yet)."""
    show_id = int(request.form["show_id"])
    ids = [int(x) for x in request.form["seat_ids"].split(",") if x]
    show = query(SHOW_SQL, (show_id,), one=True) or abort(404)
    marks = ",".join(["%s"] * len(ids))
    labels = query(f"""SELECT CONCAT(row_label, seat_number) AS label FROM seats
                       WHERE screen_id=%s AND seat_id IN ({marks}) ORDER BY row_label, seat_number""",
                   [show["screen_id"]] + ids) if ids else []
    if not ids or len(labels) != len(ids):
        flash("Please select valid seats.")
        return redirect(url_for("seats", show_id=show_id))
    total = show["ticket_price"] * len(ids)
    return render_template("payment.html", show=show, labels=[l["label"] for l in labels],
                           seat_ids=",".join(map(str, ids)), total=total)

@app.route("/confirm", methods=["POST"])
@login_required
def confirm():
    """THE TRANSACTION: booking + seats + payment succeed together or not at all (Atomicity)."""
    show_id = int(request.form["show_id"])
    method = request.form["method"]
    ids = [int(x) for x in request.form["seat_ids"].split(",") if x]
    if method not in ("UPI", "CARD", "CASH") or not ids:
        flash("Invalid request.")
        return redirect(url_for("seats", show_id=show_id))
    marks = ",".join(["%s"] * len(ids))
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    try:
        conn.start_transaction()
        # 1. Lock the show row so two buyers of this show are processed one at a time.
        cur.execute("""SELECT ticket_price, screen_id,
                              TIMESTAMP(show_date, show_time) > NOW() AS upcoming
                       FROM shows WHERE show_id=%s FOR UPDATE""", (show_id,))
        show = cur.fetchone()
        if not show or not show["upcoming"]:
            raise ValueError("This show is not available.")
        # 2. Seats must belong to this show's screen.
        cur.execute(f"SELECT COUNT(*) AS n FROM seats WHERE screen_id=%s AND seat_id IN ({marks})",
                    [show["screen_id"]] + ids)
        if cur.fetchone()["n"] != len(ids):
            raise ValueError("Invalid seats selected.")
        # 3. Are the seats still free?
        cur.execute(f"SELECT COUNT(*) AS n FROM booking_seats WHERE show_id=%s AND seat_id IN ({marks})",
                    [show_id] + ids)
        if cur.fetchone()["n"] > 0:
            raise ValueError("Sorry, one or more seats were just booked by someone else.")
        total = show["ticket_price"] * len(ids)
        # 4. Insert booking, its seats and the payment.
        cur.execute("INSERT INTO bookings (user_id, show_id, total_amount) VALUES (%s,%s,%s)",
                    (session["user_id"], show_id, total))
        booking_id = cur.lastrowid
        cur.executemany("INSERT INTO booking_seats (booking_id, seat_id, show_id) VALUES (%s,%s,%s)",
                        [(booking_id, s, show_id) for s in ids])
        cur.execute("INSERT INTO payments (booking_id, method, amount, status) VALUES (%s,%s,%s,'SUCCESS')",
                    (booking_id, method, total))
        conn.commit()                                   # 5. all or nothing
    except (ValueError, mysql.connector.Error) as e:
        conn.rollback()                                 # undo everything
        # UNIQUE(show_id, seat_id) is the last line of defence against double booking
        flash(str(e) if isinstance(e, ValueError) else "Seat conflict - please choose other seats.")
        return redirect(url_for("seats", show_id=show_id))
    finally:
        cur.close(); conn.close()
    return redirect(url_for("confirmation", booking_id=booking_id))

@app.route("/confirmation/<int:booking_id>")
@login_required
def confirmation(booking_id):
    b = query("SELECT * FROM booking_details_view WHERE booking_id=%s AND user_id=%s",
              (booking_id, session["user_id"]), one=True) or abort(404)
    return render_template("confirmation.html", b=b)

@app.route("/my-bookings")
@login_required
def my_bookings():
    rows = query("SELECT * FROM booking_details_view WHERE user_id=%s ORDER BY booking_time DESC",
                 (session["user_id"],))
    return render_template("my_bookings.html", bookings=rows)

@app.route("/cancel/<int:booking_id>", methods=["POST"])
@login_required
def cancel(booking_id):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.callproc("sp_cancel_booking", (booking_id, session["user_id"]))   # trigger frees seats
        conn.commit()
        flash("Booking cancelled. Payment marked as refunded.")
    except mysql.connector.Error:
        conn.rollback()
        flash("This booking cannot be cancelled (already cancelled or show started).")
    finally:
        cur.close(); conn.close()
    return redirect(url_for("my_bookings"))

# ---------- admin ----------
ENT = {  # entity -> (table, primary key, editable columns)
    "movie":   ("movies", "movie_id", ["title", "language", "duration_min", "rating", "status"]),
    "theatre": ("theatres", "theatre_id", ["name", "city"]),
    "show":    ("shows", "show_id", ["show_date", "show_time", "ticket_price"]),
    "screen":  ("screens", "screen_id", []),
}

def admin_do(sql, params, ok):
    try:
        execute(sql, params)
        flash(ok)
    except mysql.connector.Error as e:
        flash(f"Database error: {e.msg}")
    return redirect(url_for("admin"))

@app.route("/admin")
@admin_required
def admin():
    stats = query("""SELECT (SELECT COUNT(*) FROM movies) AS movies,
                            (SELECT COUNT(*) FROM theatres) AS theatres,
                            (SELECT COUNT(*) FROM bookings WHERE status='CONFIRMED') AS bookings,
                            (SELECT COALESCE(SUM(amount),0) FROM payments WHERE status='SUCCESS') AS revenue""",
                  one=True)
    return render_template(
        "admin/dashboard.html", stats=stats,
        movies=query(MOVIE_SQL.format(where="")),
        genres=query("SELECT * FROM genres ORDER BY genre_name"),
        theatres=query("SELECT * FROM theatres ORDER BY name"),
        screens=query("""SELECT sc.*, t.name AS theatre, sc.total_rows*sc.seats_per_row AS capacity
                         FROM screens sc JOIN theatres t ON t.theatre_id=sc.theatre_id ORDER BY t.name, sc.screen_name"""),
        shows=query("""SELECT s.*, m.title, t.name AS theatre, sc.screen_name
                       FROM shows s JOIN movies m ON m.movie_id=s.movie_id
                       JOIN screens sc ON sc.screen_id=s.screen_id
                       JOIN theatres t ON t.theatre_id=sc.theatre_id
                       ORDER BY s.show_date, s.show_time"""),
        bookings=query("SELECT * FROM booking_details_view ORDER BY booking_time DESC"))

@app.route("/admin/add/movie", methods=["POST"])
@admin_required
def add_movie():
    f = request.form
    try:
        movie_id = execute("""INSERT INTO movies (title, description, duration_min, language, rating,
                              release_date, poster_url, status) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                           (f["title"], f["description"], f["duration_min"], f["language"], f["rating"],
                            f["release_date"], f["poster_url"], f["status"]))
        for g in request.form.getlist("genres"):
            execute("INSERT INTO movie_genres (movie_id, genre_id) VALUES (%s,%s)", (movie_id, g))
        flash("Movie added.")
    except mysql.connector.Error as e:
        flash(f"Database error: {e.msg}")
    return redirect(url_for("admin"))

@app.route("/admin/add/theatre", methods=["POST"])
@admin_required
def add_theatre():
    f = request.form
    return admin_do("INSERT INTO theatres (name, city, address) VALUES (%s,%s,%s)",
                    (f["name"], f["city"], f["address"]), "Theatre added.")

@app.route("/admin/add/screen", methods=["POST"])
@admin_required
def add_screen():
    """Creates the screen AND its seat rows in one transaction."""
    f = request.form
    rows, per_row = int(f["total_rows"]), int(f["seats_per_row"])
    conn = get_connection()
    cur = conn.cursor()
    try:
        conn.start_transaction()
        cur.execute("INSERT INTO screens (theatre_id, screen_name, total_rows, seats_per_row) VALUES (%s,%s,%s,%s)",
                    (f["theatre_id"], f["screen_name"], rows, per_row))
        screen_id = cur.lastrowid
        cur.executemany("INSERT INTO seats (screen_id, row_label, seat_number) VALUES (%s,%s,%s)",
                        [(screen_id, chr(65 + r), n) for r in range(rows) for n in range(1, per_row + 1)])
        conn.commit()
        flash("Screen and seats created.")
    except mysql.connector.Error as e:
        conn.rollback()
        flash(f"Database error: {e.msg}")
    finally:
        cur.close(); conn.close()
    return redirect(url_for("admin"))

@app.route("/admin/add/show", methods=["POST"])
@admin_required
def add_show():
    f = request.form
    return admin_do("""INSERT INTO shows (movie_id, screen_id, show_date, show_time, ticket_price)
                       VALUES (%s,%s,%s,%s,%s)""",
                    (f["movie_id"], f["screen_id"], f["show_date"], f["show_time"], f["ticket_price"]),
                    "Show created.")

@app.route("/admin/update/<ent>/<int:eid>", methods=["POST"])
@admin_required
def admin_update(ent, eid):
    if ent not in ENT or not ENT[ent][2]:
        abort(404)
    table, pk, cols = ENT[ent]
    sets = ", ".join(f"{c}=%s" for c in cols)
    return admin_do(f"UPDATE {table} SET {sets} WHERE {pk}=%s",
                    [request.form[c] for c in cols] + [eid], "Updated.")

@app.route("/admin/delete/<ent>/<int:eid>", methods=["POST"])
@admin_required
def admin_delete(ent, eid):
    if ent not in ENT:
        abort(404)
    table, pk, _ = ENT[ent]
    return admin_do(f"DELETE FROM {table} WHERE {pk}=%s", (eid,), "Deleted.")

if __name__ == "__main__":
    app.run(debug=True)
