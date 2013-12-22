package controllers

import scala.concurrent.Future
import play.api._
import          Play.current
import          mvc._
import          data._
import               Forms._
import          i18n.Messages
import play.api.libs.concurrent.Execution.Implicits.defaultContext
import org.mindrot.jbcrypt.BCrypt
import macros._
import dbrary._
import site._
import models._

private[controllers] sealed abstract class PartyController extends ObjectController[SiteParty] {
  /** ActionBuilder for party-targeted actions.
    * @param i target party id, defaulting to current user (site.identity)
    * @param p permission needed, or None if delegation is not allowed (must be self)
    */
  private[controllers] def action(i : Option[models.Party.Id], p : Option[Permission.Value] = Some(Permission.ADMIN)) =
    optionZip(i, p).fold[ActionFunction[SiteRequest.Auth,Request]] {
      new ActionRefiner[SiteRequest.Auth,Request] {
        protected def refine[A](request : SiteRequest.Auth[A]) =
          if (i.fold(true)(_ === request.identity.id))
            request.identity.perSite(request).map { p =>
              Right(request.withObj(p))
            }
          else
            macros.Async(Left(Forbidden))
      }
    } { case (i, p) =>
      RequestObject.check[SiteParty](models.SiteParty.get(i)(_), p)
    }

  private[controllers] def Action(i : Option[models.Party.Id], p : Option[Permission.Value] = Some(Permission.ADMIN)) =
    SiteAction.auth ~> action(i, p)

  protected val passwordInputMapping : Mapping[Option[String]]
  type PasswordMapping = Mapping[Option[String]]
  def passwordMapping : PasswordMapping = 
    passwordInputMapping
    .transform[Option[String]](
      _.map(BCrypt.hashpw(_, BCrypt.gensalt)),
      _.map(_ => "")
    )

  protected def AdminAction(i : models.Party.Id, delegate : Boolean = true) =
    Action(Some(i), if (delegate) Some(Permission.ADMIN) else None)

  protected def adminAccount(implicit request : Request[_]) : Option[Account] =
    request.obj.party.account.filter(_ === request.identity || request.superuser)

  type EditMapping = (Option[String], Option[Option[Orcid]], Option[(String, Option[String], Option[String], Option[String])])
  type EditForm = Form[EditMapping]
  protected def formFill(implicit request : Request[_]) : EditForm = {
    val e = request.obj.party
    val acct = adminAccount
    Form(tuple(
      "name" -> OptionMapping(nonEmptyText),
      "orcid" -> OptionMapping(text(0,20).transform[Option[Orcid]](Maybe(_).opt.map(Orcid.apply _), _.fold("")(_.toString)))
        .verifying(Messages("orcid.invalid"), _.flatten.fold(true)(_.valid)),
      "" -> MaybeMapping(acct.map(_ => tuple(
        "auth" -> text,
        "email" -> OptionMapping(email),
        "password" -> passwordMapping,
        "openid" -> OptionMapping(text(0,256))
      )))
    )).fill((Some(e.name), Some(e.orcid), acct.map(a => ("", Some(a.email), None, a.openid))))
  }

  def formForAccount(form : EditForm)(implicit request : Request[_]) =
    form.value.fold[Option[Any]](adminAccount)(_._3).isDefined

  def update(i : models.Party.Id) = AdminAction(i).async { implicit request =>
    def bad(form : EditForm) =
      ABadForm[EditMapping](views.html.party.edit(_), form)
    val form = formFill.bindFromRequest
    val party = request.obj.party
    val acct = adminAccount
    form.fold(bad _, {
      case (_, _, Some((cur, _, _, _))) if !acct.fold(false)(a => BCrypt.checkpw(cur, a.password)) =>
        bad(form.withError("cur_password", "password.incorrect"))
      case (name, orcid, accts) =>
        for {
          _ <- party.change(name = name, orcid = orcid)
          _ <- macros.Async.map[(String, Option[String], Option[String], Option[String]), Boolean](accts, { case (_, email, password, openid) =>
            val a = acct.get
            a.change(
              email = email,
              password = password,
              openid = openid.map(Maybe(_).opt)
            )
          })
        } yield (result(request.obj))
    })
  }

  type AuthorizeForm = Form[(Permission.Value, Permission.Value, Boolean, Option[Date])]
  protected val authorizeForm : AuthorizeForm = Form(
    tuple(
      "access" -> Field.enum(Permission),
      "delegate" -> Field.enum(Permission),
      "pending" -> boolean,
      "expires" -> optional(jodaLocalDate)
    )
  )

  protected def authorizeFormFill(auth : Authorize, apply : Boolean = false) : AuthorizeForm =
    authorizeForm.fill((auth.access, auth.delegate, auth.authorized.isEmpty, auth.expires.map(_.toLocalDate)))

  protected val authorizeSearchForm = Form(
    "name" -> nonEmptyText
  )
}

private[controllers] object PartyController extends PartyController {
  protected val passwordInputMapping = optional(text(7))
}

object PartyHtml extends PartyController {
  protected val passwordInputMapping =
    tuple(
      "once" -> optional(text(7)),
      "again" -> text
    ).verifying(Messages("password.again"), pa => pa._1.fold(true)(_ == pa._2))
    .transform[Option[String]](_._1, p => (p, p.getOrElse("")))

  def view(i : models.Party.Id) = Action(Some(i), Some(Permission.NONE)).async { implicit request =>
    val party = request.obj.party
    for {
      parents <- party.authorizeParents()
      children <- party.authorizeChildren()
      vols <- party.volumeAccess
      fund <- party.funding
      comments <- party.account.fold[Future[Seq[Comment]]](macros.Async(Nil))(_.comments)
    } yield (Ok(views.html.party.view(parents, children, vols, fund, comments)))
  }

  private[this] def viewAdmin(
    status : Status,
    authorizeChangeForm : Option[(models.Party,AuthorizeForm)] = None,
    authorizeWhich : Option[Boolean] = None,
    authorizeSearchForm : Form[String] = authorizeSearchForm,
    authorizeResults : Seq[(models.Party,AuthorizeForm)] = Seq())(
    implicit request : Request[_]) = {
    val authorizeChange = authorizeChangeForm.map(_._1.id)
    request.obj.party.authorizeChildren(true).flatMap { children =>
    request.obj.party.authorizeParents(true).map { parents =>
      val authorizeForms = children
        .filter(t => authorizeChange.fold(true)(_ === t.childId))
        .map(t => (t.child, authorizeFormFill(t))) ++
        authorizeChangeForm
      status(views.html.party.authorize(parents, authorizeForms, authorizeWhich, authorizeSearchForm, authorizeResults))
    }}
  }
  
  def edit(i : models.Party.Id) = AdminAction(i) { implicit request =>
    Ok(views.html.party.edit(formFill))
  }

  def admin(i : models.Party.Id) = AdminAction(i).async { implicit request =>
    viewAdmin(Ok)
  }

  private final val maxExpiration = org.joda.time.Years.years(1)

  def authorizeChange(id : models.Party.Id, childId : models.Party.Id) = AdminAction(id).async { implicit request =>
    models.Party.get(childId).flatMap(_.fold(ANotFound) { child =>
    val form = authorizeForm.bindFromRequest
    form.fold(
      form => viewAdmin(BadRequest, authorizeChangeForm = Some((child, form))),
      { case (access, delegate, pending, expires) =>
        val (exp, expok) = if (request.superuser) (expires, true)
          else {
            val maxexp = (new Date).plus(maxExpiration)
            val exp = expires.getOrElse(maxexp)
            (Some(exp), exp.isAfter(maxexp))
          }
        if (!expok)
          viewAdmin(BadRequest, authorizeChangeForm = Some((child, form.withError("expires", "error.max", maxExpiration))))
        else
          Authorize.set(childId, id, access, delegate, if (pending) None else Some(new Timestamp), exp.map(_.toDateTimeAtStartOfDay)).map { _ =>
            Redirect(routes.PartyHtml.admin(id))
          }
      }
    )
    })
  }

  def authorizeDelete(id : models.Party.Id, child : models.Party.Id) = AdminAction(id).async { implicit request =>
    models.Authorize.delete(child, id).map { _ =>
      Redirect(routes.PartyHtml.admin(id))
    }
  }

  def authorizeSearch(id : models.Party.Id, apply : Boolean) = AdminAction(id).async { implicit request =>
    val form = authorizeSearchForm.bindFromRequest
    form.fold(
      form => viewAdmin(BadRequest, authorizeWhich = Some(apply), authorizeSearchForm = form),
      name =>
        models.Party.searchForAuthorize(name, request.obj.party).flatMap { res =>
        viewAdmin(Ok, authorizeWhich = Some(apply), authorizeSearchForm = form, 
          authorizeResults = res.map(e => (e, authorizeForm.fill(
            if (apply) (Permission.NONE, Permission.NONE, true, None)
            else (Permission.NONE, Permission.NONE, false, Some((new Date).plus(maxExpiration)))))))
        }
    )
  }

  def authorizeApply(id : models.Party.Id, parentId : models.Party.Id) = AdminAction(id).async { implicit request =>
    models.Party.get(parentId).flatMap(_.fold(ANotFound) { parent =>
    authorizeForm.bindFromRequest.fold(
      form => viewAdmin(BadRequest, authorizeWhich = Some(true), authorizeResults = Seq((parent, form))),
      { case (access, delegate, _, expires) =>
        Authorize.set(id, parentId, access, delegate, None, expires.map(_.toDateTimeAtStartOfDay)).map { _ =>
          Redirect(routes.PartyHtml.admin(id))
        }
      }
    )})
  }
}

object PartyApi extends PartyController {
  protected val passwordInputMapping = OptionMapping(text(7))

  def get(partyId : models.Party.Id) = Action(Some(partyId), Some(Permission.NONE)).async { implicit request =>
    request.obj.json(request.apiOptions).map(Ok(_))
  }
}
