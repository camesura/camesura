# bridge

スマートフォンからのリセット（Full Reset / Yaw Reset）要求をUDP（既定ポート`39500`）で受け取り、SlimeVR Serverへ中継するGoアプリケーションです。`ResetAdapter`はMock版と、SlimeVR Server（`ws://127.0.0.1:21110`）へSolarXR Protocol（WebSocket + FlatBuffers）で`ResetRequest`を送るSlimeVR版の2つを実装しています。

## 配布版を起動する

GitHub ReleaseからOSとCPUに合うファイルを展開し、SlimeVR Serverを起動してから`camesura-bridge`（Windowsは`camesura-bridge.exe`）を開きます。引数なしで起動するとSlimeVR Adapterを使ってバックグラウンドで動作します。Go、FlatBuffers、設定ファイル、インストーラーは不要です。

ログはOSのユーザーキャッシュディレクトリ内にある`CameSura/camesura-bridge.log`へ保存されます。動作確認のためコンソールを開いたままにする場合:

```sh
./camesura-bridge -foreground
```

明示的にバックグラウンド起動する場合:

```sh
./camesura-bridge -background
```

Mock Adapter（SlimeVRなしで開発時の疎通確認をする場合）:

```sh
mise run bridge-run-mock
# または
go run ./cmd/camesura-bridge -foreground -adapter mock
```

スマホアプリの初回設定で「Bridgeを探す」を押します。見つからない場合は、起動ログの`manual address ip=...`に表示されたIPアドレスを「IPアドレスを設定」へ入力します。スマートフォンとPCは同じLANに接続してください（スマホのホットスポットにPCを繋いでいる場合も同様に動作します）。

初回起動時にOSのファイアウォールが受信接続の許可を求めた場合は許可します。未署名のmacOS配布物はGatekeeperに止められる場合があるため、一般公開時はコード署名とnotarizationを追加します。

## 構成

- `cmd/camesura-bridge`: エントリポイント
- `internal/protocol`: Mobile ↔ BridgeのJSONメッセージと検証
- `internal/server`: UDP受信、重複排除（5分）、端末ごとのクールダウン（3秒）
- `internal/resetadapter`: `ResetAdapter`、Mock実装、SlimeVR実装（`slimevr.go`）
- `internal/solarxr`: `flatc`で生成したSolarXR ProtocolのGoコード（手編集禁止）

## 手動で疎通確認する

```sh
echo '{"version":1,"type":"ping","request_id":"test"}' | nc -u -w1 127.0.0.1 39500
echo '{"version":1,"type":"discover","request_id":"test"}' | nc -u -w1 127.0.0.1 39500
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
