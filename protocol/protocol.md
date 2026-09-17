# Communication Protocol

通信仕様の正本は[camesura-spec.md](../camesura-spec.md)とする。

- Mobile → Bridge: UDP / UTF-8 JSON（仕様書7章）
- Bridge → SlimeVR Server: WebSocket / SolarXR Protocol FlatBuffers（仕様書8章）

ここへ同じフィールド定義を複製しない。通信仕様を変更するときは仕様書、実装、テスト用fixtureを同じ変更で更新する。
