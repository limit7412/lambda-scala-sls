# Lambda の zip (provided.al2023 カスタムランタイム) に入れる bootstrap を
# 完全静的リンクでビルドする専用イメージ。デプロイするのは抽出したバイナリだけで、
# このイメージ自体はデプロイしない。背景は README とその参照先 (#22, #28) を参照。
# ベースの scala-cli 公式イメージは amd64 のみの提供のため、x86_64 が前提となる。
# タグは再現性のためバージョン固定する。
FROM --platform=linux/amd64 virtuslab/scala-cli:1.16.0 AS build-image

# ベースイメージ (Debian + ツールチェーン + scala-cli) に足りないものだけ追加する。
#   curl / ca-certificates : libcurl のソース取得用
#   file                   : 静的リンクの検証用 (最下部参照)
#   libidn2 / libunistring : sttp-model が @link("idn2") で要求する
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl ca-certificates file libidn2-dev libunistring-dev \
    && rm -rf /var/lib/apt/lists/*

# 最小構成の libcurl を静的ビルドする。通信相手は Lambda Runtime API だけなので
# TLS も名前解決も HTTP/2 も圧縮も使わず、これらを切ればディストリビューション版の
# 静的リンクで芋づる式に必要になる OpenSSL などの静的アーカイブごと不要になる。
# /usr/local は clang/ld の既定の探索パスなので、ヘッダ側の -I 指定は不要になる。
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
#  --server=false : Bloop ビルドサーバを使わず、インプロセスでビルドする。
#  --native-linking : リンカー依存のオプションのため、project.scala ではなく
#    ここで渡す (project.scala 冒頭のコメント参照)。ライブラリ群は Scala Native に
#    よる並べ替えの影響を受けないよう、1 つの --start-group にまとめて渡す。
#  --wrap=dlopen : glibc の完全静的リンクでは、Scala Native 0.5.12 が起動時の
#    スタック境界検出で行う dlopen が解放済みコードの呼び出しになり、SIGSEGV する。
#    そこで dlopen を getenv に差し替えて常に NULL を返させ (未知の名前への getenv は
#    NULL を返し、呼び出しの形も互換)、近似スタック境界へのフォールバックに落とす。
#    これは musl の静的リンク (dlopen が常に失敗する) で従来から通っていた経路と同じ。
RUN scala-cli --power package --native --server=false \
      --native-linking "-static" \
      --native-linking "-Wl,--wrap=dlopen" \
      --native-linking "-Wl,--defsym=__wrap_dlopen=getenv" \
      --native-linking "-L/usr/local/lib" \
      --native-linking "-Wl,--start-group,-lcurl,-lidn2,-lunistring,--end-group" \
      -o bootstrap .
RUN chmod +x bootstrap
# 静的リンクの検証 (glibc の ldd は musl と違い静的バイナリの判定に使えないため file で)
RUN file bootstrap | grep -q "statically linked"
# 起動できることの検証。前述の dlopen 問題はリンクが通っても起動時に落ちるため、
# 実際に実行して確かめる。_HANDLER 未設定による NoSuchElementException 即終了が正常。
RUN ./bootstrap 2>&1 | grep -q "NoSuchElementException: _HANDLER"
