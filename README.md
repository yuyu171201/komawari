# Komawari

大学の時間割を `timetable.yaml` で管理し、週ビュー（Web UI）と `.ics` を提供するアプリ。仕様は [SPEC.md](SPEC.md)。

## セットアップ

```bash
uv sync
```

## 使い方

```bash
uv run komawari week                 # 今週の予定をターミナルに表示
uv run komawari week -d 2026-10-21   # 指定日を含む週
uv run komawari ics -o timetable.ics # .ics をファイルに出力
uv run komawari serve                # http://127.0.0.1:8000 で週ビューを配信
uv run pytest                        # テスト
```

YAML の場所は `-c PATH` か環境変数 `KOMAWARI_CONFIG` で変えられる（既定はカレントディレクトリの `timetable.yaml`）。サーバーは YAML の更新を検知して自動で読み直す。

### カレンダーの購読

`komawari serve` を起動した状態で、週ビュー右下の「カレンダーで購読」（`webcal://127.0.0.1:8000/timetable.ics`）を開くと、標準カレンダーに購読カレンダーとして追加できる。カレンダーが更新を取りに来るときにサーバーが動いている必要がある。

## `timetable.yaml`

```yaml
term: {start: 2026-10-05, end: 2027-01-29}

periods:
  1: {start: "08:45", end: "10:15"}

classes:   # weekday: 0=月 ... 6=日。時刻は period か start/end のどちらか一方
  - {name: Java演習, weekday: 0, period: 2, room: 情報1号館}
  - {name: ゼミ, weekday: 4, start: "18:10", end: "19:40"}

exceptions:   # 1行1件。同じ日付に複数行書いてよい
  - {date: 2026-10-21, as_weekday: 0}                 # 振替: この日は月曜授業
  - {date: 2026-11-04, off: true}                     # 休講: この日は授業なし
  - {date: 2026-11-23, off: false}                    # 祝日だが授業あり
  - {date: 2026-11-14, extra: {name: 機械学習, period: 4, room: A101}}  # 補講
  - {date: 2026-12-02, class: 機械学習, room: B202}   # 教室変更（period で絞り込み可）
  - {date: 2026-12-09, class: 機械学習, off: true}    # その授業だけ休講
```

- 日本の祝日は `jpholiday` で自動的に休講になる。祝日に授業がある日は `off: false` か `as_weekday` を書く
- 補講（`extra`）は日付を明示した追加なので、休みの日や学期外でも表示・出力される
- `class` で指定した授業がその日に無い場合は、打ち間違いとして読み込みエラーになる

## 構成

| ファイル | 役割 |
|----------|------|
| `komawari/config.py` | YAML の読み込みと検証 |
| `komawari/core.py` | 展開ロジック（`expand_day` / `week_view` / `expand_term` / `week_summary`）。UI・API から独立 |
| `komawari/ics.py` | `.ics` 生成 |
| `komawari/cli.py` | CLI |
| `komawari/api.py` | FastAPI（`GET /week?date=`、`GET /timetable.ics`、Web UI の配信） |
| `komawari/static/` | Web UI（週ビュー） |
