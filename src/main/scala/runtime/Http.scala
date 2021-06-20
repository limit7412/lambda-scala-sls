package serverless

import java.net.http.HttpRequest
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpResponse

object Http {
  def Get(url: String): HttpResponse[String] = {
    var request = HttpRequest
      .newBuilder()
      .uri(URI.create(url))
      .GET()
      .build()
    var response = HttpClient
      .newHttpClient()
      .send(request, HttpResponse.BodyHandlers.ofString())

    return response
  }
  def Post(url: String, body: String): HttpResponse[String] = {
    var request = HttpRequest
      .newBuilder()
      .uri(URI.create(url))
      .POST(HttpRequest.BodyPublishers.ofString(body))
      .build()
    var response = HttpClient
      .newHttpClient()
      .send(request, HttpResponse.BodyHandlers.ofString())

    return response
  }
}
