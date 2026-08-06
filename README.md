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
(以前は glibc/libcurl を一致させるため Amazon Linux 2023 上でビルドしていた)。

`serverless-plugin-scripts` により、`sls deploy` / `sls package` の
パッケージング直前 (`before:package:createDeploymentArtifacts`) に
`bootstrap` が自動でビルド・取り出しされる (Docker が必要)。

### libcurl を最小構成でソースビルドしている理由 (#28)

静的リンクの都合で、[Dockerfile](Dockerfile) では libcurl を自前でソースビルドしている。

Alpine の `curl-static` は OpenSSL / nghttp2 / brotli / zstd / idn2 / psl / c-ares
込みでビルドされているため、静的リンクするとそれら全ての静的アーカイブが芋づる式に
必要になる。さらに Alpine の `brotli-static` / `libpsl-static` は GCC LTO 済みの
アーカイブでクロス ld が中の object を解決できず、この 2 つはソースから非LTOで
ビルドし直す必要があった (#22)。これが Dockerfile 肥大化の主因だった。

通信相手は Lambda Runtime API (`http://127.0.0.1:9001/...`) だけで **TLS も名前解決も
HTTP/2 も圧縮も不要**なので、それらを全て無効にした最小構成の libcurl をビルドすれば
依存が消える。結果、`*-static` パッケージ群と brotli / libpsl のソースビルドが
まるごと不要になり、リンク対象は libcurl と libidn2 → libunistring だけになった。

なお libidn2 は libcurl ではなく **sttp-model が `@link("idn2")` で要求する**
(国際化ドメイン名の変換用) ため、curl を最小化しても残る。

### x86_64 + 公式イメージ案 (#28 の b-2) を見送った理由

#28 の本命は「libcurl 依存そのものを排除 (HTTP を自前実装) すれば依存が libc だけに
なり、amd64 単一アーキの公式イメージ `virtuslab/scala-cli` (Debian/glibc) 上でも
`-static` が通る」という案だったが、次の 2 点により採用していない。

1. HTTP クライアントを自前実装することになり、本リポジトリの趣旨から外れる。
2. そもそも **glibc の完全静的リンクが成立しない**。glibc + `-static` の Scala Native
   バイナリはリンクは通るが起動直後に SIGSEGV (exit 139) で落ちる。
   `println("hello")` だけの最小プログラムでも再現するため本リポジトリのコードとは
   無関係で、Scala Native ランタイムと glibc 静的リンクの相性問題。
   動的リンクなら正常に起動し、musl なら静的でも正常に動作する。

このため musl (Alpine) + arm64 (Graviton) を維持している。

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
