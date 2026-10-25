"""Database helper: the only file that knows how to connect to MySQL."""
import os
import mysql.connector

# Edit the password below (or set the DB_PASSWORD environment variable).
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", "Akshaya88.."),
    "database": "movie_booking",
}

def get_connection():
    return mysql.connector.connect(**DB_CONFIG)

def query(sql, params=(), one=False):
    """Run a SELECT. Returns a list of dict rows (or one dict if one=True)."""
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    cur.execute(sql, params)
    rows = cur.fetchall()
    cur.close(); conn.close()
    if one:
        return rows[0] if rows else None
    return rows

def execute(sql, params=()):
    """Run one INSERT / UPDATE / DELETE and commit. Returns the new id."""
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(sql, params)
        conn.commit()
        return cur.lastrowid
    finally:
        cur.close(); conn.close()
