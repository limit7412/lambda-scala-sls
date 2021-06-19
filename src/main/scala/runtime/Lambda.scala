package serverless

import java.net.http.HttpRequest
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpResponse

object Lambda {
  def Handler(name: String, callback: String => Unit): Lambda.type = {
    // if (name != sys.env("_HANDLER")) {
    //   return this
    // }

    var request = HttpRequest
      .newBuilder()
      .uri(URI.create("https://api.coindesk.com/v1/bpi/currentprice.json"))
      .GET()
      .build();
    var response = HttpClient
      .newHttpClient()
      .send(request, HttpResponse.BodyHandlers.ofInputStream());
    println(response.body().toString())

    // while (true) {
    callback(name)
    // }

    this
  }
}
