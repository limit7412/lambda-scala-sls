// for GraalVM
// //> using packaging.graalvmArgs --static
// //> using packaging.graalvmArgs --no-fallback
// for Scala Native
//> using platform native
//> using toolkit default
//> using dep "com.lihaoyi::upickle:4.4.2"

// 静的(musl)リンク化 (#22)
// Lambda ランタイム(provided.al2023)の glibc/libcurl のバージョンに依存しない
// 自己完結バイナリを生成する。Alpine(musl) 上でビルドし、libcurl と推移的依存
// (OpenSSL/zlib/nghttp2/brotli/zstd/idn2 等)を静的アーカイブから取り込む。
//
// Scala Native は @link("curl") により -lcurl のみを付与するため、libcurl の
// 推移的依存は明示的に並べる必要がある。静的リンク時の解決順序問題を避けるため
// --start-group / --end-group で囲む。
//> using nativeLinkingOptions "-static"
//> using nativeLinkingOptions "-Wl,--start-group" "-lcurl" "-lnghttp2" "-lssl" "-lcrypto" "-lz" "-lbrotlienc" "-lbrotlidec" "-lbrotlicommon" "-lzstd" "-lidn2" "-lunistring" "-lpsl" "-lcares" "-Wl,--end-group"
