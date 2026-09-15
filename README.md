# camesura

スマートフォンをトラッカーとして利用し、SlimeVR へデータを中継するためのプロジェクトです。

## ディレクトリ構成

```text
camesura/
├── mobile/          # Flutter（Android / iOS）
├── bridge/          # Go（SlimeVR との中継）
├── protocol/        # スマートフォン ↔ Bridge の通信仕様
├── docs/            # 発表資料・構成図
└── .github/
    └── workflows/   # CI/CD
```

現在はFlutterアプリのトップ画面と、チーム共通の開発環境・CIまでを用意しています。

## 初回セットアップ

FlutterとGoはmiseでプロジェクト単位に固定します。各自が個別にSDKを選んで導入する必要はありません。

### macOS（推奨）

Homebrewだけを事前に導入し、次のスクリプトを実行します。

```sh
./scripts/bootstrap-macos.sh
```

このスクリプトはBrewfileからmise、Android Studio、Android SDK Command-line Tools、CocoaPodsを導入し、続けて固定SDKとプロジェクト依存関係をセットアップします。Xcode本体とSDKライセンス同意だけは本人操作が必要です。

### その他のOS／手動セットアップ

Git、mise 2026.9.1以上、Android Studioを導入後、リポジトリのルートで実行します。

```sh
mise trust
mise install
mise run setup
```

miseだけを個別に導入する場合、macOSでは次のコマンドを利用できます。

```sh
brew install mise
```

`mise install`により、`mise.toml`で固定したFlutter 3.47.4とGo 1.26.2が自動的に導入されます。`mise run setup`はFlutterパッケージとGoモジュールを取得し、端末固有の不足項目を表示します。

## 開発コマンド

```sh
mise run doctor          # Flutter環境の診断
mise run mobile-format   # Dartフォーマットの確認
mise run mobile-analyze  # Flutter静的解析
mise run mobile-test     # Flutterテスト
mise run bridge-test     # Goテスト
mise run android-run     # 接続したAndroid端末で起動
mise run android-apk     # 動作確認用リリースAPKを生成
mise run ci              # CIと同じ全チェック
```

Flutterアプリの起動:

```sh
mise run android-run
```

## Androidで動かす

### 実機

1. Android端末の開発者向けオプションとUSBデバッグを有効にする
2. USBでMacへ接続し、端末側のデバッグ許可を承認する
3. `mise exec -- flutter devices`で端末が表示されることを確認する
4. `mise run android-run`を実行する

### エミュレーター

Android StudioのDevice Managerから端末を起動して、`mise run android-run`を実行します。

### APKを作る

```sh
mise run android-apk
```

生成先は`mobile/build/app/outputs/flutter-apk/app-release.apk`です。現在のreleaseビルドは開発用キーで署名しているため、チーム内の動作確認用です。Google Playへ公開するときは専用の署名設定を追加します。

バージョンタグをpushすると、GitHub Actionsが同じmise環境でテストとAPKビルドを行い、APKとSHA-256チェックサムをGitHub Releaseへ自動添付します。

```sh
git tag v0.1.0
git push origin v0.1.0
```

## 固定バージョン

- mise 2026.9.1以上
- Flutter 3.47.4 / Dart 3.13.3
- Go 1.26.2

バージョン定義は`mise.toml`を唯一の正として、GitHub Actionsでも同じ定義を利用します。

### Android の残作業

Android Studioを初回起動し、SDK ManagerからAndroid SDK 36とBuild Tools 28.0.3を追加します。その後、次のコマンドでライセンス内容を確認して同意します。

```sh
flutter doctor --android-licenses
```

### iOS の残作業

App StoreからXcodeを導入して初回起動を済ませた後、CocoaPodsを導入して次のコマンドを実行します。

```sh
brew install cocoapods
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

最後に `flutter doctor -v` を再実行し、開発対象の項目がすべて有効になったことを確認します。
