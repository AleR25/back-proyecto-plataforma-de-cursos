// Prueba semántica de las vistas reales sobre SQLite; no valida el DDL de MySQL.
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const schema = readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');

function fixture() {
  const db = new DatabaseSync(':memory:');
  db.function('LEAST', { varargs: true }, (...values) => Math.min(...values));
  db.function('GREATEST', { varargs: true }, (...values) => Math.max(...values));
  db.function('TRUNCATE', (value, digits) => Math.trunc(value * 10 ** digits) / 10 ** digits);
  db.exec(`
    CREATE TABLE lessons (id INTEGER PRIMARY KEY, module_id INTEGER, duration_seconds NUMERIC, video_revision INTEGER DEFAULT 1);
    CREATE TABLE lesson_watch_intervals (
      user_id INTEGER, lesson_id INTEGER, start_seconds NUMERIC, end_seconds NUMERIC, video_revision INTEGER DEFAULT 1
    );
    CREATE TABLE lesson_progress_state (user_id INTEGER, lesson_id INTEGER, max_progress_percentage NUMERIC);
    CREATE TABLE module_completion_records (user_id INTEGER, module_id INTEGER);
    CREATE TABLE course_progress_state (user_id INTEGER, course_id INTEGER, max_progress_percentage NUMERIC);
    CREATE TABLE course_modules (id INTEGER, course_id INTEGER, coverage_percentage NUMERIC);
    INSERT INTO course_modules VALUES (10, 1, 60), (20, 1, 40);
    INSERT INTO lessons(id, module_id, duration_seconds) VALUES (1, 10, 100), (2, 10, 100), (3, 20, 100);
  `);
  for (const name of ['lesson_progress', 'module_completions', 'course_progress']) {
    const sql = schema.match(new RegExp(`CREATE VIEW ${name} AS[\\s\\S]*?;`));
    assert.ok(sql, `Falta la vista ${name}`);
    db.exec(sql[0]);
  }
  return db;
}

function watch(db, user, lesson, start, end) {
  db.prepare('INSERT INTO lesson_watch_intervals(user_id, lesson_id, start_seconds, end_seconds) VALUES (?, ?, ?, ?)').run(user, lesson, start, end);
}

function progress(db, user = 1, lesson = 1) {
  return db.prepare('SELECT * FROM lesson_progress WHERE user_id = ? AND lesson_id = ?').get(user, lesson);
}

function check(name, run) {
  test(name, () => {
    const db = fixture();
    try { run(db); } finally { db.close(); }
  });
}

check('89.999 % no completa; 90 % exacto sí', db => {
  watch(db, 1, 1, 0, 89.999);
  assert.equal(progress(db).is_completed, 0);
  watch(db, 1, 1, 89.999, 90);
  assert.equal(progress(db).is_completed, 1);
});

check('solapamientos, intervalos anidados y reintentos no duplican tiempo', db => {
  for (const [start, end] of [[0, 60], [10, 20], [30, 90], [0, 60]]) {
    watch(db, 1, 1, start, end);
  }
  assert.equal(progress(db).watched_seconds, 90);
});

check('saltar al final no completa el video', db => {
  watch(db, 1, 1, 0, 10);
  watch(db, 1, 1, 90, 100);
  assert.equal(progress(db).watched_seconds, 20);
  assert.equal(progress(db).is_completed, 0);
});

check('el cómputo no excede la duración', db => {
  watch(db, 1, 1, 0, 120);
  watch(db, 1, 1, 130, 140);
  assert.equal(progress(db).watched_seconds, 100);
});

check('separa usuarios y lecciones', db => {
  watch(db, 1, 1, 0, 50);
  watch(db, 2, 1, 50, 100);
  watch(db, 1, 2, 0, 90);
  assert.equal(progress(db, 1, 1).watched_seconds, 50);
  assert.equal(progress(db, 2, 1).watched_seconds, 50);
  assert.equal(progress(db, 1, 2).watched_seconds, 90);
});

check('el módulo exige todas sus lecciones al 90 %', db => {
  const count = () => db.prepare('SELECT COUNT(*) AS n FROM module_completions WHERE user_id = 1 AND module_id = 10').get().n;
  watch(db, 1, 1, 0, 90);
  assert.equal(count(), 0);
  watch(db, 1, 2, 0, 89);
  assert.equal(count(), 0);
  watch(db, 1, 2, 89, 90);
  assert.equal(count(), 1);
});

check('sin reproducción o sin lecciones no hay módulos completos', db => {
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM module_completions').get().n, 0);
  assert.equal(progress(db), undefined);
  db.exec('DELETE FROM lessons');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM module_completions').get().n, 0);
});

check('el porcentaje reconocido sobrevive al reemplazo y cambio de duración', db => {
  watch(db, 1, 1, 0, 60);
  db.exec('INSERT INTO lesson_progress_state SELECT user_id, lesson_id, progress_percentage FROM lesson_progress');
  db.exec('UPDATE lessons SET video_revision = 2, duration_seconds = 200 WHERE id = 1');
  assert.equal(progress(db).progress_percentage, 60);
  assert.equal(progress(db).watched_seconds, 0);
  assert.equal(progress(db).is_completed, 0);
});

check('una lección completada sigue completa con un video más largo', db => {
  watch(db, 1, 1, 0, 90);
  db.exec('INSERT INTO lesson_progress_state SELECT user_id, lesson_id, progress_percentage FROM lesson_progress');
  db.exec('UPDATE lessons SET video_revision = 2, duration_seconds = 200 WHERE id = 1');
  assert.equal(progress(db).is_completed, 1);
});

check('acortar un video no convierte intervalos antiguos en avance nuevo', db => {
  watch(db, 1, 1, 0, 50);
  db.exec('INSERT INTO lesson_progress_state SELECT user_id, lesson_id, progress_percentage FROM lesson_progress');
  db.exec('UPDATE lessons SET video_revision = 2, duration_seconds = 20 WHERE id = 1');
  assert.equal(progress(db).progress_percentage, 50);
  assert.equal(progress(db).is_completed, 0);
});

check('el módulo reconocido sigue completo al agregar una lección', db => {
  watch(db, 1, 1, 0, 90);
  watch(db, 1, 2, 0, 90);
  db.exec('INSERT INTO module_completion_records SELECT user_id, module_id FROM module_completions');
  db.exec('INSERT INTO lessons(id, module_id, duration_seconds) VALUES (4, 10, 100)');
  assert.equal(db.prepare('SELECT COUNT(*) AS n FROM module_completions WHERE user_id = 1 AND module_id = 10').get().n, 1);
});

check('el curso conserva el 60 % al redistribuir pesos y agregar módulos', db => {
  db.exec('INSERT INTO module_completion_records VALUES (1, 10)');
  db.exec('INSERT INTO course_progress_state SELECT user_id, course_id, progress_percentage FROM course_progress');
  db.exec('UPDATE course_modules SET coverage_percentage = 30 WHERE id = 10');
  db.exec('INSERT INTO course_modules VALUES (30, 1, 30)');
  assert.equal(db.prepare('SELECT progress_percentage AS p FROM course_progress WHERE user_id = 1').get().p, 60);
  db.exec('INSERT INTO module_completion_records VALUES (1, 20)');
  assert.equal(db.prepare('SELECT progress_percentage AS p FROM course_progress WHERE user_id = 1').get().p, 70);
});

check('un curso terminado conserva el 100 % y el estado no se comparte entre usuarios', db => {
  db.exec('INSERT INTO course_progress_state VALUES (1, 1, 100), (2, 1, 40)');
  db.exec('INSERT INTO course_modules VALUES (30, 1, 20)');
  db.exec('UPDATE course_modules SET coverage_percentage = 40 WHERE id = 10');
  assert.equal(db.prepare('SELECT progress_percentage AS p FROM course_progress WHERE user_id = 1').get().p, 100);
  assert.equal(db.prepare('SELECT progress_percentage AS p FROM course_progress WHERE user_id = 2').get().p, 40);
});
