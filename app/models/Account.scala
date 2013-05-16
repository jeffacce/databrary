package models

import play.api.Play.current
import play.api.db.slick
import             slick.DB
import             slick.Config.driver.simple._
import java.sql.Timestamp

abstract class Identity(val id : Int) {
  override def hashCode = id
  def equals(o : Identity) = o.id == id
  val account : Option[Account]

  private[models] val _entity = CachedVal[Entity](Entity.get(id))
  def entity : Entity = _entity
  def access : Permission.Value = entity.access
}

object NoAccount extends Identity(Entity.NOBODY) {
  val account = None
}

case class Account(override val id : Int, username : String, var email : String, var openid : Option[String]) 
  extends Identity(id) with TableRow {
  val account = Some(this)

  def commit = DB.withSession { implicit session =>
    Account.byId(id).map(_.update_*) update (email, openid)
  }
  def add = DB.withSession { implicit session =>
    Account.* insert this
  }
}

object Account extends Table[Account]("account") {
  def id = column[Int]("entity")
  def username = column[String]("username", O.PrimaryKey, O.DBType("varchar(32)"))
  def created = column[Timestamp]("created")
  def email = column[String]("email", O.DBType("varchar(256)"))
  def openid = column[Option[String]]("openid", O.DBType("varchar(256)"))

  def * = id ~ username ~ email ~ openid <> (Account.apply _, Account.unapply _)
  private def update_* = email ~ openid

  def idKey = index("account_entity_key", id, unique = true)
  def openidKey = index("account_openid_key", openid, unique = false)
  def entity = foreignKey("account_entity_fkey", id, Entity)(_.id)

  private def byId(i : Int) = Query(this).where(_.id === i)
  private[this] def byUsername(u : String) = Query(this).filter(_.username === u)
  private[this] def byOpenid(o : String) = Query(this).filter(_.openid === o)

  private[this] def firstOption(q : Query[Account.type, Account]) : Option[Account] =
    DB.withSession { implicit session =>
      (for { a <- q ; (e, c) <- a.entity.map(e => (e, Authorize._access_check(e.id))) } yield (a,e,c)).firstOption.map(
        { case (a,e,c) => 
          a._entity() = Entity.cache(e, c.getOrElse(Permission.NONE))
          a 
        }
      )
    }

  def getId(i : Int) : Option[Account] =
    firstOption(byId(i))
  def getUsername(u : String) : Option[Account] =
    firstOption(byUsername(u))
  def getOpenid(o : String, u : Option[String] = None) : Option[Account] = DB.withSession { implicit sesssion =>
    val qao = byOpenid(o)
    u.fold(qao)(u => qao.filter(_.username === u)).firstOption
  }
}
