import account.{account_message_handler, create_actors}
import argv
import engine.{engine_message_handler}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/otp/actor
import gleam/pair
import gleam/time/timestamp
import logging
import mist
import routes.{feed, home_page, post, session, subreddits}
import types.{
  type ServerMessage, type ServerState, AddUser, Engine, GetUser, Join, Leave,
  RemoveUser, ServerState, Start,
}
import utils.{create_default_subs}
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)
  //number of actors
  let assert Ok(args) = list.rest(argv.load().arguments)
  let assert Ok(num_string) = list.first(args)
  let assert Ok(num_actors) = int.parse(num_string)

  //max frequency of users sending in seconds
  let assert Ok(args) = list.rest(args)
  let assert Ok(num_string) = list.first(args)
  let assert Ok(max_frequency) = int.parse(num_string)
  let max_frequency = max_frequency * 1000

  let reply_subj = process.new_subject()

  //create default subreddits so users have places to post and such
  let engine_state =
    Engine(
      create_default_subs(2, dict.new()),
      dict.new(),
      reply_subj,
      timestamp.system_time(),
      timestamp.system_time(),
      0,
      0,
      0,
    )

  let assert Ok(engine) =
    actor.new(engine_state)
    |> actor.on_message(engine_message_handler)
    |> actor.start

  let assert Ok(server) =
    actor.new(ServerState(dict.new(), engine.data))
    |> actor.on_message(server_handler)
    |> actor.start

  let step_size = max_frequency / num_actors
  create_actors(num_actors, 0, step_size, step_size, engine.data)

  let secret_key_base = "..."
  let assert Ok(_) =
    fn(req: Request) -> Response {
      use <- wisp.log_request(req)
      use <- wisp.serve_static(req, under: "/static", from: "/public")
      case wisp.path_segments(req) {
        // This matches `/`.
        [] -> home_page(req, server.data)
        ["session"] -> session(req, server.data)
        ["subreddits"] -> subreddits(req, server.data, engine.data)
        ["feed"] -> feed(req, server.data)
        ["post"] -> post(req, server.data, engine.data)
        ["subreddit"] -> routes.subreddit(req, server.data)
        ["message"] -> routes.message(req, server.data, engine.data)
        ["my_subreddits"] -> routes.my_subreddits(req, server.data)
        ["subreddits", sub_id_str, "posts", "new"] ->
          routes.get_new_post(req, sub_id_str, server.data)
        ["subreddits", _sub_id_str, "posts"] ->
          routes.submit_post(req, server.data)
        ["inbox"] -> routes.inbox(req, server.data)
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

pub fn server_handler(
  state: ServerState,
  message: ServerMessage,
) -> actor.Next(ServerState, ServerMessage) {
  case message {
    AddUser(username) -> {
      let assert Ok(actor) =
        actor.new(types.Account(
          username,
          None,
          0,
          [],
          [],
          0,
          [],
          state.engine,
          None,
        ))
        |> actor.on_message(account_message_handler)
        |> actor.start

      actor.send(actor.data, Start(actor.data))
      actor.send(state.engine, Join(actor.data, username))
      actor.continue(
        ServerState(
          ..state,
          users: dict.insert(state.users, username, actor.data),
        ),
      )
    }
    RemoveUser(username) -> {
      let assert Ok(user) = dict.get(state.users, username)
      actor.send(state.engine, Leave(username))
      actor.send(user, types.Quit)
      actor.continue(
        ServerState(..state, users: dict.delete(state.users, username)),
      )
    }
    GetUser(reply, username) -> {
      let user = dict.get(state.users, username)
      process.send(reply, user)
      actor.continue(state)
    }
  }
}
