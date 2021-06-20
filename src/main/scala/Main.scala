import serverless.Lambda

import io.circe._
import io.circe.parser._
import io.circe.generic.JsonCodec
import io.circe.syntax._
object Main {
  @JsonCodec case class SampleRequest(msg: String, test: Int)
  @JsonCodec case class SampleResponse(msg: String)

  def main(args: Array[String]): Unit =
    serverless.Lambda
      .Handler(
        "hello",
        (event) =>
          serverless.Lambda
            .Response(
              200,
              SampleResponse("さよなら透明だった僕たち").asJson.noSpaces
            )
            .asJson
            .noSpaces
      )
      .Handler(
        "world",
        (event) =>
          decode[serverless.Lambda.APIGatewayRequest](event) match {
            case Right(decodeEvent) =>
              decode[SampleRequest](decodeEvent.body) match {
                case Right(body) =>
                  serverless.Lambda
                    .Response(
                      200,
                      SampleResponse(
                        s"でしょうねミスター・サーバーレス ${body.asJson.noSpaces}"
                      ).asJson.noSpaces
                    )
                    .asJson
                    .noSpaces
                case Left(_) =>
                  throw new Exception("failed to decode request body")
              }
            case Left(_) =>
              throw new Exception("failed to decode lambda event")
          }
      )
}
