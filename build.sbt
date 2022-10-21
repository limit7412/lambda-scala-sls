scalaVersion := "2.13.8"
name := "bootstrap"

val circeVersion = "0.14.1"
libraryDependencies ++= Seq(
  "io.circe" %% "circe-core",
  "io.circe" %% "circe-generic",
  "io.circe" %% "circe-parser"
).map(_ % circeVersion)

addCompilerPlugin(
  "org.scalamacros" % "paradise" % "2.1.1" cross CrossVersion.full
)

enablePlugins(NativeImagePlugin)
nativeImageOptions ++= List(
  "--static",
  "--enable-https"
)
