import account.{create_actors}
import argv
import client_types.{type Account}
import engine.{engine_message_handler}
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/list
import gleam/otp/actor
import gleam/string
import gleam/time/timestamp
import logging
import mist
import routes.{home_page, session, subreddits}
import types.{Engine}
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

  let step_size = max_frequency / num_actors
  create_actors(num_actors, 0, step_size, step_size, engine.data)

  let secret_key_base = "..."
  let assert Ok(_) =
    fn(req: Request) -> Response {
      use <- wisp.log_request(req)
      use <- wisp.serve_static(req, under: "/static", from: "/public")
      case wisp.path_segments(req) {
        // This matches `/`.
        [] -> home_page(req, engine.data)
        ["session"] -> session(req)
        ["subreddits"] -> subreddits(req, engine.data)

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
