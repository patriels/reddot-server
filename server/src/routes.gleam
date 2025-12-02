import css.{get_css}
import gleam/erlang/process.{type Subject}
import gleam/http.{Delete, Get, Post}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/string
import logging
import types.{
  type EngineMessage, type ServerMessage, AddUser, GetAllSubReddits, GetFeed,
  GetUser, RemoveUser, Subscribe,
}
import wisp.{type Request, type Response}

//server: Subject(ServerMessage)
// engine: Subject(EngineMessage)
const cookie_name = "id"

pub fn home_page(req: Request) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      [
        get_css(),
        "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
        "<h1> Hello " <> name <> "</h1>",
        "<form action='/session?_method=DELETE' method='post'>",
        "  <button type='submit'>Log out</button>",
        "</form>",
        "<ul>",
        "<li><a href='/subreddits'>View Available SubReddits</a></li>",
        "<li><a href='/feed'>View Your Feed</a></li>",
        "</ul>",
        "</div>",
      ]
      |> string.concat
      |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn feed(req: Request, server: Subject(ServerMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      logging.log(logging.Info, name <> " wants to view their feed")
      let actor = process.call(server, 100, GetUser(_, name))
      let post_list = process.call(actor, 100, GetFeed)
      let html_list = [
        get_css(),
        "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
        "<h1>" <> name <> "'s Feed</h1>",
      ]
      let posts =
        list.map(post_list, fn(post) {
          let html = [
            "<div>",
            "<h5>" <> post.title <> " by " <> post.author_username <> "</h5>",
            "<p>" <> post.content <> "</p>",
            "<a href=\"/post?post_id="
              <> int.to_string(post.id)
              <> "&sub_id="
              <> int.to_string(post.id)
              <> "\"/>View Comments</a>",
            "</div>",
          ]
          string.concat(html)
        })

      let html_list = list.append(html_list, posts)
      string.concat(html_list) |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn post(req: Request, server: Subject(ServerMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(wisp.get_query(req), "post_id") {
        Ok(post_id) -> {
          logging.log(
            logging.Info,
            name <> " wants to view comments for post " <> post_id,
          )
          //let actor = process.call(server, 100, GetUser(_, name))
          //let post_list = process.call(actor, 100, GetFeed)
          let html_list = [
            get_css(),
            "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
            "<h1>" <> post_id <> "</h1>",
          ]

          //let html_list = list.append(html_list)
          string.concat(html_list) |> wisp.html_response(200)
        }
        Error(_) -> {
          wisp.redirect("/")
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn subreddits(
  req: Request,
  server: Subject(ServerMessage),
  engine: Subject(EngineMessage),
) -> Response {
  case req.method {
    Get -> view_subreddits(req, engine)
    Post -> subscribe(req, server)
    //Delete -> destroy_session(req)
    _ -> wisp.method_not_allowed([Get, Post, Delete])
  }
}

pub fn view_subreddits(req: Request, engine: Subject(EngineMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(_name) -> {
      let subs = process.call(engine, 100, GetAllSubReddits)
      let html_list = [
        get_css(),
        "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
        "<h1>Available SubReddits</h1>",
      ]
      let forms =
        list.map(subs, fn(sub) {
          let form =
            "<form action='/subreddits' method='post'><h3>"
            <> sub.1
            <> "<input type='hidden' name='sub_id' value='"
            <> int.to_string(sub.0)
            <> "'/><input class='button-link' type='submit' value='Join'/></h3></form>"
          form
        })
      let html_list = list.append(html_list, forms)
      let html_list = list.append(html_list, ["</div>"])
      string.concat(html_list) |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn subscribe(req: Request, server: Subject(ServerMessage)) -> Response {
  use formdata <- wisp.require_form(req)
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(formdata.values, "sub_id") {
        Ok(sub_id) -> {
          logging.log(
            logging.Info,
            name <> " wants to join subreddit " <> sub_id,
          )
          let actor = process.call(server, 100, GetUser(_, name))
          let assert Ok(sub_id) = int.parse(sub_id)
          actor.send(actor, Subscribe(sub_id))
          wisp.redirect("/")
        }
        Error(_) -> {
          logging.log(logging.Info, "didn't find id")
          wisp.redirect("/")
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn session(req: Request, server: Subject(ServerMessage)) -> Response {
  case req.method {
    Get -> new_session()
    Post -> create_session(req, server)
    Delete -> destroy_session(req, server)
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

pub fn create_session(req: Request, server: Subject(ServerMessage)) -> Response {
  use formdata <- wisp.require_form(req)
  case list.key_find(formdata.values, "name") {
    Ok(name) -> {
      actor.send(server, AddUser(name))
      wisp.redirect("/")
      |> wisp.set_cookie(req, cookie_name, name, wisp.Signed, 60 * 60 * 24)
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn destroy_session(req: Request, server: Subject(ServerMessage)) -> Response {
  let resp = wisp.redirect("/session")
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(value) -> {
      actor.send(server, RemoveUser(value))
      wisp.set_cookie(resp, req, cookie_name, value, wisp.Signed, 0)
    }
    Error(_) -> resp
  }
}
