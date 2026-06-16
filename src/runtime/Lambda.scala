package serverless

import sttp.client4.quick._
import upickle.default._
import scala.annotation.tailrec

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
  // Lambda カスタムランタイムのイベントループ。
  // /next で次の呼び出しを取得 → callback 実行 → /response か /error を通知、を繰り返す。
  // 末尾再帰(@tailrec)とし、長時間稼働(ウォーム)でもスタックが伸びないことを保証する。
  @tailrec
  private def handler[A: Reader](callback: A => Response): Nothing = {
    val response = quickRequest
      .get(
        uri"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/next"
      )
      .send()
    val requestID = response.header("Lambda-Runtime-Aws-Request-Id")

    try {
      val decodeBody = read[A](response.body)
      val result = callback(decodeBody)

      basicRequest
        .post(
          uri"http://${sys.env("AWS_LAMBDA_RUNTIME_API")}/2018-06-01/runtime/invocation/$requestID/response"
        )
        .body(write(result))
        .send()
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
                statusCode = 500,
                body = ErrorMessage("Internal Lambda Error", e.getMessage())
              )
            )
          )
          .send()
      }
    }

    handler[A](callback)
  }
}
