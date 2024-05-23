import serverless.Lambda

import upickle.default.*
object Main {
  case class SampleRequest(msg: String, test: Int) derives ReadWriter
  case class SampleResponse(msg: String) derives ReadWriter

  def main(args: Array[String]): Unit =
    serverless.Lambda
      .Handler[serverless.Lambda.APIGatewayRequest](
        "hello",
        (event) =>
          serverless.Lambda
            .Response(
              200,
              write(SampleResponse("さよなら透明だった僕たち"))
            )
      )
      .Handler[serverless.Lambda.APIGatewayRequest](
        "world",
        (event) => {
          val body = read[SampleRequest](event.body)

          serverless.Lambda
            .Response(
              200,
              write(
                SampleResponse(
                  s"でしょうねミスター・サーバーレス ${write(body)}"
                )
              )
            )
        }
      )
}
