# CameSura MVP 仕様書

最終更新: 2026-09-15
対象: ハッカソン実装担当者・コーディングエージェント

## 1. プロダクト概要

CameSura（カメスラ）は、スマートフォンのカメラで利用者の姿勢を認識し、SlimeVRのYaw Resetを行うのに適した姿勢か判定する補助ツールである。

MVPでは、カメラ映像とSlimeVRのトラッカー姿勢を連続的に融合しない。利用者が補正セッションを明示的に開始した後、正面を向いて直立・静止したことを画像処理で判定し、PCへYaw Reset要求を1回だけ送る。

## 2. 解決する課題

SlimeVRは利用中に方位のずれ（Yaw drift）が発生することがあり、利用者は正しい姿勢を取ってリセット操作を行う必要がある。しかし、姿勢が不適切な状態でリセットすると、その状態が基準になってしまう。

CameSuraは次を可能にする。

- スマホだけで、補正に適した姿勢か確認できる
- 骨格表示により画像処理の結果を目視できる
- 条件成立時だけ補正操作を有効にできる
- PC側でSlimeVRへの操作を一元管理できる

## 3. MVPの範囲

### 必須

1. AndroidとiOSで同一のFlutterアプリを起動できる
2. 背面カメラのプレビューを表示できる
3. 1人分の人体ランドマークを端末内で検出できる
4. 検出した骨格をプレビューへ重ねて表示できる
5. 「全身が見える」「正面」「直立」「静止」を個別表示できる
6. 全条件が一定時間成立すると「補正可能」になる
7. 「補正開始」操作後、15秒間だけ補正セッションを実行できる
8. セッション中に補正可能になったらGo Bridgeへリセット要求を1回送れる
9. Bridgeは同じ要求を連続実行しない
10. SlimeVRがなくてもMock Adapterで一連の動作を実演できる

### 対象外

- カメラとIMUの連続センサーフュージョン
- 各トラッカーの角度をカメラから直接補正する機能
- 複数人の同時認識
- 背景での常時動作
- インターネット越しの接続
- アカウント、クラウド保存、映像保存
- ユーザーが補正セッションを開始していない状態での自動リセット
- VRChatとの直接連携

## 4. システム構成

```text
mobile/  Flutterアプリ
  カメラ → 姿勢推定 → 条件判定 → ユーザー確認
                                      ↓ UDP/JSON
bridge/  Goアプリ
  要求検証 → 重複防止 → ResetAdapter
                         ├── Mock Adapter（必須）
                         └── SlimeVR Adapter（Stretch Goal）
```

カメラ画像はスマホ内だけで処理し、PCへ送信しない。

## 5. 技術選定

| 領域 | 採用技術 | 備考 |
| --- | --- | --- |
| モバイル | Flutter / Dart | Android・iOSを単一コードベースで実装 |
| カメラ | Flutter `camera` | 背面カメラを既定とする |
| 姿勢推定 | `google_mlkit_pose_detection` | ML Kitのストリームモードを使用 |
| 通信 | UDP + UTF-8 JSON | 同一LAN内、映像は送らない |
| PC Bridge | Go | 単一バイナリとして実行 |
| SlimeVR連携 | Adapter方式 | Mockを先に完成させる |

ML KitのFlutterラッパーが対象端末で動かない場合だけ、MethodChannel経由でAndroid/iOSのネイティブML Kit SDKを呼ぶ。最初から独自推論器は作らない。

初期対応バージョンはAndroid API 23以上、iOS 15.5以上とする。依存バージョンはM0時点の安定版を採用し、`pubspec.lock`をコミットして固定する。

## 6. モノレポ構成

```text
camesura/
├── README.md
├── mobile/
│   ├── lib/
│   │   ├── camera/
│   │   ├── pose/
│   │   ├── calibration/
│   │   └── transport/
│   └── test/
├── bridge/
│   ├── cmd/camesura-bridge/
│   ├── internal/protocol/
│   ├── internal/reset/
│   └── internal/server/
├── protocol/
│   ├── README.md
│   └── examples/
└── docs/
    └── SPEC.md
```

この仕様書はリポジトリでは `docs/SPEC.md` に配置する。

## 7. モバイルアプリ仕様

### 7.1 画面

MVPは1画面でよい。

- カメラプレビュー
- 骨格オーバーレイ
- BridgeのIPアドレス入力欄
- Bridge状態: `未確認` / `最終要求に応答あり` / `タイムアウト`
- 条件一覧
  - 全身: OK / NG
  - 正面: OK / NG
  - 直立: OK / NG
  - 静止: OK / NG
- 総合状態: `未検出` / `姿勢調整中` / `判定中` / `補正可能`
- `補正開始`ボタン
- 補正セッションの残り時間
- `キャンセル`ボタン

全身を映す距離からスマホへ触れる必要がないように、利用者はカメラの近くで先に`補正開始`を押す。アプリは15秒間だけ補正セッションを開始し、その間に総合状態が`補正可能`になったらリセット要求を自動送信する。送信後または時間切れでセッションを終了する。

### 7.2 権限

- Android: Camera権限、必要な場合のみネットワーク権限
- iOS: Camera Usage Description、Local Network Usage Description
- 権限拒否時は設定を確認するための説明を表示し、クラッシュしない

### 7.3 姿勢判定

すべての座標差は、解像度への依存を減らすため肩幅または画像サイズで正規化する。

アプリは縦向きに固定し、背面カメラだけをMVP対象とする。推論入力にはカメラセンサーの回転情報を正しく設定し、ランドマーク座標は左上原点の正立画像に正規化する。プレビューは`BoxFit.contain`相当で全体表示し、表示領域を `(offsetX, offsetY, displayWidth, displayHeight)` としたとき、正規化座標 `(x, y)` を次で描画する。

```text
screenX = offsetX + x * displayWidth
screenY = offsetY + y * displayHeight
```

上下または左右を切り取る`cover`表示はMVPでは使用しない。

#### 全身が見える

次の左右ランドマークの信頼度が設定値以上であること。

- 肩
- 腰
- 膝
- 足首

既定の信頼度しきい値は `0.6`。設定値としてコード内の1か所にまとめる。

通信上の`confidence`は、肩・腰・膝・足首の左右8点における信頼度の最小値とする。

#### 正面

MVPでは厳密な身体方位ではなく、次のヒューリスティックで判定する。

- 左右の肩と左右の腰が検出されている
- 鼻のX座標が左右肩のX座標の間にある
- 左右肩の見かけの高さの差が肩幅の15%以下
- 左右腰の見かけの高さの差が腰幅の15%以下

#### 直立

- 左右それぞれの腰・膝・足首が作る角度が160度以上
- 肩の中点が腰の中点より上にある
- 肩中点と腰中点を結ぶ線が画像の垂直方向から15度以内

片側の信頼度不足時は、そのフレームを直立とは判定しない。

#### 静止

- 肩・腰・膝・足首の座標を直近1秒分保持する
- 各点について、1秒窓の先頭座標からの最大距離を求める
- 8点の最大距離の平均を、窓内の肩幅中央値で正規化する
- 正規化した平均最大距離が `0.03` 未満なら静止候補とする
- 1秒窓の途中で必須点が欠損した場合は静止ではないと判定し、窓をリセットする

端末性能差を吸収するため、フレーム数ではなく時刻で1秒を測る。

#### 補正可能

4条件がすべて連続2秒成立したら`補正可能`にする。1条件でも不成立になったら計時をリセットする。補正セッション外では判定結果を表示するだけで、要求を送信しない。

しきい値は初期値であり、実機映像を見て調整可能とする。UIへのハードコードは禁止する。

### 7.4 補正セッションとリセット操作

1. 利用者が`補正開始`を押す
2. 15秒の補正セッションを開始する
3. 利用者がスマホから離れ、カメラに全身を映す
4. 4条件が連続2秒成立するまで待つ
5. アプリが一意な`request_id`を生成する
6. `reset_request`をBridgeへ3回、100ms間隔で送る
7. Bridgeから`reset_result`を受け取る
8. 成功またはエラーを表示してセッションを終了する
9. 15秒以内に条件が成立しなければ、要求を送らず時間切れを表示する
10. 送信から2秒以内に応答がなければ通信失敗を表示する

UDPの欠落対策として同一要求を3回送るが、Bridgeは`request_id`で重複排除する。

セッション状態は `idle`、`armed`、`sending`、`succeeded`、`failed` の5状態とする。`armed`以外で姿勢条件が成立しても要求を送らない。

## 8. 通信仕様

### 8.1 基本

- Transport: UDP
- Bridge待受ポート既定値: `39500`
- Encoding: UTF-8
- Payload: JSON object 1個
- 最大データグラム: 4 KiB
- Protocol version: `1`
- 接続先IPはMVPでは手入力
- 自動探索・QR接続は拡張機能

Flutterは送信用UDP socketを応答待受にも使用し、要求送信後2秒間は閉じない。Bridgeは受信データグラムの送信元IP・送信元ポートへ`reset_result`を返す。同じ`request_id`の3回の受信すべてに、キャッシュ済みの同一結果を返す。

### 8.2 reset_request

```json
{
  "version": 1,
  "type": "reset_request",
  "request_id": "018f47c2-6b36-7a84-8f72-15be61da84df",
  "device_id": "local-installation-uuid",
  "reset": "yaw",
  "pose": {
    "full_body": true,
    "facing_forward": true,
    "standing": true,
    "still": true,
    "stable_ms": 2180,
    "confidence": 0.91
  }
}
```

`request_id`はUUID。`device_id`は初回起動時に生成して端末内へ保存する。映像・画像・全ランドマークは送らない。

Bridgeが受理する条件は次のすべてを満たすこと。

- `version == 1`
- `type == "reset_request"`
- `request_id`と`device_id`が空でない文字列
- `reset == "yaw"`
- `pose`内の4つのbooleanがすべて`true`
- `stable_ms >= 2000`
- `0.0 <= confidence <= 1.0`

未知フィールドは将来互換のため無視する。必須フィールドの欠落または型違いは拒否する。

### 8.3 reset_result

```json
{
  "version": 1,
  "type": "reset_result",
  "request_id": "018f47c2-6b36-7a84-8f72-15be61da84df",
  "status": "ok",
  "code": "reset_accepted",
  "adapter": "mock",
  "message": "Yaw reset accepted"
}
```

`status`は `ok` または `error`。意味検証に失敗し、空でない`request_id`を読み取れた場合だけ、そのIDを付けて`error`を返す。`request_id`が欠落・空・型違いの場合は応答せず警告ログを出す。`code`は `reset_accepted`、`invalid_request`、`unsupported_version`、`cooldown`、`adapter_error` のいずれかとする。JSON構文自体が壊れている場合も応答は返さず警告ログだけを出す。いずれの場合もBridgeは終了しない。

### 8.4 セキュリティ前提

MVPは信頼できる同一LANでのデモ専用であり、認証と暗号化を提供しない。Bridgeは既定でプライベートネットワークだけからの利用を案内する。インターネットへポート公開しない。

## 9. Go Bridge仕様

### 9.1 CLI

```text
camesura-bridge --listen 0.0.0.0:39500 --adapter mock
camesura-bridge --listen 0.0.0.0:39500 --adapter slimevr
```

### 9.2 ResetAdapter

```go
type ResetAdapter interface {
	YawReset(ctx context.Context) error
}
```

必須Adapter:

- `mock`: 呼び出されたことを標準出力へ記録し、成功を返す

Bridgeのserver層が受信時刻、request_id、device_idを記録する。Adapterは通信要求そのものを知らない。

拡張Adapter:

- `slimevr`: SlimeVR ServerへYaw Resetを要求する

SlimeVRとの実通信方式は、実装時点のSlimeVR Serverの公式実装を確認して決定する。内部RPCを利用する場合は、SlimeVRの更新で壊れる可能性をREADMEへ明記し、`ResetAdapter`以外へプロトコル詳細を漏らさない。

ハッカソンMVPの正式な完了地点はMock AdapterによるM3までとする。M4のSlimeVR実機統合はStretch Goalであり、利用可能な実機と調査時間がある場合のみ行う。

### 9.3 重複防止

- 処理済み`request_id`を5分間保持する
- 同じ`request_id`の再受信ではAdapterを再実行しない
- 初回と同じ結果を返す
- 1端末あたり3秒間のクールダウンを設ける
- クールダウン中の別request_idには`error`を返す

### 9.4 ログ

次を1行単位で表示する。

- Bridge起動と待受アドレス
- 受信元IP、device_id、request_id
- 判定された姿勢情報
- Adapter名
- Reset成功またはエラー

画像や個人を識別する情報はログに含めない。

## 10. 実装順序とバックログ

### M0: リポジトリ初期化

- モノレポ構造を作る
- ルートREADMEに目的、起動方法、構成を記載
- FlutterとGoを個別にビルドできるCIを作る

完了条件: 空のFlutterアプリとGo CLIがCIを通る。

### M1: カメラと骨格表示

- Androidでカメラプレビュー
- ML Kitで姿勢推定
- 骨格オーバーレイ
- iOSでビルド・実機確認

完了条件: AndroidとiPhoneで、動きに追従する骨格が表示される。

### M2: 補正可能判定

- 4条件を独立した関数として実装
- 条件状態をUI表示
- 連続2秒判定
- 判定ロジックの単体テスト

完了条件: 補正セッション中に直立・静止すると要求送信へ進み、座るか動くと成立タイマーが戻る。

### M3: Mockで端から端まで接続

- Go UDP Server
- JSON validation
- Mock Adapter
- Flutter UDP client
- ACK、タイムアウト、重複排除

完了条件: 実トラッカーなしで、スマホのボタンからBridgeのReset成功まで実演できる。

### M4: SlimeVR統合（Stretch Goal）

- 現行SlimeVR ServerのReset経路を調査
- SlimeVR Adapterを実装
- 実機でYaw Resetを確認
- SlimeVR停止時のエラー表示

完了条件: SlimeVR Server起動中に要求するとYaw Resetが1回だけ実行される。

### M5: 発表品質

- 接続先QRコード（余裕があれば）
- しきい値調整
- デモ手順作成
- 失敗時の録画を用意

## 11. テスト要件

### モバイル単体テスト

- 正面・直立・静止判定を、固定ランドマーク入力で検証する
- 条件が2秒未満では補正可能にならない
- 条件が途中で崩れると計時が戻る
- 補正セッション外では要求を送信しない
- 補正不能のまま15秒経過したら要求を送信しない
- 1セッション中に要求を複数回送信しない（UDP再送3回は同一request_idとする）

### Bridge単体テスト

- 正常JSONでMock Adapterが1回呼ばれる
- 同じrequest_idを3回受けても1回だけ呼ばれる
- 不正JSONを無応答で破棄し、未知version・未知typeにはエラー応答する
- 受信元IP・ポートへ結果を返信する
- クールダウン中の別要求を拒否する

### 結合テスト

- Android → Bridge Mock
- iPhone → Bridge Mock
- Bridge → SlimeVR Server（M4を実施する場合のみ）
- Bridge停止中にモバイルがクラッシュしない
- SlimeVR停止中にBridgeがクラッシュしない

## 12. デモシナリオ

1. BridgeをMock Adapterで起動する
2. スマホへBridgeのIPを入力する
3. 被写体がカメラ前へ立つ
4. 骨格と4条件がリアルタイム表示される
5. スマホの近くで`補正開始`を押す
6. スマホから離れて正面・直立・静止を2秒維持する
7. 要求が自動送信される
8. PC側へ`Yaw reset accepted`が1回だけ表示される
9. 実機が利用可能ならSlimeVR Adapterへ切り替えて同じ操作を行う

## 13. エージェント向け実装ルール

- 本仕様にない機能を勝手に追加しない
- MVP完成前に自動探索、ログイン、クラウド、連続補正へ進まない
- モバイルとBridgeは通信例JSONを契約として独立実装する
- 数値しきい値は名前付き設定へ集約する
- 画像をネットワーク送信・保存しない
- SlimeVR固有処理はResetAdapter内へ隔離する
- 実機がない作業ではMock Adapterを使用する
- 仕様と実装が衝突した場合は、コードを推測で変更せずIssueへ差分を書く

## 14. 未確定事項

次はMVP着手を妨げないため、実装中に決める。

- ML Kit Flutterラッパーの採用品
- 現行SlimeVR Serverへの最も安定したYaw Reset経路
- 姿勢判定しきい値の実機調整値
- iOSの最低対応バージョン
- Androidの最低対応SDK

## 15. 参考資料

- [Google ML Kit Pose Detection](https://developers.google.com/ml-kit/vision/pose-detection)
- [Flutter camera plugin guide](https://docs.flutter.dev/cookbook/plugins/picture-using-camera)
- [SlimeVR Documentation](https://docs.slimevr.dev/)
