scalaVersion := "3.3.3" // A Long Term Support version.

enablePlugins(ScalaNativePlugin)

// set to Debug for compilation details (Info is default)
logLevel := Level.Info

// import to add Scala Native options
import scala.scalanative.build._

libraryDependencies ++= Seq(
  "com.lihaoyi" %%% "upickle" % "3.3.1",
  "com.softwaremill.sttp.client4" %%% "core" % "4.0.0-M14"
)

// defaults set with common options shown
nativeConfig ~= { c =>
  c.withLinkingOptions(
    Seq(
      "-lcurl",
      "-lgssapi_krb5",
      "-lgss",
      "-static"
    )
  ).withLTO(LTO.none) // thin
    .withMode(Mode.debug) // releaseFast
    .withGC(GC.immix) // commix
}
