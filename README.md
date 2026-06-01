# lambda-scala-sls

Scala CLI（とScala Native）でAWS Lambdaを自力で動かして見たかった話
Scalaらしいコードを書けたかというと微妙な気がするがまあいいでしょう

  - scala3 / Scala Native / scala-cli
  - aws lambda
    - provided.al2023 カスタムランタイム (zipアップロード形式)
  - serverless framework

## デプロイ

`bootstrap` (Scala Nativeバイナリ) をビルドして zip でアップロードする。
ビルドは Lambda 実行環境 (provided.al2023) と glibc/libcurl の互換性を保つため、
Amazon Linux 2023 のコンテナ内で行う ([Dockerfile](Dockerfile))。

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
