//> using platform native
//> using toolkit default
//> using dep "com.lihaoyi::upickle:4.4.2"

// 静的リンクのオプションはこのファイルには置かない (#22)。
// -static や -Wl,--start-group といったオプションは Linux のリンカーに依存していて、
// ここに書くと macOS/Windows でのローカル開発 (scala-cli run/test) が壊れる。
// そのため、コンテナビルド時の scala-cli コマンドに --native-linking フラグとして
// 渡す形にしている (Dockerfile 参照)。
