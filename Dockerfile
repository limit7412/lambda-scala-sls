# ビルド専用イメージ: Scala Native の `bootstrap` バイナリを Amazon Linux 2023 上で
# コンパイルし、Lambda の `provided.al2023` ランタイムと glibc / libcurl を一致させる
# (Debian 上でビルドしたバイナリは互換性のない libcurl/glibc にリンクされ、Lambda 上で
#  GLIBC_* not found / curl OPERATION_TIMEDOUT でクラッシュする)。
#
# ここで作ったバイナリはコンテナイメージとしてではなく、抽出して Lambda の zip
# (provided.al2023 カスタムランタイム) としてデプロイする。
FROM --platform=linux/amd64 amazonlinux:2023 AS build-image

RUN dnf install -y \
      clang \
      gcc \
      glibc-devel \
      libstdc++-devel \
      zlib-devel \
      libcurl-devel \
      openssl-devel \
      libidn2-devel \
      java-17-amazon-corretto-headless \
      tar gzip which findutils \
    && dnf clean all

# scala-cli (static x86_64 linux launcher)
RUN curl -fsSL https://github.com/VirtusLab/scala-cli/releases/latest/download/scala-cli-x86_64-pc-linux.gz \
      | gunzip > /usr/local/bin/scala-cli \
    && chmod +x /usr/local/bin/scala-cli

WORKDIR /work
COPY ./ ./

RUN scala-cli clean .
RUN scala-cli config power true
# target GraalVM
# RUN scala-cli --power package --native-image -o bootstrap .
# target Scala Native
RUN scala-cli --power package --native -o bootstrap .
RUN chmod +x bootstrap

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
