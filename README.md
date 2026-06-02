# lambda-scala-sls

Scala CLI（とScala Native）でAWS Lambdaを自力で動かして見たかった話
Scalaらしいコードを書けたかというと微妙な気がするがまあいいでしょう

  - scala3 / Scala Native / scala-cli
  - aws lambda
    - provided.al2023 カスタムランタイム (zipアップロード形式)
  - serverless framework

## デプロイ

`bootstrap` (Scala Nativeバイナリ) をビルドして zip でアップロードする。
ビルドは Alpine (musl) コンテナ内で **静的リンク (static build)** して行う ([Dockerfile](Dockerfile))。
完全静的リンクにより Lambda 実行環境 (provided.al2023) の glibc/libcurl の
バージョンに依存しない自己完結バイナリになるため、ビルド環境とランタイム環境の
ライブラリ整合を取る必要がなくなる (#22)。
(以前は glibc/libcurl を一致させるため Amazon Linux 2023 上でビルドしていた。
[Dockerfile](Dockerfile) 下部にコメントで保持)。

`serverless-plugin-scripts` により、`sls deploy` / `sls package` の
パッケージング直前 (`before:package:createDeploymentArtifacts`) に
`bootstrap` が自動でビルド・取り出しされる (Docker が必要)。

```shell
# プラグインをインストール
$ npm install

# deploy (bootstrap の生成 → zip化 → アップロードまで自動)
$ sls deploy --stage <stage_name>
```

## Docker（コンテナイメージ）版について

このリポジトリはサンプル実装のため、以前の Docker イメージ
（ECR コンテナイメージ）版のデプロイ設定も各ファイルにコメントで残してある。

  - [serverless.yml](serverless.yml): `ecr.images` / `image.command` などをコメント保持
  - [Dockerfile](Dockerfile): コンテナイメージ用のビルドステージをコメント保持
