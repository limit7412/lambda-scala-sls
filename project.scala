//> using platform native
//> using toolkit default
//> using dep "com.lihaoyi::upickle:4.4.2"

// 静的リンクのオプションは project.scala には置かない (#22)。
// -static や -Wl,--start-group 等は Linux/リンカー依存で、macOS/Windows での
// ローカル開発(scala-cli run/test)を壊すため、コンテナビルド時の scala-cli
// コマンドに --native-linking フラグとして渡す (Dockerfile 参照)。
