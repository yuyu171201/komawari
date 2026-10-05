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

function dayLabel(day) {
  const d = fromISO(day.date);
  return `${d.getMonth() + 1}/${d.getDate()}(${WEEKDAYS[day.weekday]})`;
}

// 表示中の週（月曜）。URL の ?date= で任意の週を開ける
let cursor = mondayOf(fromISO(new URLSearchParams(location.search).get("date")) || new Date());
let requestId = 0;
let classNames = [];

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
  classNames = data.class_names;

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
        if (c.period === row.number) slot.append(sessionCard(day, c));
      }
      if (row.number != null) slot.append(addExtraButton(day, row));
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
  const head = el("button", "cell day-head");
  head.type = "button";
  head.title = "この日の振替・休講を登録";
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
  head.addEventListener("click", () => openDayDialog(day));
  return head;
}

function sessionCard(day, c) {
  const card = el("button", `session ${c.status}`);
  card.type = "button";
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
  card.addEventListener("click", () => (c.status === "extra" ? openExtraDialog(day, c) : openClassDialog(day, c)));
  return card;
}

function addExtraButton(day, row) {
  const button = el("button", "add-extra", "+");
  button.type = "button";
  button.title = "補講を追加";
  button.setAttribute("aria-label", `${dayLabel(day)} ${row.number}限に補講を追加`);
  button.addEventListener("click", () => openAddExtraDialog(day, row));
  return button;
}

// ---- 授業変更の登録 -------------------------------------------------------

const dialog = document.getElementById("dialog");
const dialogForm = document.getElementById("dialog-form");
const dialogBody = document.getElementById("dialog-body");
const dialogError = document.getElementById("dialog-error");
const dialogSubmit = document.getElementById("dialog-submit");
let collectChange = null;

// collect は保存時に呼ばれ、{add, remove} を返す（入力に不備があれば Error を投げる）
function openDialog({ title, sub, body, submitLabel = "保存", collect }) {
  document.getElementById("dialog-title").textContent = title;
  document.getElementById("dialog-sub").textContent = sub;
  dialogBody.replaceChildren(...body);
  dialogError.textContent = "";
  dialogSubmit.textContent = submitLabel;
  dialogSubmit.hidden = collect == null;
  collectChange = collect;
  dialog.showModal();
}

dialogForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  dialogSubmit.disabled = true;
  dialogError.textContent = "";
  try {
    const { add = [], remove = [] } = collectChange();
    if (add.length || remove.length) await saveChange(add, remove);
    dialog.close();
    await load();
  } catch (err) {
    dialogError.textContent = err.message;
  } finally {
    dialogSubmit.disabled = false;
  }
});

document.getElementById("dialog-cancel").addEventListener("click", () => dialog.close());

async function saveChange(add, remove) {
  const res = await fetch("/exceptions", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ add, remove }),
  });
  if (res.ok) return;
  const data = await res.json().catch(() => ({}));
  throw new Error(typeof data.detail === "string" ? data.detail : "保存に失敗しました");
}

function radio(name, value, text, checked) {
  const label = el("label");
  const input = el("input");
  input.type = "radio";
  input.name = name;
  input.value = value;
  input.checked = checked;
  label.append(input, text);
  return label;
}

function textField(labelText, value, placeholder) {
  const label = el("label", "field", labelText);
  const input = el("input");
  input.type = "text";
  input.value = value || "";
  if (placeholder) input.placeholder = placeholder;
  label.append(input);
  return { label, input };
}

const chosen = (name) => dialogForm.querySelector(`input[name="${name}"]:checked`).value;
const ids = (entries) => entries.map((e) => e.id);

// 通常授業: 休講・教室変更
function openClassDialog(day, c) {
  const siblings = day.classes.filter((x) => x.name === c.name && x.status !== "extra");
  const canNarrow = c.period != null && siblings.length > 1;
  const forName = day.exceptions.filter((e) => e.class === c.name);
  const mine = forName.filter((e) => e.period == null || e.period === c.period);
  const current = mine.some((e) => e.off) ? "off" : mine.some((e) => e.room != null) ? "room" : "normal";

  const room = el("input");
  room.type = "text";
  room.placeholder = "新しい教室";
  room.value = mine.filter((e) => e.room != null).map((e) => e.room).pop() || "";
  room.addEventListener("focus", () => {
    dialogForm.querySelector('input[name="state"][value="room"]').checked = true;
  });
  const roomRow = radio("state", "room", "教室変更", current === "room");
  roomRow.append(room);

  const body = [radio("state", "normal", "通常どおり", current === "normal"), radio("state", "off", "休講", current === "off"), roomRow];

  const whole = el("input");
  whole.type = "checkbox";
  whole.checked = mine.length === 0 || mine.some((e) => e.period == null);
  if (canNarrow) {
    const label = el("label");
    label.append(whole, `この日の「${c.name}」すべて（${siblings.length}コマ）に適用`);
    body.push(el("hr"), label);
  }

  openDialog({
    title: c.name,
    sub: `${dayLabel(day)} ` + (c.period != null ? `${c.period}限 ` : "") + `${c.start}–${c.end}`,
    body,
    collect() {
      const state = chosen("state");
      const all = !canNarrow || whole.checked;
      const target = { date: day.date, class: c.name, ...(all ? {} : { period: c.period }) };
      const removed = all ? forName : mine;
      const add = [];
      if (!all) {
        // このコマだけ変えるとき、同名の全コマに掛かっていた変更は他のコマに付け直す
        for (const e of removed.filter((x) => x.period == null)) {
          for (const s of siblings.filter((x) => x.period !== c.period)) {
            add.push({ date: day.date, class: c.name, period: s.period, ...(e.off ? { off: true } : { room: e.room }) });
          }
        }
      }
      if (state === "off") add.push({ ...target, off: true });
      if (state === "room") {
        if (!room.value.trim()) throw new Error("新しい教室を入力してください");
        add.push({ ...target, room: room.value.trim() });
      }
      return { add, remove: ids(removed) };
    },
  });
}

// 登録済みの補講: 削除
function openExtraDialog(day, c) {
  const entry = day.exceptions.find(
    (e) => e.extra && e.extra.name === c.name && (c.period != null ? e.extra.period === c.period : e.extra.start === c.start),
  );
  openDialog({
    title: `${c.name}（補講）`,
    sub: `${dayLabel(day)} ` + (c.period != null ? `${c.period}限 ` : "") + `${c.start}–${c.end}` + (c.room ? ` @${c.room}` : ""),
    body: [el("p", "note", "この補講の登録を取り消します。")],
    submitLabel: "補講を削除",
    collect: entry ? () => ({ remove: [entry.id] }) : null,
  });
}

// 空きコマ: 補講の追加
function openAddExtraDialog(day, row) {
  const name = textField("授業名", "", "授業名");
  const list = el("datalist");
  list.id = "class-names";
  for (const n of classNames) list.append(new Option(n));
  name.input.setAttribute("list", list.id);
  const room = textField("教室（任意）", "", "教室");

  openDialog({
    title: "補講を追加",
    sub: `${dayLabel(day)} ${row.number}限 ${row.start}–${row.end}`,
    body: [name.label, list, room.label],
    submitLabel: "追加",
    collect() {
      if (!name.input.value.trim()) throw new Error("授業名を入力してください");
      const extra = { name: name.input.value.trim(), period: row.number };
      if (room.input.value.trim()) extra.room = room.input.value.trim();
      return { add: [{ date: day.date, extra }] };
    },
  });
  name.input.focus();
}

// 日: 振替・休講・祝日の授業
function openDayDialog(day) {
  if (!day.in_term) {
    openDialog({
      title: dayLabel(day),
      sub: "学期外",
      body: [el("p", "note", "学期外の日です。補講はコマの「+」から追加できます。")],
      collect: null,
    });
    return;
  }

  const entries = day.exceptions.filter((e) => e.class == null && e.extra == null);
  const swap = entries.find((e) => e.as_weekday != null);
  const off = entries.find((e) => e.off != null);
  const current = swap ? "swap" : off ? (off.off ? "off" : "hold") : "normal";

  const select = el("select");
  for (let w = 0; w < 5; w++) {
    if (w !== day.weekday) select.append(new Option(`${WEEKDAYS[w]}曜授業`, w));
  }
  if (swap) select.value = swap.as_weekday;
  select.addEventListener("focus", () => {
    dialogForm.querySelector('input[name="state"][value="swap"]').checked = true;
  });
  const swapRow = radio("state", "swap", "振替", current === "swap");
  swapRow.append(select);

  const body = [
    radio("state", "normal", day.holiday ? `通常どおり（祝日のため休み）` : "通常どおり", current === "normal"),
    swapRow,
  ];
  if (day.holiday) body.push(radio("state", "hold", "祝日だが授業を行う", current === "hold"));
  else body.push(radio("state", "off", "休講（この日は授業なし）", current === "off"));

  openDialog({
    title: dayLabel(day),
    sub: day.holiday || "この日全体の変更",
    body,
    collect() {
      const state = chosen("state");
      const add = [];
      if (state === "swap") add.push({ date: day.date, as_weekday: Number(select.value) });
      if (state === "off") add.push({ date: day.date, off: true });
      if (state === "hold") add.push({ date: day.date, off: false });
      return { add, remove: ids(entries) };
    },
  });
}

// ---- 週の移動 -------------------------------------------------------------

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
  if (e.metaKey || e.ctrlKey || e.altKey || dialog.open) return;
  if (e.key === "ArrowLeft") go(addDays(cursor, -7));
  else if (e.key === "ArrowRight") go(addDays(cursor, 7));
  else if (e.key === "t" || e.key === "T") go(mondayOf(new Date()));
});

// 購読方式: カレンダーアプリが自動更新する webcal:// リンク
document.getElementById("subscribe").href = `webcal://${location.host}/timetable.ics`;

// 現在のコマのハイライトと YAML の変更を反映するため定期的に読み直す
setInterval(() => {
  if (!dialog.open) load();
}, REFRESH_MS);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden && !dialog.open) load();
});

load();
