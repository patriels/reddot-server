import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http.{Delete, Get, Post}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import wisp.{type Request, type Response}
import wisp/wisp_mist

const cookie_name = "id"

pub type ClientAccount {
  ClientAccount(username: String, karma: Int)
}

fn home_page(req: Request, user: Subject(String)) -> Response {
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

fn state_handler(state: String, message: String) -> actor.Next(String, String) {
  io.println(message)
  actor.continue(message)
}

pub fn main() {
  let secret_key_base = "..."
  let assert Ok(user) =
    actor.new("")
    |> actor.on_message(state_handler)
    |> actor.start
  let assert Ok(_) =
    fn(req: Request) -> Response {
      use <- wisp.log_request(req)
      use <- wisp.serve_static(req, under: "/static", from: "/public")
      case wisp.path_segments(req) {
        // This matches `/`.
        [] -> home_page(req, user.data)
        ["session"] -> session(req)

        // This matches all other paths.
        _ -> wisp.not_found()
      }
    }
    |> wisp_mist.handler(secret_key_base)
    |> mist.new
    |> mist.port(3000)
    |> mist.start
  process.sleep_forever()
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
      //process.send(user, username)
      wisp.redirect("/")
      |> wisp.set_cookie(req, cookie_name, name, wisp.Signed, 60 * 60 * 24)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

fn handle_login_form(req: Request, user: Subject(String)) -> Response {
  use formdata <- wisp.require_form(req)
  let result = {
    use username <- result.try(list.key_find(formdata.values, "username"))
    process.send(user, username)
    let greeting = "Sucess! We'll redirect you to your homepage"
    Ok(greeting)
  }
  // An appropriate response is returned depending on whether the form data
  // could be successfully handled or not.
  case result {
    Ok(content) -> {
      //wisp.ok()
      //|> wisp.html_body(content)
      wisp.redirect("http://localhost:3000")
    }
    Error(_) -> {
      wisp.bad_request("Invalid form")
    }
  }
}
