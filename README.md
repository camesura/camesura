# かめすら（CameSura）

スマートフォンのカメラで姿勢を確認し、SlimeVRのYaw Resetを正しい姿勢で行うための補助プロジェクトです。

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

現在はFlutterアプリのトップ画面と、背面カメラ映像へ端末内のML Kitで検出した骨格を重ねる補正準備画面を実装しています。チーム共通の開発環境、CI、Android APKの自動リリースも用意しています。

## 初回セットアップ

FlutterとGoはmiseでプロジェクト単位に固定します。各自が個別にSDKを選んで導入する必要はありません。

### macOS（推奨）

Homebrewだけを事前に導入し、次のスクリプトを実行します。

```sh
./scripts/bootstrap-macos.sh
```

このスクリプトはBrewfileからmise、Android Studio、Android SDK Command-line Tools、CocoaPodsを導入し、続けて固定SDKとプロジェクト依存関係をセットアップします。Xcode本体とSDKライセンス同意だけは本人操作が必要です。

### その他のOS／手動セットアップ

Git、mise 2026.9.9以上、Android Studioを導入後、リポジトリのルートで実行します。

```sh
mise trust
mise install
mise run setup
```

miseだけを個別に導入する場合、macOSでは次のコマンドを利用できます。

```sh
brew install mise
```

`mise install`により、`mise.toml`で固定したFlutter 3.47.4とGo 1.27.1が自動的に導入されます。`mise run setup`はFlutterパッケージとGoモジュールを取得し、端末固有の不足項目を表示します。

## 開発コマンド

```sh
mise run doctor          # Flutter環境の診断
mise run mobile-format   # Dartフォーマットの確認
mise run mobile-analyze  # Flutter静的解析
mise run mobile-test     # Flutterテスト
mise run bridge-test     # Goテスト
mise run bridge-run      # Bridgeを起動（Mock Adapter）
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

初回はカメラ権限を許可してください。「補正をはじめる」を押すと背面カメラが起動し、人物を検出すると映像上へ骨格が表示されます。映像は端末内だけで処理し、保存・送信しません。

### エミュレーター

Android StudioのDevice ManagerからAndroid端末を作成・起動して、`mise run android-run`を実行します。

エミュレーターでも画面構成は確認できますが、骨格追従の確認にはカメラを利用できるAndroid実機を推奨します。

## PCで画面をプレビューする

Android Emulatorを使うと、Mac上で実際のAndroid版を確認しながら開発できます。

1. Android Studioを開く
2. `Tools` → `Device Manager`を開く
3. `+` → `Create Virtual Device`からPixel系端末を作成する
4. 作成した端末の再生ボタンを押す
5. リポジトリで次を実行する

```sh
mise exec -- flutter devices
mise run android-run
```

ターミナルで`r`を押すとHot Reload、`R`で再起動、`q`で終了します。複数端末が表示される場合は、次のようにAndroidのdevice IDを指定します。

```sh
cd mobile
mise exec -- flutter run -d <device-id>
```

### APKを作る

```sh
mise run android-apk
```

生成先は`mobile/build/app/outputs/flutter-apk/app-release.apk`です。現在のreleaseビルドは開発用キーで署名しているため、チーム内の動作確認用です。Google Playへ公開するときは専用の署名設定を追加します。

### リリース（Release Please）

mainへのコミットは[Conventional Commits](https://www.conventionalcommits.org/ja/v1.0.0/)に従います。「リリースしたい」「リリースバージョンを作りたい」と都度判断する代わりに、機能・修正のマージだけでリリース候補が自動で積み上がり、タイミングを選んでマージするだけで公開できます。

- `fix:` は patch（0.2.0 → 0.2.1）
- `feat:` は minor（0.2.0 → 0.3.0）
- `!` / `BREAKING CHANGE` は major

#### リリースノートのルール

`feat:` / `fix:` のコミット件名が、そのままリリースノートの変更点になります。mainに入るコミット件名（squash mergeする場合はPRタイトル）は、次のルールで書きます。

- 必ず日本語で書く。
- 実装内容ではなく、リリース後にユーザーができるようになったことや、改善された体験を書く。
- 1件につき1つの変更点を、プロダクトバックログの完了項目として読める粒度で書く。
- `feat:` はユーザーに新しい価値を提供する変更、`fix:` はユーザーが遭遇する不具合の修正に使う。
- 内部のリファクタリング、テスト、CI、ドキュメントなどは `refactor:`、`test:`、`ci:`、`docs:`、`chore:` を使い、ユーザー向けリリースノートには載せない。

```text
# 良い例
feat: Aポーズを取るとトラッキングを開始できる
fix: Bridge接続中もポーズ検出が滑らかに動くように修正

# 避ける例
feat: Aポーズ判定クラスを追加
fix: タイマーのライフサイクル競合を修正
```

#### リリースの流れ

1. 通常の変更PRをマージする。mainに入る `feat:` / `fix:` のコミット件名は、上記ルールに従う。
2. mainへのpushを契機に、GitHub Actionsがリリース候補PRを作成または更新する。
3. リリース候補PRの `mobile/CHANGELOG.md` を確認し、すべての変更点が日本語かつユーザー視点になっていることを確認する。ルールに合わない場合は、元のPRタイトルまたはコミット件名を次回から直すだけで済ませず、公開前のリリースノートも日本語のユーザー向け表現へ整える。
4. リリースするタイミングでリリース候補PRをマージする。
5. バージョンタグ `v*` と GitHub Release が自動作成され、同じmise環境でビルドしたAPKとSHA-256チェックサムが自動で添付される。タグの手動pushは不要。

リリース候補PRはpubspec.yamlのバージョンとCHANGELOG.md、`.release-please-manifest.json`を更新します。

pubspec.yamlの`+ビルド番号`（AndroidのversionCode）はリリースのたびに自動でインクリメントされます。

> **補足**: 標準では`GITHUB_TOKEN`を使うため、Release Pleaseが作成したPR／Releaseをトリガーにした他workflow（CIなど）は実行されません。リリースPRでもCIを回したい場合は、PATをsecretへ登録しworkflowの`token`へ渡してください。また、リポジトリ設定で「Allow GitHub Actions to create and approve pull requests」を有効にする必要があります。

## 固定バージョン

- mise 2026.9.9以上
- Flutter 3.47.4 / Dart 3.13.3
- Go 1.27.1
- Android SDK 36 / Build Tools 36.0.0
- Android最低API 24
- iOS最低バージョン 15.5

バージョン定義は`mise.toml`を唯一の正として、GitHub Actionsでも同じ定義を利用します。

### Android の残作業

Android Studioを初回起動し、SDK ManagerからAndroid SDK 36とBuild Tools 36.0.0を追加します。その後、次のコマンドでライセンス内容を確認して同意します。

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
