package serverless

import io.circe._, io.circe.parser._
import java.net.http.HttpRequest
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpResponse

object Http {
  def get(url: String): HCursor = {
    var request = HttpRequest
      .newBuilder()
      .uri(URI.create(url))
      .GET()
      .build()
    var response = HttpClient
      .newHttpClient()
      .send(request, HttpResponse.BodyHandlers.ofString())

    val doc: Json = parse(response.body()).getOrElse(Json.Null)
    return doc.hcursor
  }
}
