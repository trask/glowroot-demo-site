import io.gatling.core.Predef._
import io.gatling.core.session.Expression
import io.gatling.http.Predef._
import io.gatling.jdbc.Predef._
import scala.concurrent.duration._

class HeatClinicSimulation extends Simulation {

  val httpProtocol = http
    .baseURL("http://localhost:8080")
    .acceptHeader("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
    .acceptEncodingHeader("gzip, deflate")
    .acceptLanguageHeader("en-US,en;q=0.5")
    .connectionHeader("keep-alive")

  def scn = scenario("Heat Clinic")
    .exec(http("home").get("/"))
    .pause(50 milliseconds, 150 milliseconds)
    .exec(http("hot sauces").get("/hot-sauces"))
    .pause(50 milliseconds, 150 milliseconds)
    .exec(http("merchandise").get("/merchandise"))
    .pause(50 milliseconds, 150 milliseconds)
    .exec(http("clearance").get("/clearance"))
    .pause(50 milliseconds, 150 milliseconds)
    .exec(http("new to hot sauce").get("/new-to-hot-sauce"))
    .pause(50 milliseconds, 150 milliseconds)
    .exec(http("faq").get("/faq"))
    .pause(50 milliseconds, 150 milliseconds)

  setUp(scn.inject(constantUsersPerSec(1) during(365 days) randomized))
      .protocols(httpProtocol)
}
