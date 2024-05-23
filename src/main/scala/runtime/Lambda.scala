package serverless

import sttp.client4.quick.*
import sttp.client4.curl.*
import upickle.default.*

object Lambda {
  case class APIGatewayRequest(
      resource: String,
      path: String,
      httpMethod: String,
      headers: Map[String, String],
      body: String
  ) derives ReadWriter

  case class Response(statusCode: Int = 0, body: String) derives ReadWriter
  case class ErrorResponse(statusCode: Int = 0, body: ErrorMessage)
      derives ReadWriter
  case class ErrorMessage(msg: String, error: String) derives ReadWriter

  def Handler[A: Reader](name: String, callback: A => Response): Lambda.type = {
    if (name == sys.env("_HANDLER")) {
      handler(callback)
    }

    this
  }
  private def handler[A: Reader](callback: A => Response): Lambda.type = {
    val backend = CurlBackend()
    var response = quickRequest
      .get(
        uri"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/next"
      )
      .send(backend)
    val requestID = response.header("Lambda-Runtime-Aws-Request-Id")

    try {
      val decodeBody = read[A](response.body)
      val result = callback(decodeBody)

      basicRequest
        .post(
          uri"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/$requestID/response"
        )
        .body(write(result))
        .send(backend)
    } catch {
      case e: Exception => {
        e.printStackTrace()
        basicRequest
          .post(
            uri"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/$requestID/error"
          )
          .body(
            write(
              ErrorResponse(
                500,
                ErrorMessage("Internal Lambda Error", e.getMessage())
              )
            )
          )
          .send(backend)
      }
    }

    handler[A](callback)
    this
  }
}
