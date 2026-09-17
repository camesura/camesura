# かめすら（CameSura）MVP仕様書

最終更新: 2026-09-17
対象: ハッカソン実装担当者・コーディングエージェント

## 1. 目的

かめすらは、スマートフォンのカメラ（背面・前面切り替え可）で利用者のAポーズを検出し、適切な姿勢が安定したときだけSlimeVR ServerへYaw Resetを要求する補助ツールである。

初回設定後、利用者はスマートフォンへ触れない。カメラの前でAポーズを取ること自体を補正開始の意思表示とし、条件成立時に1回だけYaw Resetする。

カメラ映像とSlimeVRトラッカーを連続的に融合せず、映像やランドマークを端末外へ送信・保存しない。

## 2. MVPの利用手順

### 初回設定

1. PCでSlimeVR ServerとCameSura Bridgeを起動する
2. SlimeVRの通常セットアップを完了し、少なくとも一度Full Resetする
3. スマートフォンの初回設定で「探す」を押してBridgeを検出する（見つからない場合はIPアドレスを手入力する）
4. 全身が映る位置へスマートフォンを縦向きで固定する
5. 監視画面を開始する

Yaw Resetは、SlimeVR上でFull Resetが済んだセッションの方位ずれ補正に使う。初回のFull ResetやMounting CalibrationをCameSuraで置き換えない。

### 通常利用

1. 利用者がカメラ正面でAポーズを取る
2. アプリが全身、正面、直立、腕の形、静止を確認する
3. 全条件が2秒間続いたらBridgeへ要求する
4. BridgeがSlimeVR ServerへYaw Resetを要求する
5. 完了後、一度Aポーズを崩すまで次の要求を受け付けない

通常利用中にスマートフォンのボタン操作は要求しない。アプリが前面にあり監視画面が開かれていることは必要とする。

## 3. MVPの範囲

### 必須

- FlutterでAndroidとiOSへ対応する
- カメラのプレビューと1人分の骨格を表示する（背面カメラを既定とし、前面カメラへ切り替え可能）
- Aポーズの成立条件と不足条件をリアルタイム表示する
- Aポーズが2秒間安定したときだけ要求を1回送る
- 同じポーズを維持している間は再送しない
- Go Bridgeが要求を検証し、SlimeVR ServerへYaw Resetを送る
- SlimeVRがなくてもMock AdapterでモバイルからBridgeまで確認できる
- 映像処理は端末内だけで行う

### 対象外

- Full ResetとMounting Calibrationの自動実行
- カメラとIMUの連続センサーフュージョン
- カメラによる個別トラッカー角度の補正
- 複数人の同時認識
- バックグラウンド監視
- インターネット経由の接続
- アカウント、クラウド保存、映像保存
- VRChatとの直接連携
- QR接続

## 4. システム構成

```text
Flutter mobile
  Camera -> Pose detection -> A-pose state machine
                                  |
                                  | UDP / JSON (same LAN)
                                  v
Go Bridge
  Validation -> deduplication -> ResetAdapter
                                  |-- Mock
                                  `-- SlimeVR WebSocket / FlatBuffers
                                               |
                                               v
                                      SlimeVR Server :21110
```

スマートフォンはSlimeVR Serverへ直接接続しない。SlimeVR固有のバイナリプロトコルとバージョン差分をGo Bridgeへ隔離する。

## 5. 技術方針

| 領域 | 採用技術 | 方針 |
| --- | --- | --- |
| モバイル | Flutter / Dart | Android・iOSを単一コードベースで実装 |
| カメラ | Flutter `camera` | 背面/前面切り替え可、縦向き |
| 姿勢推定 | ML Kit Pose Detection | ストリームモード、端末内処理 |
| Mobile → Bridge | UDP + UTF-8 JSON | 同一LAN限定 |
| Bridge | Go | 単一バイナリ |
| Bridge → SlimeVR | WebSocket + FlatBuffers | SolarXR ProtocolのResetRequest |

Flutter、Go、パッケージの正確なバージョンは仕様書へ重複記載せず、`mise.toml`、`pubspec.lock`、`go.mod`を正本とする。

## 6. モバイル仕様

### 6.1 画面

MVPは次の2画面とする。

1. 初回設定画面
   - BridgeのIPアドレス
   - 接続確認
   - カメラ権限の案内
   - カメラ設置方法
   - 監視開始
2. 監視画面
   - カメラプレビュー
   - 骨格オーバーレイ
   - Bridge状態: `接続未確認` / `利用可能` / `応答なし`
   - 条件: `全身` / `正面` / `直立` / `腕` / `静止`
   - 総合状態: `人物未検出` / `ポーズ調整中` / `判定中` / `送信中` / `補正完了` / `エラー`

監視画面に毎回押す「補正開始」ボタンや15秒セッションは設けない。設定変更と監視終了は補助操作として提供してよい。

### 6.2 権限

- Android: Camera、ネットワーク通信に必要な権限
- iOS: Camera Usage Description、Local Network Usage Description
- 拒否時は設定方法を表示し、クラッシュしない

### 6.3 座標と表示

- 必須ランドマーク: 左右の肩・肘・手首・腰・膝・足首（12点）
- 鼻はオプション扱い。検出できれば正面判定の精度を上げるが、画角外で
  検出できなくても他の条件判定は継続する
- 信頼度の既定値は`0.6`
- 距離は肩幅、角度、または画像サイズで正規化する
- カメラセンサーの回転を反映し、左上原点の正立画像座標へ変換する
- プレビューは全身を欠落させない`BoxFit.contain`相当とする
- しきい値は1か所へ集約し、実機映像で調整可能にする

### 6.4 Aポーズ判定

AポーズはCameSuraが誤作動を避けるための明示ジェスチャーであり、SlimeVRのYaw Resetプロトコルが要求するポーズではない。

キャリブレーション（自動Yaw Reset送信）が成立する条件は**正面＋静止**。
全身・直立・腕は検出精度に対して厳しすぎ、実機では成立しにくいことが
分かったため、送信の必須条件から外した（直立は一旦条件から外した状態。
卓上設置などで下半身が画角外になるケースを含め、実機での再検証が必要）。
これらは監視画面の参考表示（骨格が全身映っているか等のヒント）として
引き続き判定・表示する。

正面（＝静止を除いたポーズそのものの成立、`poseMatched`）が満たされた
時点でプレビュー枠を緑にし、「そのまま静止してください」と案内する。
正面を向いていないまま静止しているだけでは要求条件は成立しない。

以下の角度・比率・時間はハッカソン時点の初期見積もりであり、実機で
検証済みの値ではない。ML Kitの検出精度や端末・設置環境によって体感の
厳しさは変わるため、実際の運用値は`mobile/lib/pose/a_pose_conditions.dart`の
`APoseThresholds`を正本とし、この仕様書の数値は「参考にしつつ実機で
調べ直すもの」として扱う。数値だけを信頼して実装/検証しないこと。

#### 全身

- 必須12点すべての信頼度が`0.6`以上
- 各点が画像範囲内にある

#### 正面

- 鼻のX座標が左右肩の間にある
- 左右肩の高さの差が肩幅の15%以下
- 左右腰の高さの差が腰幅の15%以下

これは厳密な3D身体方位ではなく、MVP用ヒューリスティックである。

#### 直立

- 左右の腰・膝・足首が作る角度が160度以上
- 肩の中点が腰の中点より上
- 肩中点から腰中点への線が画像の垂直方向から15度以内

#### 腕

- 左右の肩・肘・手首が作る角度が160度以上
- 肩から手首への線が、鉛直下向きから左右それぞれ25〜55度外側
- 手首は同じ側の肘より外側、肘は肩より外側
- 左右の腕角度の差が15度以内
- 両手首は両肩より下

#### 静止

- 必須12点を直近1秒保持する
- 各点の窓内最大移動距離を肩幅で正規化する
- 12点の平均が一定値未満なら静止候補とする（初期値`0.03`だが、検出精度の
  揺れで成立しにくい場合は緩める。現在値は`APoseThresholds`参照）
- 必須点が欠損したら窓をリセットする
- フレーム数ではなく単調増加時刻で測る

#### 成立と再待機

- 成立条件（正面＋静止）が連続2秒成立したら要求を1回送る
- 送信開始時にラッチを閉じる
- 成功・失敗にかかわらず、Aポーズが1秒連続で不成立になるまで再送しない
- Bridge側のクールダウンも併用する
- 監視停止中、初回設定中、送信中には要求しない

状態は`setup`、`watching`、`holding`、`sending`、`latched`、`error`とする。

## 7. Mobile → Bridge通信

### 7.1 基本

- Transport: UDP
- Bridge既定ポート: `39500`
- Encoding: UTF-8 JSON object
- 最大データグラム: 4 KiB
- Protocol version: `1`
- 接続先は7.4の自動検出で選ぶ。見つからない場合はIPを手入力する
- 要求を同じ`request_id`で3回、100ms間隔で送る
- 送信用socketで2秒間応答を待つ

### 7.2 reset_request

```json
{
  "version": 1,
  "type": "reset_request",
  "request_id": "018f47c2-6b36-7a84-8f72-15be61da84df",
  "device_id": "local-installation-uuid",
  "reset": "yaw",
  "pose": "a_pose",
  "stable_ms": 2180,
  "confidence": 0.91
}
```

`confidence`は必要な13点の信頼度の最小値とする。

開発用に、監視画面の「リセット」（Full Reset）と「Yawリセット」ボタンからSlimeVRと同じ3秒カウントダウン後に送る手動要求も扱う。手動要求に限り`reset = "full"`を使える。手動要求は`pose = "manual"`、`stable_ms`にカウントダウン長（3000）、`confidence = 0.0`を入れる。Bridgeは次を検証する。

- `version == 1`
- `type == "reset_request"`
- `request_id`と`device_id`が空でない
- `reset == "yaw"`または`reset == "full"`
- `pose == "a_pose"`または`pose == "manual"`
- `stable_ms >= 2000`
- `0.0 <= confidence <= 1.0`

### 7.3 reset_result

```json
{
  "version": 1,
  "type": "reset_result",
  "request_id": "018f47c2-6b36-7a84-8f72-15be61da84df",
  "status": "ok",
  "code": "reset_finished",
  "adapter": "slimevr",
  "message": "Yaw reset finished"
}
```

`status`は`ok`または`error`。`code`は少なくとも`reset_finished`、`invalid_request`、`unsupported_version`、`cooldown`、`slimevr_unavailable`、`slimevr_timeout`、`adapter_error`を扱う。

接続確認には`{"version": 1, "type": "ping", "request_id": "..."}`を送り、Bridgeは`type = "pong"`、`code = "bridge_ready"`の結果形式で応答する。

Bridgeは同じ`request_id`の再受信にAdapterを再実行せず、キャッシュした同じ結果を送信元へ返す。壊れたJSONやrequest_idを特定できない要求には応答せず、警告ログだけを残す。

### 7.4 Bridgeの検出

- アプリは`{"version": 1, "type": "discover", "request_id": "..."}`を送る
- 送信先は`255.255.255.255:39500`へのブロードキャストと、端末自身の各IPv4アドレスが属する/24内の全ホストへのユニキャスト
  - iOSはブロードキャストにmulticast entitlementが必要なため、ユニキャスト探索を必須とする
  - 携帯回線・VPNのインターフェースは探索対象から外す
- Bridgeは`type = "announce"`、`name`（ホスト名）付きで送信元へ応答する
- 1件ならそのBridgeを自動選択し、複数なら一覧から選ばせる
- `/24`全体の探索は初回設定の「探す」を押したときだけ実行する
- 監視画面を開いたときは保存済みBridgeへの接続確認だけを行い、姿勢推定とLAN探索を競合させない

## 8. Go BridgeとSlimeVR

### 8.1 結論

GoからSlimeVR Serverへ直接通信できる。

調査対象のSlimeVR Server v21.1.0はTCPポート`21110`でRFC 6455 WebSocketを待ち受け、バイナリフレームとしてSolarXR ProtocolのFlatBuffers `MessageBundle`を受け取る。RPCにはYaw Reset用の`ResetRequest`と完了通知の`ResetResponse`が定義されている。

これはHTTP/JSON APIではない。SlimeVRのトラッカー向けUDPプロトコルへリセット命令を送る方式でもない。

### 8.2 SlimeVR Adapter

```go
type ResetAdapter interface {
	Reset(ctx context.Context, kind Kind) error // kind: yaw / full
}
```

`slimevr` Adapterは次を行う。

1. 同一PCの`ws://127.0.0.1:21110`へ接続する
2. 公式`all.fbs`から生成したGo型でFlatBuffersを構築する
3. `MessageBundle.rpc_msgs`へ、`tx_id`付き`ResetRequest`を1件入れる
4. `reset_type = Yaw`（手動Full Resetでは`Full`）、`body_parts = []`、`delay = 0`を指定する
5. バイナリWebSocketフレームとして送る
6. 同じ`tx_id`、同じ`reset_type`、`status = FINISHED`の`ResetResponse`を待つ
7. タイムアウトまたは切断をエラーとしてモバイルへ返す

SlimeVRの既定ディレイは使わない。モバイル側でAポーズを2秒確認した後に送るため、要求の`delay`は明示的に0秒とする。

公式SolarXR Protocolリポジトリには現時点で生成済みGoコードがないため、`flatc --go schema/all.fbs`で生成する。生成元のコミットSHAをBridge内に記録し、生成コードをコミットする。手書きでFlatBuffersのバイト列を組み立てない。

SlimeVR APIは認証もTLSも提供しない。Bridgeは`127.0.0.1:21110`だけへ接続し、SlimeVRの21110番ポートを外部公開しない。Mobile → Bridgeも信頼できる同一LANでのみ使う。

### 8.3 制約

- Yaw Resetの前にSlimeVR側でFull Resetが必要
- `FINISHED`はSlimeVRが処理を完了した通知であり、身体姿勢の正しさを保証しない
- WebSocket/FlatBuffers APIは公式GUIでも使われているが、安定版として文書化された外部APIではないため、SlimeVR更新時に互換性確認が必要
- 対応確認の基準はSlimeVR Server v21.1.0、SolarXR Protocol commit `00c38a6dc28070b30850a89c26b17928e56245d4`

### 8.4 重複防止

- 処理済み`request_id`と結果を5分保持する
- 同じIDではAdapterを再実行しない
- 1端末につき3秒のクールダウンを設ける
- SlimeVR向けRPCごとに異なる`tx_id`を割り当てる
- 受信した応答は`tx_id`とReset種別の両方で照合する

## 9. 実装順序

1. Aポーズ判定を純粋関数と状態機械へ分離する
2. 固定ランドマークによる単体テストを作る
3. Mock AdapterでMobile → Bridgeを接続する
4. SolarXR ProtocolからGoコードを生成する手順を固定する
5. SlimeVR Adapterを実装する
6. ユーザーが実機とSlimeVR Server v21.1.0で確認する

Mockは開発用の代替であり、MVPの最終ゴールはSlimeVR AdapterによるYaw Reset成功とする。

## 10. テスト方針

### エミュレーターを使わないテスト

- Aポーズ各条件の純粋関数テスト
- 2秒成立、姿勢崩れ、ラッチ解除の状態機械テスト
- Flutter widget testによる文言・状態・画面遷移の確認
- JSON validation、重複排除、クールダウンのGo単体テスト
- 偽WebSocket Serverを使ったFlatBuffers要求・応答テスト
- Mock Adapterを使ったローカル結合テスト

簡単なUI変更や上記の自動テストのためにエミュレーターを起動しない。

### ユーザーが実機で行うテスト

- カメラ、権限、骨格追従、端末回転、処理速度
- Aポーズのしきい値調整
- Android/iPhone → Bridge
- Bridge → 実SlimeVR Server → 実トラッカー
- SlimeVR停止、ネットワーク切断、アプリ復帰

エージェントはエミュレーター、実機アプリ、SlimeVR Serverを起動しない。コード編集、静的解析、単体テスト、モックによる確認までを担当し、実機確認手順を利用者へ渡す。

## 11. 実装ルール

- この仕様にない機能を追加しない
- Aポーズ以外を補正ジェスチャーにしない
- 数値しきい値を名前付き設定へ集約する
- 映像、画像、全ランドマークを送信・保存しない
- SlimeVR固有処理を`ResetAdapter`内へ隔離する
- Mobile → BridgeのJSONとBridge → SlimeVRのFlatBuffersを混同しない
- SlimeVRのバージョン更新時は、スキーマ差分とReset RPCを再確認する

## 12. 参考資料

- [SlimeVR用語集: Full Reset / Yaw Reset](https://docs.slimevr.dev/glossary.html)
- [SlimeVR Quick Setup: resetの役割](https://docs.slimevr.dev/quick-setup)
- [SlimeVR Server v21.1.0](https://github.com/SlimeVR/SlimeVR-Server/releases/tag/v21.1.0)
- [SlimeVR WebSocket server implementation](https://github.com/SlimeVR/SlimeVR-Server/blob/c11dc54ed1a745ffc4b15db7f820d8d0c1993990/server/core/src/main/java/dev/slimevr/websocketapi/WebsocketAPI.java)
- [SlimeVR Reset RPC handler](https://github.com/SlimeVR/SlimeVR-Server/blob/c11dc54ed1a745ffc4b15db7f820d8d0c1993990/server/core/src/main/java/dev/slimevr/protocol/rpc/reset/RPCResetHandler.kt)
- [SolarXR Protocol RPC schema](https://github.com/SlimeVR/SolarXR-Protocol/blob/00c38a6dc28070b30850a89c26b17928e56245d4/schema/rpc.fbs)
- [SolarXR Protocol root schema](https://github.com/SlimeVR/SolarXR-Protocol/blob/00c38a6dc28070b30850a89c26b17928e56245d4/schema/all.fbs)
- [Google ML Kit Pose Detection](https://developers.google.com/ml-kit/vision/pose-detection)
