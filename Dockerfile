# ビルド専用イメージ: Scala Native の `bootstrap` を scala-cli 公式イメージ
# (Debian/glibc) 上で完全静的リンクする (#28)。
# 生成物はコンテナイメージではなく、抽出して Lambda の zip
# (provided.al2023 カスタムランタイム) としてデプロイする。
#
# 公式イメージは amd64 単一アーキのため x86_64 が前提となる (#21 の arm64 化を巻き戻す)。
# 以前は Alpine (musl) 上でビルドしていたが、musl 版は JDK / gcompat / musl 用 JVM の
# 用意と *-static パッケージの取り回しが必要だった。公式イメージにはツールチェーンと
# scala-cli が同梱されており、Debian の -dev パッケージは静的アーカイブ(.a)も含むため
# それらがまるごと不要になる。タグは再現性のためバージョン固定する。
FROM --platform=linux/amd64 virtuslab/scala-cli:1.16.0 AS build-image

# イメージには Debian(stable-slim) + build-essential + clang + scala-cli が入っている。
# 追加で要るのは以下だけ。
#   curl / ca-certificates: libcurl のソース取得
#   file                  : 静的リンクの検証用 (下部参照)
#   libidn2 / libunistring: libcurl ではなく sttp-model が @link("idn2") で要求する
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl ca-certificates file libidn2-dev libunistring-dev \
    && rm -rf /var/lib/apt/lists/*

# 最小構成の libcurl を静的ビルドする (#28)。
# ディストリの curl は OpenSSL/nghttp2/brotli/zstd/psl/c-ares 込みのため、静的リンク
# するとそれら全ての静的アーカイブが芋づる式に要る。通信相手は Lambda Runtime API
# だけで TLS も名前解決も HTTP/2 も圧縮も不要なので、それらを無効にして自前ビルド
# すれば依存ごと消える。
# --prefix=/usr/local に入れると clang/ld の既定探索パスに載るため、ヘッダ側の
# -I 指定は不要 (ライブラリ側は下の -L/usr/local/lib で明示する)。
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
#  --server=false : Bloop ビルドサーバを使わずインプロセスでビルド
#  --native-linking: リンクオプションは Linux/リンカー依存のため project.scala ではなく
#    ここで指定し、macOS/Windows でのローカル開発を壊さないようにする。
#    Scala Native は @link 由来の -l を独自順で並べるため、解決順序に依存しないよう
#    ライブラリ群は 1 つの -Wl, 引数にまとめて原子的に渡す。
#
#  --wrap=dlopen / --defsym=__wrap_dlopen=getenv について:
#    Scala Native ランタイムは起動時のスタック境界検出で
#    dlopen("libpthread.so.0") → dlsym → dlclose と進み、**アンロード済み**の関数
#    ポインタを呼ぶ (nativeThreadTLS.c の get_pthread_getattr_np)。glibc 完全静的
#    リンクではこれが解放済みコードへの分岐になり、起動直後に SIGSEGV する
#    (println だけの最小プログラムでも再現する Scala Native 0.5.12 側の不具合)。
#    そこで dlopen の呼び出しを libc の getenv へ差し替えて常に NULL を返させ、
#    近似スタック境界へのフォールバックに落とす。dlopen は失敗時 NULL、getenv も
#    未定義の名前に対し NULL を返すため戻り値の形が一致し、dlopen の第 2 引数は
#    レジスタ渡しで無視される。
#    このフォールバック経路は、musl の静的 dlopen が常に失敗する Alpine 版で従来から
#    使われていたものと同一であり、実行時の挙動に新規性はない。
RUN scala-cli --power package --native --server=false \
      --native-linking "-static" \
      --native-linking "-Wl,--wrap=dlopen" \
      --native-linking "-Wl,--defsym=__wrap_dlopen=getenv" \
      --native-linking "-L/usr/local/lib" \
      --native-linking "-Wl,--start-group,-lcurl,-lidn2,-lunistring,--end-group" \
      -o bootstrap .
RUN chmod +x bootstrap
# 静的リンクの検証。musl の ldd は静的バイナリに対し非ゼロ終了するのでそれを利用できたが、
# glibc の ldd は挙動が異なるため file で判定する。
RUN file bootstrap | grep -q "statically linked"
# 起動できることの検証。_HANDLER 未設定なので NoSuchElementException で即終了するのが正常。
# リンクが通り静的でもある (= 上の 2 つのチェックは通る) のに起動しない、という上記
# dlopen 由来の状態を検知するため。
RUN ./bootstrap 2>&1 | grep -q "NoSuchElementException: _HANDLER"

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
