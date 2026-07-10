// DuckDB FFI for Amphora — the duckdb Node driver wrapped for Effect/Aff.
// Async ops resolve Promises; toAffE lifts them into Aff.

import duckdb from "duckdb";

export function openDB_(path) {
  return function () {
    return new Promise((resolve, reject) => {
      const db = new duckdb.Database(path, (err) => {
        if (err) reject(err);
        else resolve(db);
      });
    });
  };
}

export function closeDB_(db) {
  return function () {
    return new Promise((resolve, reject) => {
      db.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  };
}

export function exec_(db) {
  return function (sql) {
    return function () {
      return new Promise((resolve, reject) => {
        db.exec(sql, (err) => {
          if (err) reject(err);
          else resolve();
        });
      });
    };
  };
}

export function queryAll_(db) {
  return function (sql) {
    return function () {
      return new Promise((resolve, reject) => {
        db.all(sql, (err, rows) => {
          if (err) reject(err);
          else resolve(rows || []);
        });
      });
    };
  };
}

// Parameterised query (positional `?`). Also used for INSERT … RETURNING.
export const queryAllParams_ = (db, sql, params) =>
  new Promise((resolve, reject) => {
    db.all(sql, ...params, (err, rows) => {
      if (err) reject(err);
      else resolve(rows || []);
    });
  });

// Parameterised statement returning nothing.
export const run_ = (db, sql, params) =>
  new Promise((resolve, reject) => {
    db.run(sql, ...params, (err) => {
      if (err) reject(err);
      else resolve();
    });
  });

// Read a column from a result row. DuckDB hands back JS values (BigInt for
// BIGINT, Date for TIMESTAMP, etc.); stringify them uniformly so the typed
// side only ever deals in Maybe String. null/undefined -> null (SQL NULL).
export const readField_ = (key) => (row) => {
  const v = row[key];
  if (v === null || v === undefined) return null;
  if (typeof v === "bigint") return v.toString();
  if (v instanceof Date) return v.toISOString();
  return String(v);
};

export const firstRow_ = (rows) => (rows.length > 0 ? rows[0] : null);
