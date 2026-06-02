// for GraalVM
// //> using packaging.graalvmArgs --static
// //> using packaging.graalvmArgs --no-fallback
// for Scala Native
//> using platform native
//> using toolkit default
//> using dep "com.lihaoyi::upickle:4.4.2"

// 静的(musl)リンクのオプションは project.scala には置かない (#22)。
// -static や -Wl,--start-group 等は Linux/リンカー依存で、macOS/Windows での
// ローカル開発(scala-cli run/test)を壊すため、Alpine ビルド時の scala-cli
// コマンドに --native-linking フラグとして渡す (Dockerfile 参照)。
