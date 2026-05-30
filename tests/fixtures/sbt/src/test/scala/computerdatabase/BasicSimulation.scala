package computerdatabase

import io.gatling.core.Predef._
import io.gatling.http.Predef._

import scala.concurrent.duration._

class BasicSimulation extends Simulation {

  val httpProtocol = http
    .baseUrl("https://computer-database.gatling.io")
    .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")

  val scn = scenario("BasicSimulation")
    .exec(
      http("home")
        .get("/")
        .check(status.is(200))
    )

  setUp(
    scn.inject(atOnceUsers(1))
  ).protocols(httpProtocol)
    .maxDuration(30.seconds)
}
