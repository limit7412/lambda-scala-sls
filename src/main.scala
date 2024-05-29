import upickle.default._

import serverless.Lambda

case class SampleRequest(msg: String, test: Int) derives ReadWriter
case class HelloResponse(msg: String) derives ReadWriter
case class WorldResponse(msg: String, body: String) derives ReadWriter

@main def main = serverless.Lambda
  .Handler[serverless.Lambda.APIGatewayRequest](
    "hello",
    (event) =>
      serverless.Lambda
        .Response(
          200,
          write(HelloResponse("さよなら透明だった僕たち"))
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
            WorldResponse(
              msg = "でしょうねミスター・サーバーレス",
              body = write(body)
            )
          )
        )
    }
  )
