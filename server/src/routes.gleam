import account.{account_message_handler}
import gleam/erlang/process.{type Subject}
import gleam/http.{Delete, Get, Post}
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/string
import types.{type EngineMessage, Account, GetAllSubReddits, Join, Start}
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
        "<ul>",
        "<li><a href='/subreddits'>View Available SubReddits</a></li>",
        "</ul>",
      ]
      |> string.concat
      |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn subreddits(req: Request, engine: Subject(EngineMessage)) -> Response {
  case req.method {
    Get -> view_subreddits(req, engine)
    Post -> create_session(req)
    Delete -> destroy_session(req)
    _ -> wisp.method_not_allowed([Get, Post, Delete])
  }
}

pub fn view_subreddits(req: Request, engine: Subject(EngineMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(_name) -> {
      let list = process.call(engine, 100, GetAllSubReddits)
      let html =
        "<h1>Available SubReddits</h1>"
        <> list.fold(list, "", fn(result, sub) {
          result
          <> "<form action='/subreddits' method='post'><label>"
          <> sub.1
          <> "<input type='submit' id='"
          <> int.to_string(sub.0)
          <> "'>
      </form>"
        })

      html |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn session(req: Request) -> Response {
  case req.method {
    Get -> new_session()
    Post -> create_session(req)
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

pub fn create_session(req: Request) -> Response {
  use formdata <- wisp.require_form(req)
  case list.key_find(formdata.values, "name") {
    Ok(name) -> {
      wisp.redirect("/")
      |> wisp.set_cookie(req, cookie_name, name, wisp.Signed, 60 * 60 * 24)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}
