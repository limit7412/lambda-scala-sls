# ビルド専用イメージ: Scala Native の `bootstrap` バイナリを Alpine (musl) 上で
# 静的リンク(static)してビルドする (#22)。
#
# 完全静的リンクにより、Lambda 実行環境 (provided.al2023) の glibc / libcurl の
# バージョンに依存しない自己完結バイナリになる。これによりビルド環境とランタイム
# 環境のライブラリ整合を取る必要がなくなる (従来は Amazon Linux 2023 上でビルドして
# glibc/libcurl を一致させていた。下部にコメントで保持)。
#
# ここで作ったバイナリはコンテナイメージとしてではなく、抽出して Lambda の zip
# (provided.al2023 カスタムランタイム) としてデプロイする。
FROM --platform=linux/arm64 alpine:3.21 AS build-image

# ビルドツールチェーン + libcurl とその推移的依存の「静的アーカイブ(.a)」一式。
#  - Scala Native は clang でコンパイル/リンクするため clang/lld/llvm が必要
#  - scala-cli の glibc 製ネイティブランチャを musl 上で動かすため gcompat を入れる
#  - JVM は musl ネイティブの openjdk17 をシステム JVM として使う
#  - *-static は libcurl(OpenSSL/zlib/nghttp2/brotli/zstd/idn2 ...) の静的リンク用
RUN apk add --no-cache \
      bash curl tar gzip which findutils coreutils \
      build-base clang lld llvm \
      gcompat libstdc++ libgcc \
      openjdk17 \
      pkgconf \
      curl-static curl-dev \
      openssl-libs-static \
      zlib-static \
      nghttp2-static \
      brotli-static \
      zstd-static \
      libidn2-static \
      libunistring-static \
      libpsl-static

# scala-cli にシステム JVM(musl ネイティブ)を使わせるため JAVA_HOME を明示
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# scala-cli (arm64 linux launcher)。glibc 製のため gcompat 経由で実行する。
RUN curl -fsSL https://github.com/VirtusLab/scala-cli/releases/latest/download/scala-cli-aarch64-pc-linux.gz \
      | gunzip > /usr/local/bin/scala-cli \
    && chmod +x /usr/local/bin/scala-cli

WORKDIR /work
COPY ./ ./

RUN scala-cli clean .
RUN scala-cli config power true
# target GraalVM
# RUN scala-cli --power package --native-image -o bootstrap .
# target Scala Native (静的リンクは project.scala の nativeLinkingOptions で指定)
#  --jvm system : musl ネイティブの openjdk17 を使用 (glibc JVM の自動DLを回避)
#  --server=false: Bloop ビルドサーバを使わずインプロセスでビルド
RUN scala-cli --power package --native --jvm system --server=false -o bootstrap .
RUN chmod +x bootstrap
# 静的バイナリであることの簡易確認 (動的依存が無ければ "not a dynamic executable")
RUN ldd bootstrap || true

# ============================================================================
# 旧: Amazon Linux 2023 (glibc) 上で動的リンクビルドしていた版。
# Lambda 実行環境と glibc/libcurl を一致させるため AL2023 上でビルドしていたが、
# 静的(musl)リンク版 (#22) へ移行したためコメントで保持。
# ============================================================================
#
# FROM --platform=linux/arm64 amazonlinux:2023 AS build-image
#
# RUN dnf install -y \
#       clang \
#       gcc \
#       glibc-devel \
#       libstdc++-devel \
#       zlib-devel \
#       libcurl-devel \
#       openssl-devel \
#       libidn2-devel \
#       java-17-amazon-corretto-headless \
#       tar gzip which findutils \
#     && dnf clean all
#
# RUN curl -fsSL https://github.com/VirtusLab/scala-cli/releases/latest/download/scala-cli-aarch64-pc-linux.gz \
#       | gunzip > /usr/local/bin/scala-cli \
#     && chmod +x /usr/local/bin/scala-cli
#
# WORKDIR /work
# COPY ./ ./
#
# RUN scala-cli clean .
# RUN scala-cli config power true
# RUN scala-cli --power package --native -o bootstrap .
# RUN chmod +x bootstrap

# ============================================================================
# 以下は Docker(コンテナイメージ)版の Lambda デプロイ用 Dockerfile。
# zip(provided.al2023 カスタムランタイム)版へ移行したため無効化している。
# サンプル実装として両方式を残すためコメントで保持。
# ============================================================================
#
# FROM virtuslab/scala-cli:latest as build-image
#
# RUN apt-get update && apt-get install -y libcurl4-openssl-dev && rm -rf /var/lib/apt/lists/*
#
# WORKDIR /work
# COPY ./ ./
#
# RUN scala-cli clean .
# RUN scala-cli config power true
# # target GraalVM
# # RUN scala-cli --power package --native-image -o bootstrap .
# # target Scala Native
# RUN scala-cli --power package --native -o bootstrap .
# RUN chmod +x bootstrap
#
# # コンテナイメージ版ではここで Lambda 用ベースイメージに bootstrap を載せていた
# FROM public.ecr.aws/lambda/provided:latest
#
# COPY --from=build-image /work/bootstrap /var/runtime/
#
# CMD ["dummyHandler"]
