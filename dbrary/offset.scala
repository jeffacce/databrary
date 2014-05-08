package dbrary

import scala.util.control.Exception.catching
import play.api.mvc.{PathBindable,QueryStringBindable,JavascriptLitteral}
import play.api.data.format.Formatter
import play.api.libs.json
import org.postgresql.util.PGInterval
import org.joda.time
import macros._

/* A length of time.
 * Called "interval" in postgres and Duration in joda, offset is a better name for our purposes. */
final case class Offset(millis : Long) extends scala.math.Ordered[Offset] {
  // def nanos = 1000000L*seconds
  def seconds : Double = millis/1000.0
  def samples(rate : Double) = math.round(rate*seconds)
  def +(other : Offset) = Offset(millis + other.millis)
  def -(other : Offset) = Offset(millis - other.millis)
  def unary_- = Offset(-millis)
  def compare(other : Offset) : Int = millis.compare(other.millis)
  def min(other : Offset) = Offset(millis.min(other.millis))
  def max(other : Offset) = Offset(millis.max(other.millis))
  def duration : time.Duration = new time.Duration(millis)
  def abs = Offset(millis.abs)

  /* This is unfortunate but I can't find any other reasonable formatting options without the postgres server or converting to a joda Period */
  override def toString = {
    val ms = millis.abs
    val m = ms / 60000
    (if (millis.signum < 0) "-" else "") +
    (if (m < 60) m.formatted("%02d:")
     else "%02d:%02d:".format(m / 60, m % 60)) +
    ((ms % 60000)/1000.0).formatted("%06.3f")
  }
}

object Offset {
  final val ZERO = new Offset(0)
  // def apply(d : BigDecimal) : Offset = new Offset((1000L*d).toLong)
  def apply(i : PGInterval) : Offset =
    ofSeconds(60*(60*(24*(30*(12.175*i.getYears + i.getMonths) + i.getDays) + i.getHours) + i.getMinutes) + i.getSeconds)
  def apply(d : time.Duration) : Offset = new Offset(d.getMillis)
  def ofSeconds(seconds : Double) : Offset = new Offset((1000.0*seconds).toLong)

  private val multipliers : Seq[Double] = Seq(60,60,24).scanLeft(1.0)(_ * _)
  def fromString(s : String) : Offset =
    ofSeconds(s.stripPrefix("-").split(':').reverseIterator.zipAll(multipliers.iterator, "", 0.0).map {
      case (_, 0) => throw new java.lang.NumberFormatException("For offset string: " + s)
      case ("", _) => 0.0
      case (s, m) => m*s.toDouble
    }.sum * (if (s.startsWith("-")) -1.0 else 1.0))

  implicit val sqlType : SQLType[Offset] =
    SQLType.interval.transform[Offset]("interval", classOf[Offset])(
      p => catching(classOf[UnsupportedOperationException])
        .opt(new Offset(p.toStandardDuration.getMillis)),
      o => new time.Period(o.millis)
    )

  implicit val pathBindable : PathBindable[Offset] = PathBindable.bindableLong.transform(new Offset(_), _.millis)
  implicit val queryStringBindable : QueryStringBindable[Offset] = new QueryStringBindable[Offset] {
    def bind(key : String, params : Map[String, Seq[String]]) : Option[Either[String, Offset]] =
      params.get(key).flatMap(_.headOption).map { s =>
        Maybe.toLong(s).map(new Offset(_))
          .orElse(Maybe.toNumber(fromString(s)))
          .toRight("invalid offset parameter value for " + key)
      }
    def unbind(key : String, offset : Offset) : String =
      QueryStringBindable.bindableLong.unbind(key, offset.millis)
  }
  implicit val javascriptLitteral : JavascriptLitteral[Offset] = new JavascriptLitteral[Offset] {
    def to(value : Offset) = value.millis.toString
  }

  implicit val formatter : Formatter[Offset] = new Formatter[Offset] {
    override val format = Some(("format.offset", Nil))
    def bind(key: String, data: Map[String, String]) =
      data.get(key).flatMap(s => Maybe.toNumber(fromString(s)))
        .toRight(Seq(play.api.data.FormError(key, "error.offset", Nil)))
    def unbind(key: String, value: Offset) = Map(key -> value.toString)
  }

  implicit val jsonFormat : json.Format[Offset] = new json.Format[Offset] {
    def writes(o : Offset) = json.JsNumber(o.millis)
    def reads(j : json.JsValue) = j match {
      case json.JsNumber(s) => json.JsSuccess(new Offset(s.toLong))
      case _ => json.JsError("error.expected.jsnumber")
    }
  }
}

