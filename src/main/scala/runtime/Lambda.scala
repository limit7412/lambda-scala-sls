package serverless

import io.circe._
import io.circe.parser._
import io.circe.generic.JsonCodec
import io.circe.syntax._
import cats.instances.string
import cats.instances.boolean

object Lambda {
  @JsonCodec case class Request(
      resource: String,
      path: String,
      httpMethod: String,
      headers: Map[String, String],
      body: Option[String]
  )
  @JsonCodec case class Response(statusCode: Int, body: String)
  @JsonCodec case class ErrorResponse(msg: String, error: String)

  def Handler(name: String, callback: Request => Response): Lambda.type = {
    if (name == sys.env("_HANDLER")) {
      handler(callback)
    }

    this
  }
  private def handler(callback: Request => Response): Lambda.type = {
    var response =
      Http.Get(
        s"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/next"
      )
    val requestID =
      response.headers().firstValue("Lambda-Runtime-Aws-Request-Id").get()

    decode[Request](response.body()) match {
      case Right(event: Request) => {
        try {
          val result = callback(event)
          Http.Post(
            s"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/$requestID/response",
            result.asJson.noSpaces
          )
        } catch {
          case e: Exception => {
            e.printStackTrace()
            Http.Post(
              s"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/$requestID/error",
              Response(
                500,
                ErrorResponse(
                  "Internal Lambda Error",
                  e.getMessage()
                ).asJson.noSpaces
              ).asJson.noSpaces
            )
          }
        }
      }
      case Left(_) => throw new Exception("failed to decode request event")
    }

    handler(callback)
    this
  }
}
