import account.{account_message_handler}
import gleam/erlang/process.{type Subject}
import gleam/http.{Delete, Get, Post}
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import types.{type EngineMessage, Account, Join, Start}
import wisp.{type Request, type Response}

const cookie_name = "id"

pub fn home_page(req: Request, engine: Subject(EngineMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      [
        "<h1>Hello, " <> wisp.escape_html(name) <> "!</h1>",
        "<form action='/session?_method=DELETE' method='post'>",
        "  <button type='submit'>Log out</button>",
        "</form>",
      ]
      |> string.concat
      |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn session(req: Request, engine: Subject(EngineMessage)) -> Response {
  case req.method {
    Get -> new_session()
    Post -> create_session(req, engine)
    Delete -> destroy_session(req)
    _ -> wisp.method_not_allowed([Get, Post, Delete])
  }
}

pub fn new_session() -> Response {
  let html =
    "<h1>Welcome to Reddot</h1>
    <form action='/session' method='post'>
        <label>Enter a username to login
          <input type='text' name='name'>
        </label>
        <button type='submit'>Log in</button>
      </form>"
  wisp.ok()
  |> wisp.html_body(html)
}

pub fn destroy_session(req: Request) -> Response {
  let resp = wisp.redirect("/session")
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(value) -> wisp.set_cookie(resp, req, cookie_name, value, wisp.Signed, 0)
    Error(_) -> resp
  }
}

pub fn create_session(req: Request, engine: Subject(EngineMessage)) -> Response {
  use formdata <- wisp.require_form(req)
  case list.key_find(formdata.values, "name") {
    Ok(name) -> {
      let assert Ok(actor) =
        actor.new(Account(name, None, 0, [], [], 0, [], engine, None))
        |> actor.on_message(account_message_handler)
        |> actor.start
      actor.send(actor.data, Start(actor.data))
      actor.send(engine, Join(actor.data, name))
      wisp.redirect("/")
      |> wisp.set_cookie(req, cookie_name, name, wisp.Signed, 60 * 60 * 24)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}
