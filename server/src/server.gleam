import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http.{Get, Post}
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

fn home_page(req: Request, user: Subject(String)) -> Response {
  // The home page can only be accessed via GET requests, so this middleware is
  // used to return a 405: Method Not Allowed response for all other methods.
  case req.method {
    Get -> show_login_form()
    Post -> handle_login_form(req, user)
    _ -> wisp.method_not_allowed([Get, Post])
  }
}

fn show_login_form() -> Response {
  let html =
    "<h1>Welcome to Reddot</h1>
    <form method='post'>
        <label>Enter a username to join
          <input type='text' name='username'>
        </label>
        <input type='submit' value='Submit'>
      </form>"
  wisp.ok()
  |> wisp.html_body(html)
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
      wisp.ok()
      |> wisp.html_body(content)
    }
    Error(_) -> {
      wisp.bad_request("Invalid form")
    }
  }
}

fn app(req: Request) -> Response {
  // The home page can only be accessed via GET requests, so this middleware is
  // used to return a 405: Method Not Allowed response for all other methods.
  let html_content =
    "<!DOCTYPE html>
  <html>
  <head>
    <title>Wisp Button Example</title>
  </head>
  <body>
    <h1>Hello from Wisp!</h1>
    <button onclick=\"alert('Button clicked!')\">Click Me</button>
  </body>
  </html>"
  use <- wisp.require_method(req, Get)

  wisp.ok()
  |> wisp.html_body(html_content)
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
    fn(request: Request) -> Response {
      use <- wisp.log_request(request)
      use <- wisp.serve_static(request, under: "/static", from: "/public")
      case wisp.path_segments(request) {
        // This matches `/`.
        [] -> home_page(request, user.data)
        ["app"] -> app(request)

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
