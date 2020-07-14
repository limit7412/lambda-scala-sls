import aws.Lambda

object Main {
  def main(args: Array[String]): Unit =
    Lambda
      .Handler(
        "たべるんご",
        (event: String) => {
          println(event)
        }
      )
      .Handler(
        "こいつはりんごろう",
        (event: String) => {
          println(event)
        }
      )
}
