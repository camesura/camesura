# bridge

スマートフォンからのリセット（Full Reset / Yaw Reset）要求をUDP（既定ポート`39500`）で受け取り、SlimeVR Serverへ中継するGoアプリケーションです。`ResetAdapter`はMock版と、SlimeVR Server（`ws://127.0.0.1:21110`）へSolarXR Protocol（WebSocket + FlatBuffers）で`ResetRequest`を送るSlimeVR版の2つを実装しています。

## Macで起動する

Mock Adapter（SlimeVRなしで疎通確認する場合）:

```sh
mise run bridge-run
# または
cd bridge && go run ./cmd/camesura-bridge -listen :39500 -adapter mock
```

SlimeVR Adapter（実際にSlimeVRへリセットを送る場合）:

```sh
cd bridge && go run ./cmd/camesura-bridge -listen :39500 -adapter slimevr
```

起動ログの`enter this address in the mobile app ip=...`に表示されたIPアドレスを、アプリの補正準備画面の「IPアドレスを設定」へ入力します。スマートフォンとMacは同じLANに接続してください（スマホのホットスポットにMacを繋いでいる場合も同様に動作します）。

初回起動時にmacOSのファイアウォールが受信接続の許可を求めた場合は「許可」を選びます。

## 構成

- `cmd/camesura-bridge`: エントリポイント
- `internal/protocol`: Mobile ↔ BridgeのJSONメッセージと検証
- `internal/server`: UDP受信、重複排除（5分）、端末ごとのクールダウン（3秒）
- `internal/resetadapter`: `ResetAdapter`、Mock実装、SlimeVR実装（`slimevr.go`）
- `internal/solarxr`: `flatc`で生成したSolarXR ProtocolのGoコード（手編集禁止）

## 手動で疎通確認する

```sh
echo '{"version":1,"type":"ping","request_id":"test"}' | nc -u -w1 127.0.0.1 39500
```

## SolarXR ProtocolのGoコードを再生成する

`internal/solarxr`はSolarXR Protocolリポジトリのコミット`00c38a6dc28070b30850a89c26b17928e56245d4`から`flatc`で生成しています。スキーマ更新時は次の手順で再生成してください。

```sh
brew install flatbuffers   # flatcが未導入の場合
git clone https://github.com/SlimeVR/SolarXR-Protocol.git /tmp/solarxr-repo
cd /tmp/solarxr-repo && git checkout <新しいコミットSHA>

flatc --go --gen-all \
  --go-module-name github.com/camesura/camesura/bridge/internal/solarxr \
  -o /tmp/solarxr-gen schema/all.fbs

rm -rf <このリポジトリ>/bridge/internal/solarxr/solarxr_protocol
cp -R /tmp/solarxr-gen/solarxr_protocol <このリポジトリ>/bridge/internal/solarxr/
gofmt -w <このリポジトリ>/bridge/internal/solarxr
```

再生成後は`internal/solarxr/GENERATED.md`と本READMEのコミットSHAを更新し、`ResetRequest`/`ResetResponse`のフィールドがAdapter側の想定と一致するか確認してください。
