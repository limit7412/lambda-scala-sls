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
#  - *-static は libcurl(OpenSSL/zlib/nghttp2/zstd/idn2 ...) の静的リンク用
#  - c-ares-dev: Alpine の libcurl は c-ares 有効ビルドで libcurl.a が ares_* を
#    参照する。Alpine に c-ares-static は無く libcares.a は c-ares-dev に含まれる
#  - brotli/libpsl は Alpine の *-static が GCC LTO アーカイブでクロス ld が解決
#    できないため後段でソースから非LTO静的ビルドする。cmake と libidn2/unistring
#    の dev ヘッダ(libpsl ビルド用)を入れる
RUN apk add --no-cache \
      bash curl tar gzip which findutils coreutils \
      build-base clang lld llvm cmake \
      gcompat libstdc++ libstdc++-dev libgcc \
      openjdk17 \
      pkgconf \
      curl-static curl-dev \
      openssl-libs-static \
      zlib-static \
      nghttp2-static \
      zstd-static \
      libidn2-static libidn2-dev \
      libunistring-static libunistring-dev \
      c-ares-dev

# scala-cli にシステム JVM(musl ネイティブ)を使わせるため JAVA_HOME を明示
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

# scala-cli (arm64 linux launcher)。glibc 製のため gcompat 経由で実行する。
RUN curl -fsSL https://github.com/VirtusLab/scala-cli/releases/latest/download/scala-cli-aarch64-pc-linux.gz \
      | gunzip > /usr/local/bin/scala-cli \
    && chmod +x /usr/local/bin/scala-cli

# Alpine の brotli-static / libpsl-static は GCC LTO (GIMPLE bitcode) の静的アーカイブで、
# Scala Native のリンクで使われるクロス ld が中の object を解決できない
# ("plugin needed to handle lto object" / undefined BrotliDecoder*・psl_*)。
# そこで brotli と libpsl を非LTOの静的ライブラリとしてソースからビルドし /usr/local
# へ入れ、リンク時に /usr/local/lib を優先させる。(他の依存=nghttp2/openssl/zlib/
# zstd/idn2/unistring/c-ares は非LTO静的のためそのまま使える)

# brotli (cmake, 非LTO 静的)。cmake が libbrotli*-static.a で出す版に備え、
# サフィックス無しの別名(-lbrotlidec 等で参照可能に)も用意する。
ARG BROTLI_VERSION=1.1.0
RUN curl -fsSL "https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz" \
      | tar xz -C /tmp \
    && cmake -S "/tmp/brotli-${BROTLI_VERSION}" -B /tmp/brotli-build \
         -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
         -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_INSTALL_LIBDIR=lib \
    && cmake --build /tmp/brotli-build --target install -j "$(nproc)" \
    && for f in /usr/local/lib/libbrotli*-static.a; do \
         [ -e "$f" ] && ln -sf "$f" "${f%-static.a}.a" || true; \
       done \
    && ls -l /usr/local/lib/libbrotli*.a

# libpsl (autotools, 非LTO 静的)。--enable-builtin=no で PSL データ生成を省略
# (curl の psl.c が要求するシンボルを満たすのが目的でランタイムでは未使用)。
ARG LIBPSL_VERSION=0.21.5
RUN curl -fsSL "https://github.com/rockdaboot/libpsl/releases/download/${LIBPSL_VERSION}/libpsl-${LIBPSL_VERSION}.tar.gz" \
      | tar xz -C /tmp \
    && cd "/tmp/libpsl-${LIBPSL_VERSION}" \
    && ./configure --prefix=/usr/local --enable-static --disable-shared \
         --enable-runtime=libidn2 --enable-builtin=no \
    && make -j "$(nproc)" && make install \
    && ls -l /usr/local/lib/libpsl.a

WORKDIR /work
COPY ./ ./

RUN scala-cli clean .
RUN scala-cli config power true
# target GraalVM
# RUN scala-cli --power package --native-image -o bootstrap .
# target Scala Native
#  --jvm system : musl ネイティブの openjdk17 を使用 (glibc JVM の自動DLを回避)
#  --server=false: Bloop ビルドサーバを使わずインプロセスでビルド
#  --native-linking: 完全静的リンク。Scala Native は @link("curl") で -lcurl のみ
#    付与するため libcurl の推移的依存(c-ares/OpenSSL/zlib/nghttp2/brotli/zstd/idn2/
#    psl 等)を明示する。これらは相互依存(例: libpsl→idn2, brotlidec→brotlicommon)
#    があり、静的リンクでは解決順序が問題になる。--start-group/--end-group を別々の
#    --native-linking で渡すと Scala Native のオプション整列でグループが分断され得る
#    ため、グループ全体を 1 つの -Wl, 引数にまとめて原子的に渡す。
#    -L/usr/local/lib でソースビルドした非LTOの brotli/libpsl を優先的に探索する。
#    (Linux/リンカー依存のため project.scala ではなくここで指定し移植性を保つ)
RUN scala-cli --power package --native --jvm system --server=false \
      --native-linking "-static" \
      --native-linking "-L/usr/local/lib" \
      --native-linking "-Wl,--start-group,-lcurl,-lnghttp2,-lssl,-lcrypto,-lz,-lbrotlienc,-lbrotlidec,-lbrotlicommon,-lzstd,-lidn2,-lunistring,-lpsl,-lcares,--end-group" \
      -o bootstrap .
RUN chmod +x bootstrap
# 静的バイナリであることをアサート: musl では静的バイナリに ldd すると非ゼロ終了
# するため、! で反転し「動的リンクだったらビルド失敗」させる。
RUN ! ldd bootstrap

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
