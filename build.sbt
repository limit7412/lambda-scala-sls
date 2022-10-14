scalaVersion := "2.13.10"
name := "bootstrap"

val circeVersion = "0.14.3"
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
