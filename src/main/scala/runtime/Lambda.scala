package aws

object Lambda {
  def Handler(name: String, callback: String => Unit): Lambda.type = {
    println("大石泉すき")
    callback(name)

    this
  }
}
