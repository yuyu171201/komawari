"use strict";

const WEEKDAYS = ["月", "火", "水", "木", "金", "土", "日"];
const BADGES = { swapped: "振替", extra: "補講", room_changed: "教室変更", off: "休講" };
const REFRESH_MS = 60 * 1000;

const rangeEl = document.getElementById("range");
const summaryEl = document.getElementById("summary");
const gridEl = document.getElementById("grid");

const pad = (n) => String(n).padStart(2, "0");
const toISO = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const minutes = (hhmm) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3));

function fromISO(text) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text || "");
  if (!m) return null;
  const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  return Number.isNaN(d.getTime()) ? null : d;
}

function addDays(d, n) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
}

function mondayOf(d) {
  return addDays(d, -((d.getDay() + 6) % 7));
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

// 表示中の週（月曜）。URL の ?date= で任意の週を開ける
let cursor = mondayOf(fromISO(new URLSearchParams(location.search).get("date")) || new Date());
let requestId = 0;

async function load() {
  const id = ++requestId;
  gridEl.classList.add("loading");
  try {
    const res = await fetch(`/week?date=${toISO(cursor)}`);
    const data = await res.json();
    if (id !== requestId) return;
    if (!res.ok) throw new Error(typeof data.detail === "string" ? data.detail : "読み込みに失敗しました");
    render(data);
  } catch (e) {
    if (id !== requestId) return;
    summaryEl.className = "summary error";
    summaryEl.textContent = e.message || "サーバーに接続できません";
  } finally {
    if (id === requestId) gridEl.classList.remove("loading");
  }
}

function render(data) {
  const now = new Date();
  const today = toISO(now);
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  const days = data.days;

  renderRange(days);
  renderSummary(data, now);

  const untimed = days.some((d) => d.classes.some((c) => c.period == null));
  const rows = data.periods.map((p) => ({ ...p, label: String(p.number) }));
  if (untimed) rows.push({ number: null, label: "他" });

  gridEl.replaceChildren();
  gridEl.style.setProperty("--days", days.length);

  gridEl.append(el("div", "cell"));
  for (const day of days) gridEl.append(dayHead(day, today));

  for (const row of rows) {
    const isNow = row.number != null && minutes(row.start) <= nowMinutes && nowMinutes < minutes(row.end);
    const head = el("div", "cell period-head");
    head.append(el("span", "number", row.label));
    if (row.number != null) head.append(el("span", "time", `${row.start}–${row.end}`));
    gridEl.append(head);

    for (const day of days) {
      const isToday = day.date === today;
      const slot = el("div", "cell slot");
      if (day.status === "off") slot.classList.add("off-day");
      if (isToday) slot.classList.add("today");
      if (isToday && isNow) slot.classList.add("now");
      for (const c of day.classes) {
        if (c.period === row.number) slot.append(sessionCard(c));
      }
      gridEl.append(slot);
    }
    // 今日がこの週に表示されているときだけ、現在のコマを行見出しにも示す
    if (isNow && days.some((d) => d.date === today)) head.classList.add("now");
  }
}

function renderRange(days) {
  const first = fromISO(days[0].date);
  const last = fromISO(days[days.length - 1].date);
  const year = last.getFullYear() === first.getFullYear() ? "" : `${last.getFullYear()}年`;
  const month = year || last.getMonth() !== first.getMonth() ? `${last.getMonth() + 1}月` : "";
  rangeEl.textContent =
    `${first.getFullYear()}年${first.getMonth() + 1}月${first.getDate()}日` +
    ` 〜 ${year}${month}${last.getDate()}日`;
}

function renderSummary(data, now) {
  const weeks = Math.round((fromISO(data.week_start) - mondayOf(now)) / (7 * 24 * 3600 * 1000));
  const prefix = { 0: "今週は", 1: "来週は", "-1": "先週は" }[weeks] || "この週は";
  const changed = data.summary.length > 0;
  summaryEl.className = changed ? "summary changed" : "summary";
  summaryEl.textContent = prefix + (changed ? data.summary.join("、") : "通常どおり");
}

function dayHead(day, today) {
  const d = fromISO(day.date);
  const head = el("div", "cell day-head");
  if (day.date === today) head.classList.add("today");
  head.append(el("span", "weekday", WEEKDAYS[day.weekday]));
  head.append(el("span", "date", d.getDate() === 1 ? `${d.getMonth() + 1}/${d.getDate()}` : String(d.getDate())));

  const note = el("span", "day-note");
  if (day.status === "swapped") {
    note.classList.add("swapped");
    note.textContent = `${WEEKDAYS[day.weekday]}曜 → ${WEEKDAYS[day.effective_weekday]}曜授業`;
  } else if (day.off_reason === "exception") {
    note.classList.add("off");
    note.textContent = "休講";
  } else if (day.off_reason === "holiday") {
    note.classList.add("off");
    note.textContent = day.holiday;
  } else if (day.off_reason === "out_of_term") {
    note.classList.add("off");
    note.textContent = "学期外";
  } else if (day.holiday) {
    note.classList.add("holiday");
    note.textContent = `${day.holiday}・授業あり`;
  }
  head.append(note);
  return head;
}

function sessionCard(c) {
  const card = el("div", `session ${c.status}`);
  card.append(el("span", "name", c.name));

  if (c.period == null) card.append(el("span", "meta", `${c.start}–${c.end}`));

  if (c.room || c.original_room) {
    const meta = el("span", "meta");
    if (c.room) meta.append(el("span", "room", c.room));
    if (c.status === "room_changed" && c.original_room) {
      meta.append(" ← ", el("s", null, c.original_room));
    }
    card.append(meta);
  }

  if (BADGES[c.status]) card.append(el("span", "badge", BADGES[c.status]));
  card.title = `${c.name} ${c.start}–${c.end}` + (c.room ? ` @${c.room}` : "");
  return card;
}

function go(monday) {
  cursor = monday;
  const isThisWeek = toISO(cursor) === toISO(mondayOf(new Date()));
  history.replaceState(null, "", isThisWeek ? location.pathname : `?date=${toISO(cursor)}`);
  load();
}

document.getElementById("prev").addEventListener("click", () => go(addDays(cursor, -7)));
document.getElementById("next").addEventListener("click", () => go(addDays(cursor, 7)));
document.getElementById("today").addEventListener("click", () => go(mondayOf(new Date())));

document.addEventListener("keydown", (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  if (e.key === "ArrowLeft") go(addDays(cursor, -7));
  else if (e.key === "ArrowRight") go(addDays(cursor, 7));
  else if (e.key === "t" || e.key === "T") go(mondayOf(new Date()));
});

// 購読方式: カレンダーアプリが自動更新する webcal:// リンク
document.getElementById("subscribe").href = `webcal://${location.host}/timetable.ics`;

// 現在のコマのハイライトと YAML の変更を反映するため定期的に読み直す
setInterval(load, REFRESH_MS);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) load();
});

load();
