import css.{get_css}
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/http.{Delete, Get, Post}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/string
import logging
import types.{
  type EngineMessage, type ServerMessage, AddUser, DownVotePost,
  GetAllSubReddits, GetFeed, GetUser, PostToSub, RemoveUser, Subscribe,
  Unsubscribe, UpVotePost,
}
import utils
import wisp.{type Request, type Response}

//server: Subject(ServerMessage)
// engine: Subject(EngineMessage)
const cookie_name = "id"

pub fn home_page(req: Request, server: Subject(ServerMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      let actor_opt = process.call(server, 100, GetUser(_, name))
      case actor_opt {
        Error(_) -> {
          wisp.redirect("/session")
        }
        Ok(actor) -> {
          [
            get_css(),
            "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
            "<h1> Hello " <> name <> "</h1>",
            "<form action='/session?_method=DELETE' method='post'>",
            "<button type='submit'>Log out</button>",
            "</form>",
            "<h4>Karma: "
              <> int.to_string(process.call(actor, 100, types.GetKarma))
              <> "</h4>",
            "<ul>",
            "<li><a href='/subreddits'>View Available SubReddits</a></li>",
            "<li><a href='/feed'>View Your Feed</a></li>",
            "<li><a href='/subreddit'>Create a SubReddit</a></li>",
            "<li><a href='/my_subreddits'>View Your Subreddits</a></li>",
            "<li><a href='/inbox'>Inbox</a></li>",
            "</ul>",
            "</div>",
          ]
          |> string.concat
          |> wisp.html_response(200)
        }
      }
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
      let actor_opt = process.call(server, 100, GetUser(_, name))
      case actor_opt {
        Error(_) -> {
          wisp.redirect("/session")
        }
        Ok(actor) -> {
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
                "<h5>",
                post.title <> " by ",
                "<a href='/message?username=" <> post.author_username <> "''>",
                post.author_username,
                "</a>",
                "</h5>",
                "<p>" <> post.content <> "</p>",
                "<a href=\"/post?post_id="
                  <> int.to_string(post.id)
                  <> "&sub_id="
                  <> int.to_string(post.sub_id)
                  <> "\"/>View Post and Comments</a>",
                "</div>",
              ]
              string.concat(html)
            })

          let html_list = list.append(html_list, posts)
          let html_list =
            list.append(html_list, [
              "<br/><a href='/' class='button-link'>Back to Main Menu</a>",
              "</div>",
            ])
          string.concat(html_list) |> wisp.html_response(200)
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn message(
  req: Request,
  server: Subject(ServerMessage),
  engine: Subject(EngineMessage),
) -> Response {
  case req.method {
    Get -> message_form(req, server)
    Post -> send_message(req, server, engine)
    //Delete -> destroy_session(req)
    _ -> wisp.method_not_allowed([Get, Post, Delete])
  }
}

pub fn message_form(req: Request, server: Subject(ServerMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      let actor_opt = process.call(server, 100, types.GetUser(_, name))
      case actor_opt {
        Error(_) -> {
          wisp.redirect("/session")
        }
        Ok(_actor) -> {
          case list.key_find(wisp.get_query(req), "username") {
            Ok(username) -> {
              logging.log(
                logging.Info,
                name <> " wants to send a message to " <> username,
              )
              let actor_opt = process.call(server, 100, GetUser(_, name))
              case actor_opt {
                Error(_) -> {
                  wisp.redirect("/session")
                }
                Ok(_actor) -> {
                  let html_list = [
                    get_css(),
                    "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
                    "<h1> Send " <> username <> " A Message</h1>",
                    "<form action='/message' method='post'>",
                    "<h5>",
                    "Type message",
                    "</h5>",
                    "<input type='hidden' name='user_name' value='"
                      <> username
                      <> "'/>",
                    "<textarea name='content' required></textarea>",
                    "<input type='submit' value='Send'/>",
                    "</form>",
                  ]
                  //let html_list = list.append(html_list, posts)
                  string.concat(html_list) |> wisp.html_response(200)
                }
              }
            }
            Error(_) -> {
              logging.log(logging.Info, "Link invalid")
              wisp.redirect("/")
            }
          }
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/subreddits")
    }
  }
}

pub fn send_message(
  req: Request,
  server: Subject(ServerMessage),
  engine: Subject(EngineMessage),
) -> Response {
  use formdata <- wisp.require_form(req)
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(formdata.values, "content") {
        Ok(content) -> {
          let assert Ok(username) = list.key_find(formdata.values, "user_name")
          logging.log(logging.Info, name <> " wants to post a comment")
          let actor_opt = process.call(server, 100, GetUser(_, name))
          case actor_opt {
            Error(_) -> {
              wisp.redirect("/session")
            }
            Ok(actor) -> {
              let subj =
                process.call(engine, 100, types.GetUserSubj(_, username))
              actor.send(actor, types.SendMessage(content, subj))
              wisp.redirect("/feed")
            }
          }
        }
        Error(_) -> {
          logging.log(logging.Info, "Link invalid")
          wisp.redirect("/")
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn post(
  req: Request,
  server: Subject(ServerMessage),
  engine: Subject(EngineMessage),
) -> Response {
  case req.method {
    Get -> view_post(req, engine)
    Post -> {
      use formdata <- wisp.require_form(req)
      case list.key_find(formdata.values, "action") {
        Ok("comment") -> post_comment(req, server)
        Ok("vote") -> post_vote(req, engine)
        _ -> wisp.method_not_allowed([Post])
      }
    }
    //Delete -> destroy_session(req)
    _ -> wisp.method_not_allowed([Get, Post, Delete])
  }
}

pub fn view_post(req: Request, engine: Subject(EngineMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(wisp.get_query(req), "post_id") {
        Ok(post_id) -> {
          logging.log(
            logging.Info,
            name <> " wants to view comments for post " <> post_id,
          )
          let assert Ok(sub_id) = list.key_find(wisp.get_query(req), "sub_id")
          let assert Ok(post_id) = int.parse(post_id)
          let assert Ok(sub_id) = int.parse(sub_id)
          let post =
            process.call(engine, 100, types.GetPost(_, sub_id, post_id))
          let html_list = [
            get_css(),
            "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
            "<h1>" <> post.title <> "</h1>",
            "<h3> posted by " <> post.author_username <> "</h3>",
            "<p>" <> post.content <> "</p>",
            "<div>",
            "<span>" <> int.to_string(post.up_votes) <> "</span>",
            "<form action='/post' method='post' style='display:inline'>",
            "  <input type='hidden' name='action' value='vote'/>",
            "  <input type='hidden' name='post_id' value='"
              <> int.to_string(post.id)
              <> "'/>",
            "  <input type='hidden' name='sub_id' value='"
              <> int.to_string(post.sub_id)
              <> "'/>",
            "  <input type='hidden' name='vote' value='1'/>",
            "  <button type='submit'>Up Vote</button>",
            "</form>",
            "<span>" <> int.to_string(post.down_votes) <> "</span>",
            "<form action='/post' method='post' style='display:inline'>",
            "  <input type='hidden' name='action' value='vote'/>",
            "  <input type='hidden' name='post_id' value='"
              <> int.to_string(post.id)
              <> "'/>",
            "  <input type='hidden' name='sub_id' value='"
              <> int.to_string(post.sub_id)
              <> "'/>",
            "  <input type='hidden' name='vote' value='-1'/>",
            "  <button type='submit'>Down Vote</button>",
            "</form>",
            "</div>",
          ]
          let comment_form = [
            "<form action='/post' method='post'>",
            "  <input type='hidden' name='action' value='comment'/>",
            "<h5>",
            "Leave a comment",
            "</h5>",
            "<input type='hidden' name='sub_id' value='"
              <> int.to_string(post.sub_id)
              <> "'/>",
            "<input type='hidden' name='post_id' value='"
              <> int.to_string(post.id)
              <> "'/>",
            "<textarea name='content' required></textarea>",
            "<input type='submit' value='Submit'/>",
            "</form>",
          ]
          case dict.size(post.comments) {
            0 -> {
              let html_list =
                list.append(
                  html_list,
                  list.append(
                    ["<p>No comments yet. Be the first!</p>"],
                    comment_form,
                  ),
                )
              let html_list =
                list.append(html_list, [
                  "<br/><a href='/' class='button-link'>Back to Main Menu</a>",
                  "</div>",
                ])
              string.concat(html_list) |> wisp.html_response(200)
            }
            _ -> {
              let assert Ok(base_level_comments) = dict.get(post.comments, 0)
              let comments_html =
                utils.get_comments(
                  post.comments,
                  post.sub_id,
                  post.id,
                  0,
                  base_level_comments,
                  "",
                )

              let html_list =
                list.append(html_list, list.append(comments_html, comment_form))
              let html_list =
                list.append(html_list, [
                  "<br/><a href='/' class='button-link'>Back to Main Menu</a>",
                  "</div>",
                ])
              string.concat(html_list) |> wisp.html_response(200)
            }
          }
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

pub fn post_comment(req: Request, server: Subject(ServerMessage)) -> Response {
  use formdata <- wisp.require_form(req)
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(formdata.values, "content") {
        Ok(content) -> {
          logging.log(logging.Info, name <> " wants to post a comment")
          let actor_opt = process.call(server, 100, GetUser(_, name))
          case actor_opt {
            Error(_) -> {
              wisp.redirect("/session")
            }
            Ok(actor) -> {
              let assert Ok(post_id) = list.key_find(formdata.values, "post_id")
              let assert Ok(sub_id) = list.key_find(formdata.values, "sub_id")
              let assert Ok(p_id) = int.parse(post_id)
              let assert Ok(s_id) = int.parse(sub_id)
              actor.send(actor, types.MakeAComment(s_id, p_id, 0, content))
              wisp.redirect("/post?post_id=" <> post_id <> "&sub_id=" <> sub_id)
            }
          }
        }
        Error(_) -> {
          logging.log(logging.Info, "Link invalid")
          wisp.redirect("/")
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn my_subreddits(req: Request, server: Subject(ServerMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      let actor_opt = process.call(server, 100, GetUser(_, name))
      case actor_opt {
        Error(_) -> {
          wisp.redirect("/session")
        }
        Ok(actor) -> {
          let subs = process.call(actor, 100, types.GetSubscriptions)
          let html_list = [
            get_css(),
            "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
            "<h1>My SubReddits</h1>",
          ]
          let forms =
            list.map(subs, fn(sub) {
              "<div style='display:flex; align-items:center; gap:12px; margin-bottom:10px'>

                <h3 style='margin:0; padding:0; font-size:18px; line-height:1'>
                  "
              <> sub.1
              <> "
                </h3>

                <form action='/subreddits' method='post' style='margin:0'>
                  <input type='hidden' name='_method' value='DELETE'/>
                  <input type='hidden' name='sub_id' value='"
              <> int.to_string(sub.0)
              <> "'/>
                  <input class='button-link' type='submit' value='Leave' style='margin:0'/>
                </form>

                <a class='button-link' href='/subreddits/"
              <> int.to_string(sub.0)
              <> "/posts/new' style='margin:0'>
                  Make a Post
                </a>

              </div>"
            })

          let html_list = list.append(html_list, forms)
          let html_list = list.append(html_list, ["</div>"])
          let html_list =
            list.append(html_list, [
              "<br/><a href='/' class='button-link'>Back to Main Menu</a>",
              "</div>",
            ])
          string.concat(html_list) |> wisp.html_response(200)
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn inbox(req: Request, server: Subject(ServerMessage)) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      let actor_opt = process.call(server, 100, GetUser(_, name))
      case actor_opt {
        Error(_) -> {
          wisp.redirect("/session")
        }
        Ok(actor) -> {
          let messages = process.call(actor, 100, types.GetInbox)
          let html_list = [
            get_css(),
            "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
            "<h1>Inbox</h1>",
          ]
          let dms =
            list.map(messages, fn(dm) {
              let html = [
                "<div>",
                "<p class='username'>" <> dm.send_name <> "</p>",
                "<p>" <> dm.message <> "</p>",
                "<a href='/message?username=" <> dm.send_name <> "''>",
                "Message Back",
                "</a>",
                "</div>",
              ]
              string.concat(html)
            })
          let html_list = list.append(html_list, dms)
          let html_list = list.append(html_list, ["</div>"])
          string.concat(html_list) |> wisp.html_response(200)
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn subreddit(req: Request, server: Subject(ServerMessage)) -> Response {
  case req.method {
    Get -> subreddit_form(req)
    Post -> create_subreddit(req, server)
    //Delete -> destroy_session(req)
    _ -> wisp.method_not_allowed([Get, Post, Delete])
  }
}

pub fn subreddit_form(req: Request) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(_name) -> {
      let html_list = [
        get_css(),
        "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
        "<h1>Create A New SubReddit</h1>",
        "<form action='/subreddit' method='post'>",
        "<label>Title: ",
        "<input name='title' required>",
        "<input class='button-link' type='submit' value='Submit'/>",
        "</form>",
        "</div>",
      ]

      string.concat(html_list) |> wisp.html_response(200)
    }
    Error(_) -> {
      wisp.redirect("/subreddits")
    }
  }
}

pub fn create_subreddit(
  req: Request,
  server: Subject(ServerMessage),
) -> Response {
  use formdata <- wisp.require_form(req)
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(formdata.values, "title") {
        Ok(title) -> {
          logging.log(logging.Info, name <> " wants to create a subreddit ")
          let actor_opt = process.call(server, 100, GetUser(_, name))
          case actor_opt {
            Error(_) -> {
              wisp.redirect("/session")
            }
            Ok(actor) -> {
              actor.send(actor, types.NewSubreddit(title))
              wisp.redirect("/")
            }
          }
        }
        Error(_) -> {
          logging.log(logging.Info, "Link invalid")
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
    Post -> {
      use formdata <- wisp.require_form(req)
      let method_override = case list.key_find(formdata.values, "_method") {
        Ok(value) -> value
        Error(_) -> "POST"
      }
      case method_override {
        "DELETE" -> unsubscribe(req, server)
        _ -> subscribe(req, server)
      }
    }
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
            <> "'/><input type='hidden' name='sub_name' value='"
            <> sub.1
            <> "'/><input class='button-link' type='submit' value='Join'/></h3></form>"
          form
        })

      let html_list = list.append(html_list, forms)
      let html_list = list.append(html_list, ["</div>"])
      let html_list =
        list.append(html_list, [
          "<br/><a href='/' class='button-link'>Back to Main Menu</a>",
          "</div>",
        ])
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
          let assert Ok(sub_name) = list.key_find(formdata.values, "sub_name")
          let actor_opt = process.call(server, 100, GetUser(_, name))
          case actor_opt {
            Error(_) -> {
              wisp.redirect("/session")
            }
            Ok(actor) -> {
              let assert Ok(sub_id) = int.parse(sub_id)
              actor.send(actor, Subscribe(sub_id, sub_name))
              wisp.redirect("/")
              |> wisp.set_cookie(
                req,
                cookie_name,
                name,
                wisp.Signed,
                60 * 60 * 24,
              )
            }
          }
        }
        Error(_) -> {
          logging.log(logging.Info, "Link invalid")
          wisp.redirect("/subreddits")
        }
      }
    }
    Error(_) -> {
      wisp.redirect("/session")
    }
  }
}

pub fn unsubscribe(req: Request, server: Subject(ServerMessage)) -> Response {
  use formdata <- wisp.require_form(req)
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      case list.key_find(formdata.values, "sub_id") {
        Error(_) -> wisp.redirect("/session")
        Ok(sub_id) -> {
          let assert Ok(sub_id_int) = int.parse(sub_id)
          let actor_opt = process.call(server, 100, GetUser(_, name))
          case actor_opt {
            Error(_) -> wisp.redirect("/session")
            Ok(actor) -> {
              actor.send(actor, Unsubscribe(sub_id_int))
              wisp.redirect("/")
              |> wisp.set_cookie(
                req,
                cookie_name,
                name,
                wisp.Signed,
                60 * 60 * 24,
              )
            }
          }
        }
      }
    }
    Error(_) -> wisp.redirect("/session")
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
    get_css()
    <> "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>
    <h1>Welcome to Reddot</h1>
    <form action='/session' method='post'>
        <label>Enter a username to login
          <input type='text' name='name'>
        </label>
        <button type='submit'>Log in</button>
      </form>
      </div>"
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

pub fn post_vote(req: Request, engine: Subject(EngineMessage)) -> Response {
  use formdata <- wisp.require_form(req)
  case list.key_find(formdata.values, "post_id") {
    Error(_) -> wisp.redirect("/session")
    Ok(post_id) -> {
      case list.key_find(formdata.values, "sub_id") {
        Error(_) -> wisp.redirect("/session")
        Ok(sub_id) -> {
          case list.key_find(formdata.values, "vote") {
            Error(_) -> wisp.redirect("/session")
            Ok(vote) -> {
              let assert Ok(sub) = int.parse(sub_id)
              let assert Ok(post) = int.parse(post_id)
              case vote {
                "1" -> actor.send(engine, UpVotePost(sub, post))
                "-1" -> actor.send(engine, DownVotePost(sub, post))
                _ -> Nil
              }
              wisp.redirect("/post?post_id=" <> post_id <> "&sub_id=" <> sub_id)
            }
          }
        }
      }
    }
  }
}

pub fn get_new_post(
  req: Request,
  sub_id_str: String,
  server: Subject(ServerMessage),
) -> Response {
  case wisp.get_cookie(req, cookie_name, wisp.Signed) {
    Ok(name) -> {
      // Check user exists
      case process.call(server, 100, GetUser(_, name)) {
        Error(_) -> wisp.redirect("/session")
        Ok(_actor) -> {
          logging.log(
            logging.Info,
            name <> " wants to post on sub " <> sub_id_str,
          )

          let html_list = [
            get_css(),
            "<div class='w3-main w3-content w3-padding' style='max-width:1200px;margin-top:100px'>",
            "<h1>Make a Post</h1>",
            "<form action='/subreddits/"
              <> sub_id_str
              <> "/posts' method='post'>",
            "<input type='hidden' name='sub_id' value='" <> sub_id_str <> "'/>",
            "<input type='hidden' name='user_name' value='" <> name <> "'/>",
            "<div style='display:flex; align-items:center; margin:10px 0'>",
            "  <label for='title' style='width:100px'>Title:</label>",
            "  <input type='text' id='title' name='title' required style='flex:1'/>",
            "</div>",

            "<div style='display:flex; align-items:flex-start; margin:10px 0'>",
            "  <label for='content' style='width:100px; margin-top:4px'>Content:</label>",
            "  <textarea name='content' rows='6' required style='flex:1'></textarea>",
            "</div>",
            "<input type='submit' value='Submit Post'/>",
            "</form>",
            "</div>",
          ]

          string.concat(html_list) |> wisp.html_response(200)
        }
      }
    }
    Error(_) -> wisp.redirect("/session")
  }
}

pub fn submit_post(req: Request, server: Subject(ServerMessage)) -> Response {
  use formdata <- wisp.require_form(req)

  let assert Ok(sub_id_str) = list.key_find(formdata.values, "sub_id")
  let assert Ok(sub_id) = int.parse(sub_id_str)
  let assert Ok(title) = list.key_find(formdata.values, "title")
  let assert Ok(content) = list.key_find(formdata.values, "content")
  let assert Ok(name) = list.key_find(formdata.values, "user_name")

  logging.log(logging.Info, name <> " submitted a post to sub " <> sub_id_str)
  let actor_opt = process.call(server, 100, types.GetUser(_, name))
  case actor_opt {
    Error(_) -> {
      wisp.redirect("/session")
    }
    Ok(actor) -> {
      actor.send(actor, PostToSub(sub_id, title, content))
      wisp.redirect("/")
    }
  }

  wisp.redirect("/")
}
