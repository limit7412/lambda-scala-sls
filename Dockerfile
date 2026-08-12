# ビルド専用イメージ: Scala Native 製バイナリ bootstrap を scala-cli 公式イメージ
# (Debian/glibc) 上で完全静的リンクする (#28)。
# このイメージ自体をデプロイするのではなく、生成した bootstrap を抽出して
# Lambda の zip (provided.al2023 カスタムランタイム) としてデプロイする。
#
# 公式イメージは amd64 のみの提供のため、x86_64 が前提となる (#21 の arm64 化を巻き戻す)。
# 以前は Alpine (musl) 上でビルドしていたが、その構成では JDK / gcompat / musl 用 JVM
# の用意と *-static パッケージの取り回しが必要だった。公式イメージにはツールチェーンと
# scala-cli が同梱されており、Debian の -dev パッケージは静的アーカイブ (.a) も含むため、
# それらの手当てがまるごと不要になる。タグは再現性のためバージョン固定する。
FROM --platform=linux/amd64 virtuslab/scala-cli:1.16.0 AS build-image

# イメージには Debian (stable-slim) + build-essential + clang + scala-cli が入っている。
# 追加で必要なのは以下だけ。
#   curl / ca-certificates : libcurl のソース取得用
#   file                   : 静的リンクの検証用 (最下部参照)
#   libidn2 / libunistring : libcurl ではなく sttp-model が @link("idn2") で要求する
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl ca-certificates file libidn2-dev libunistring-dev \
    && rm -rf /var/lib/apt/lists/*

# 最小構成の libcurl を静的ビルドする (#28)。
# ディストリビューションの curl は OpenSSL/nghttp2/brotli/zstd/psl/c-ares 込みのため、
# 静的リンクするとそれら全ての静的アーカイブが芋づる式に必要になる。このランタイムの
# 通信相手は Lambda Runtime API だけで、TLS も名前解決も HTTP/2 も圧縮も使わない。
# そこでそれらを無効にして自前ビルドし、依存ごと消す。
# --prefix=/usr/local に入れると clang/ld の既定の探索パスに載るため、ヘッダ側の
# -I 指定は不要になる (ライブラリ側は下の -L/usr/local/lib で明示する)。
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
#  --native-linking : リンクオプションは Linux のリンカーに依存するため、project.scala
#    ではなくここで指定し、macOS/Windows でのローカル開発を壊さないようにする。
#    Scala Native は @link 由来の -l を独自の順序で並べるため、解決順序に依存しない
#    よう、ライブラリ群は 1 つの -Wl 引数にまとめて原子的に渡す。
#
#  --wrap=dlopen / --defsym=__wrap_dlopen=getenv について:
#    Scala Native ランタイムは起動時のスタック境界検出で dlopen("libpthread.so.0")、
#    dlsym、dlclose と進んだあと、アンロード済みの関数ポインタを呼んでしまう
#    (nativeThreadTLS.c の get_pthread_getattr_np)。glibc の完全静的リンクでは
#    これが解放済みコードへの分岐になり、起動直後に SIGSEGV する (println だけの
#    最小プログラムでも再現する、Scala Native 0.5.12 側の不具合)。
#    そこで dlopen の呼び出しを libc の getenv に差し替えて常に NULL を返させ、
#    近似スタック境界へのフォールバックに落とす。この差し替えが成立するのは、
#    dlopen が失敗時に NULL を返し、getenv も未定義の名前に対して NULL を返すため
#    戻り値の形が一致し、dlopen の第 2 引数はレジスタ渡しで単に無視されるからである。
#    このフォールバック経路は、静的リンクでは dlopen が常に失敗する musl (旧 Alpine 版)
#    で従来から通っていた経路と同じであり、実行時の挙動として新しいものではない。
RUN scala-cli --power package --native --server=false \
      --native-linking "-static" \
      --native-linking "-Wl,--wrap=dlopen" \
      --native-linking "-Wl,--defsym=__wrap_dlopen=getenv" \
      --native-linking "-L/usr/local/lib" \
      --native-linking "-Wl,--start-group,-lcurl,-lidn2,-lunistring,--end-group" \
      -o bootstrap .
RUN chmod +x bootstrap
# 静的リンクの検証。musl の ldd は静的バイナリに対して非ゼロ終了するのでそれで判定
# できたが、glibc の ldd は挙動が異なるため file の出力で判定する。
RUN file bootstrap | grep -q "statically linked"
# 起動できることの検証。リンクが通り静的にもなっている (= 上の 2 つのチェックは通る)
# のに起動はしない、という前述の dlopen 由来の壊れ方を検知するため。
# _HANDLER 未設定なので、NoSuchElementException で即終了するのが正常。
RUN ./bootstrap 2>&1 | grep -q "NoSuchElementException: _HANDLER"
