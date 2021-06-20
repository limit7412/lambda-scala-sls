import serverless.Lambda

object Main {
  def main(args: Array[String]): Unit =
    serverless.Lambda
      .Handler(
        "hello",
        (event) => {
          println("財布ないわ")
          serverless.Lambda.Response(
            200,
            "さよなら透明だった僕たち"
          )
        }
      )
      .Handler(
        "world",
        (event) => {
          println(event)
          serverless.Lambda.Response(
            200,
            "でしょうねミスター・サーバーレス"
          )
        }
      )
}
