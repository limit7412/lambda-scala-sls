# ビルド専用イメージ: Scala Native の `bootstrap` を Alpine (musl) 上で完全静的リンクする。
# 生成物はコンテナイメージではなく、抽出して Lambda の zip
# (provided.al2023 カスタムランタイム) としてデプロイする。
FROM --platform=linux/arm64 alpine:3.21 AS build-image

# clang/lld/llvm: Scala Native のコンパイル/リンク
# gcompat: scala-cli の glibc 製ランチャを musl 上で動かす
# openjdk17: システム JVM (musl ネイティブ)
# libidn2/libunistring: libcurl ではなく sttp-model が @link("idn2") で要求する
RUN apk add --no-cache \
      curl \
      build-base clang lld llvm \
      gcompat libstdc++ libstdc++-dev libgcc \
      openjdk17 \
      libidn2-static libidn2-dev \
      libunistring-static libunistring-dev

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk
ENV PATH="${JAVA_HOME}/bin:${PATH}"

RUN curl -fsSL https://github.com/VirtusLab/scala-cli/releases/latest/download/scala-cli-aarch64-pc-linux.gz \
      | gunzip > /usr/local/bin/scala-cli \
    && chmod +x /usr/local/bin/scala-cli

# 最小構成の libcurl を静的ビルドする (#28)。
# Alpine の curl-static は OpenSSL/nghttp2/brotli/zstd/psl/c-ares 込みのため、静的リンク
# するとそれら全ての静的アーカイブが要る (うち brotli/libpsl は Alpine の *-static が
# GCC LTO アーカイブでクロス ld が解決できず、ソースからの非LTOビルドが必要だった)。
# 通信相手は Lambda Runtime API だけで TLS も名前解決も HTTP/2 も圧縮も不要なので、
# それらを無効にして自前ビルドすれば依存ごと消える。
ARG CURL_VERSION=8.11.1
RUN curl -fsSL "https://curl.se/download/curl-${CURL_VERSION}.tar.gz" | tar xz -C /tmp \
    && cd "/tmp/curl-${CURL_VERSION}" \
    && ./configure --prefix=/usr/local --enable-static --disable-shared \
         --disable-ftp --disable-file --disable-ldap --disable-ldaps \
         --disable-rtsp --disable-dict --disable-telnet --disable-tftp \
         --disable-pop3 --disable-imap --disable-smb --disable-smtp \
         --disable-gopher --disable-mqtt --disable-manual --disable-docs \
         --without-ssl --without-zlib --without-brotli --without-zstd \
         --without-libpsl --without-libidn2 --without-nghttp2 --without-ngtcp2 \
         --without-libssh2 --without-librtmp --disable-ares \
    && make -j "$(nproc)" && make install

WORKDIR /work
COPY ./ ./

RUN scala-cli clean .
RUN scala-cli config power true
#  --jvm system   : musl ネイティブの openjdk17 を使う (glibc JVM の自動DLを回避)
#  --server=false : Bloop ビルドサーバを使わずインプロセスでビルド
#  --native-linking: リンクオプションは Linux/リンカー依存のため project.scala ではなく
#    ここで指定し、macOS/Windows でのローカル開発を壊さないようにする。
#    Scala Native は @link 由来の -l を独自順で並べるため、解決順序に依存しないよう
#    ライブラリ群は 1 つの -Wl, 引数にまとめて原子的に渡す。
RUN scala-cli --power package --native --jvm system --server=false \
      --native-linking "-static" \
      --native-linking "-L/usr/local/lib" \
      --native-linking "-Wl,--start-group,-lcurl,-lidn2,-lunistring,--end-group" \
      -o bootstrap .
RUN chmod +x bootstrap
# 静的リンクの検証。musl では静的バイナリへの ldd が非ゼロ終了するので ! で反転する。
RUN ! ldd bootstrap
# 起動できることの検証。_HANDLER 未設定なので NoSuchElementException で即終了するのが正常。
# リンクが通り ldd 上も静的なのに起動しない構成 (下記 glibc + -static) を検知するため。
RUN ./bootstrap 2>&1 | grep -q "NoSuchElementException: _HANDLER"

# #28 の本命だった「libcurl 排除 + 公式イメージ virtuslab/scala-cli (glibc) で x86_64」は
# 不採用。HTTP を自前実装することになり趣旨から外れる上、glibc + -static の Scala Native
# バイナリはリンクは通るが起動直後に SIGSEGV する (println("hello") だけでも再現。
# 動的リンクなら正常、musl なら静的でも正常)。よって musl + arm64 を維持している。

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
# RUN scala-cli --power package --native -o bootstrap .
# RUN chmod +x bootstrap
#
# # コンテナイメージ版ではここで Lambda 用ベースイメージに bootstrap を載せていた
# FROM public.ecr.aws/lambda/provided:latest
#
# COPY --from=build-image /work/bootstrap /var/runtime/
#
# CMD ["dummyHandler"]
