import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/pair
import gleam/time/duration
import gleam/time/timestamp
import types.{type Comment, type Engine, type Post, type SubReddit}

//functions to start engine
pub fn create_default_subs(
  num: Int,
  subs: dict.Dict(Int, SubReddit),
) -> dict.Dict(Int, SubReddit) {
  case num {
    1 -> {
      let new_sub =
        types.SubReddit(
          num,
          { "Default " <> int.to_string(num) },
          dict.new(),
          [],
        )
      dict.insert(subs, num, new_sub)
    }
    _ -> {
      let existing_subs = create_default_subs(num - 1, subs)
      let new_sub =
        types.SubReddit(
          num,
          { "Default " <> int.to_string(num) },
          dict.new(),
          [],
        )
      dict.insert(existing_subs, num, new_sub)
    }
  }
}

//functions for account handler
pub fn get_random_sub(list: List(#(Int, String))) -> #(Int, String) {
  let len = list.length(list)
  case len == 1 {
    True -> {
      let assert Ok(sub) = list.first(list)
      sub
    }
    False -> {
      //select random item in the list
      let index = int.random(len)
      //splits list in two before the index
      let split = list.split(list, index)
      //get first item in second list from splits
      let assert Ok(sub) = list.first(pair.second(split))
      sub
    }
  }
}

pub fn get_random_post(list: List(Post)) -> Post {
  let len = list.length(list)
  case len == 1 {
    True -> {
      let assert Ok(post) = list.first(list)
      post
    }
    False -> {
      let index = int.random(len)
      let split = list.split(list, index)
      let assert Ok(post) = list.first(pair.second(split))
      post
    }
  }
}

pub fn get_random_comment(list: List(Comment)) -> Comment {
  let len = list.length(list)
  case len == 1 {
    True -> {
      let assert Ok(comment) = list.first(list)
      comment
    }
    False -> {
      let index = int.random(len)
      let split = list.split(list, index)
      let assert Ok(comment) = list.first(pair.second(split))
      comment
    }
  }
}

//just adds some dynamic chooses without creating a seperate function
//neccessiates less messages
pub fn flip_a_coin() -> Bool {
  let choice = int.random(2)
  case choice {
    0 -> True
    _ -> False
  }
}

pub fn display_reddit(reddit: Engine) -> timestamp.Timestamp {
  let curr_time = timestamp.system_time()
  let time_passed = timestamp.difference(reddit.last_display, curr_time)
  let seconds_passed = duration.to_seconds(time_passed)
  case seconds_passed >=. 5.0 {
    True -> {
      print_engine(reddit)
      curr_time
    }
    False -> {
      reddit.last_display
    }
  }
}

pub fn print_engine(reddit: Engine) -> Nil {
  io.print(
    "Reddit Engine State\n"
    <> "Number of subreddits: "
    <> int.to_string(dict.size(reddit.subreddits))
    <> "\n"
    <> "Number of posts: "
    <> int.to_string(
      dict.fold(reddit.subreddits, 0, fn(count, _sub_id, sub) {
        count + dict.size(sub.posts)
      }),
    )
    <> "\n"
    <> "Number of comments: "
    <> int.to_string(
      dict.fold(reddit.subreddits, 0, fn(count, _sub_id, sub) {
        let comment_count =
          dict.fold(sub.posts, 0, fn(cum, _post_id, post) {
            let comments = list.flatten(dict.values(post.comments))
            //io.println(int.to_string(list.length(comments)))
            cum + list.length(comments)
          })
        count + comment_count
      }),
    )
    <> "\n"
    <> "Users online: "
    <> int.to_string(reddit.online)
    <> "/"
    <> int.to_string(dict.size(reddit.users))
    <> "\n"
    <> "Number of requests to engine: "
    <> int.to_string(reddit.trans_count)
    <> "\n"
    <> "Messages transmitted between users: "
    <> int.to_string(reddit.message_count)
    <> "\n"
    <> "-----------------------------------------------------------\n",
  )
}
