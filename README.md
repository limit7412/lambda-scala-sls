# lambda-scala-sls

Scala CLI（とScala Native）でAWS Lambdaを自力で動かして見たかった話
Scalaらしいコードを書けたかというと微妙な気がするがまあいいでしょう

  - scala3 / Scala Native / scala-cli
  - aws lambda
    - provided.al2023 カスタムランタイム (zipアップロード形式)
  - serverless framework

## デプロイ

`bootstrap` (Scala Native バイナリ) をビルドし、zip でアップロードする。
ビルドは scala-cli 公式イメージ (`virtuslab/scala-cli`, Debian/glibc) 内で行い、完全静的リンクする ([Dockerfile](Dockerfile))。
静的リンクした自己完結バイナリは Lambda 実行環境 (provided.al2023) の glibc/libcurl のバージョンに依存しないため、ビルド環境とランタイム環境でライブラリの整合を取る必要がなくなる (#22)。
(以前は glibc/libcurl を一致させるため Amazon Linux 2023 上で、その後 Alpine (musl) 上でビルドしていた。経緯は #22, #28 を参照。)

公式イメージが amd64 のみの提供のため、Lambda のアーキテクチャは x86_64 にしている (#28)。
Apple Silicon などでローカルビルドする場合は QEMU エミュレーションになる。

パッケージングは `serverless-plugin-scripts` のフックで自動化していて、`sls deploy` / `sls package` を実行すると zip 化の直前 (`before:package:createDeploymentArtifacts`) に Docker 内で `bootstrap` のビルドと取り出しが走る (Docker が必要)。

```shell
# プラグインをインストール
$ npm install

# デプロイ (bootstrap の生成から zip 化、アップロードまで自動)
$ sls deploy --stage <stage_name>
```
