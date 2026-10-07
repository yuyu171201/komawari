# Komawari

大学の時間割を `timetable.yaml` で管理し、週ビュー（Web UI）と `.ics` を提供するアプリ。仕様は [SPEC.md](SPEC.md)。

## セットアップ

```bash
uv sync
cp timetable.example.yaml timetable.yaml
```

`timetable.yaml` は自分の時間割を書くファイルで、`.gitignore` に入れてある（リポジトリには含めない）。

## 使い方

```bash
uv run komawari week                 # 今週の予定をターミナルに表示
uv run komawari week -d 2026-10-21   # 指定日を含む週
uv run komawari ics -o timetable.ics # .ics をファイルに出力
uv run komawari serve                # http://127.0.0.1:8000 で週ビューを配信
uv run pytest                        # テスト
```

YAML の場所は `-c PATH` か環境変数 `KOMAWARI_CONFIG` で変えられる（既定はカレントディレクトリの `timetable.yaml`）。サーバーは YAML の更新を検知して自動で読み直す。

### 授業変更の登録

週ビューから、休講・教室変更・補講・振替を登録できる。登録内容は `timetable.yaml` の `exceptions` に1行ずつ追記され、手で書いたコメントや他の行はそのまま残る。

- 授業をクリック: その授業を休講・教室変更にする（通常どおりに戻すのも同じ画面）
- コマの「+」をクリック: 補講を追加する。登録済みの補講はクリックで削除できる
- 日付をクリック: その日を振替・休講にする。祝日に授業を行う設定もここ

### カレンダーの購読

`komawari serve` を起動した状態で、週ビュー右下の「カレンダーで購読」（`webcal://127.0.0.1:8000/timetable.ics`）を開くと、標準カレンダーに購読カレンダーとして追加できる。カレンダーが更新を取りに来るときにサーバーが動いている必要がある。

## `timetable.yaml`

```yaml
term: {start: 2026-10-05, end: 2027-01-29}

periods:
  1: {start: "08:45", end: "10:15"}

terms:     # 任意。ターム別の開講期間
  3: {start: 2026-10-05, end: 2026-12-01}
  4: {start: 2026-12-02, end: 2027-01-29}

classes:   # weekday: 0=月 ... 6=日。時刻は period か start/end のどちらか一方
  - {name: Java演習, weekday: 0, period: 2, room: 情報1号館, term: 3}   # 第3タームだけ開講
  - {name: ゼミ, weekday: 4, start: "18:10", end: "19:40"}             # term なし = 学期全体

exceptions:   # 1行1件。同じ日付に複数行書いてよい
  - {date: 2026-10-21, as_weekday: 0}                 # 振替: この日は月曜授業
  - {date: 2026-11-04, off: true}                     # 休講: この日は授業なし
  - {date: 2026-11-23, off: false}                    # 祝日だが授業あり
  - {date: 2026-11-14, extra: {name: 機械学習, period: 4, room: A101}}  # 補講
  - {date: 2026-12-02, class: 機械学習, room: B202}   # 教室変更（period で絞り込み可）
  - {date: 2026-12-09, class: 機械学習, off: true}    # その授業だけ休講
  # 休講の代わりの日（補講）。その日のコマに補講として表示される
  - {date: 2026-12-16, class: 機械学習, off: true, makeup: {date: 2026-12-19, periods: [1, 2]}}
  - {date: 2026-12-23, class: 機械学習, off: true, makeup: pending}   # 代わりの日は未定
```

- 授業に `term` を書くと `terms` の期間だけ開講する。振替の日は、その日付が属するタームの授業が出る
- 日本の祝日は `jpholiday` で自動的に休講になる。祝日に授業がある日は `off: false` か `as_weekday` を書く
- 補講（`extra`）は日付を明示した追加なので、休みの日や学期外でも表示・出力される
- `makeup` の教室は `room` で指定でき、省略すると元の授業の教室になる
- `class` で指定した授業がその日に無い場合は、打ち間違いとして読み込みエラーになる

## Swift 版のロジック（KomawariCore）

iPhone アプリに向けて、展開ロジックを Swift パッケージ [KomawariCore](KomawariCore) に移植してある。サーバーなしで動かすためのもので、祝日判定も内蔵している（2020年以降）。

```bash
KomawariCore/Scripts/test.sh                          # Swift のテスト
uv run python KomawariCore/Scripts/make_golden.py     # Python 版から照合データを作り直す
```

テストは、Python 版が書き出した結果（全日付の展開・全週のサマリー・`jpholiday` の祝日）と Swift 版の結果が一致することを確かめる。Python 側のロジックを変えたら照合データを作り直すこと。

## iPhone アプリ（ios/）

SwiftUI の週ビュー。サーバーなしで動き、授業・空きコマ・日付をタップして休講・教室変更・補講・振替を登録できる。

```bash
uv run komawari json -o ios/Komawari/Resources/timetable.json   # 自分の時間割をアプリ用に書き出す
open ios/Komawari.xcodeproj                                      # Xcode で開いて実行
```

- `ios/Komawari/Resources/timetable.json` は `.gitignore` に入れてある。無ければ同梱のサンプルが表示される
- アプリで一度登録すると、アプリ内に保存したデータが優先される（書き出し直した JSON は反映されない）
- 起動引数 `-date YYYY-MM-DD` で、その日を含む週から開ける（動作確認用）

## 構成

| ファイル | 役割 |
|----------|------|
| `komawari/config.py` | YAML の読み込みと検証 |
| `komawari/core.py` | 展開ロジック（`expand_day` / `week_view` / `expand_term` / `week_summary`）。UI・API から独立 |
| `komawari/ics.py` | `.ics` 生成 |
| `komawari/cli.py` | CLI |
| `komawari/editor.py` | `exceptions` の行単位の追加・削除（コメントを保ったまま YAML を書き換える） |
| `komawari/api.py` | FastAPI（`GET /week?date=`、`GET /timetable.ics`、`POST /exceptions`、`DELETE /exceptions/{id}`、Web UI の配信） |
| `komawari/static/` | Web UI（週ビュー） |
