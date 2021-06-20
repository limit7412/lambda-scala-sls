import serverless.Lambda

import io.circe._
import io.circe.parser._
import io.circe.generic.JsonCodec
import io.circe.syntax._
object Main {
  @JsonCodec case class SampleResponse(msg: String)

  def main(args: Array[String]): Unit =
    serverless.Lambda
      .Handler(
        "hello",
        (event) => {
          serverless.Lambda.Response(
            200,
            SampleResponse("さよなら透明だった僕たち").asJson.noSpaces
          )
        }
      )
      .Handler(
        "world",
        (event) => {
          println(event)
          serverless.Lambda.Response(
            200,
            SampleResponse("でしょうねミスター・サーバーレス").asJson.noSpaces
          )
        }
      )
}
