package serverless
object Lambda {
  def Handler(name: String, callback: String => Unit): Lambda.type = {
    // if (name != sys.env("_HANDLER")) {
    //   return this
    // }

    var response = Http.get("https://api.coindesk.com/v1/bpi/currentprice.json")
    response.downField("time").downField("updated").as[String] match {
      case Right(test: String) => println(test)
      case Left(_)             =>
    }

    // while (true) {
    callback(name)
    // }

    this
  }
}
