import serverless.Lambda

object Main {
  def main(args: Array[String]): Unit =
    serverless.Lambda
      .Handler(
        "hello",
        (event) => {
          println("さよなら透明だった僕たち")
        }
      )
      .Handler(
        "world",
        (event) => {
          println("でしょうねミスター・サーバーレス")
        }
      )
}
