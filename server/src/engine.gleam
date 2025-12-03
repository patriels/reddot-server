import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/pair
import types.{
  type Comment, type Engine, type EngineMessage, AddToFeed, Comment,
  CreateSubReddit, DownVoteComment, DownVotePost, Engine, GetAUser,
  GetAllSubReddits, GetPost, GetSubReddits, Join, JoinSub, JoinSubReddit, Leave,
  LeaveSubReddit, OnlineUpdate, Post, PostComment, PostInSub, SendDM, SubReddit,
  UpVoteComment, UpVotePost, UpdateKarma,
}

//functions for engine
//check if the comment bucket already exists
//creates the bucket if it doesn't or adds the new comment if it does
pub fn add_comment(
  post_comments: dict.Dict(Int, List(Comment)),
  comment: Comment,
) -> dict.Dict(Int, List(Comment)) {
  case dict.has_key(post_comments, comment.parent_id) {
    True -> {
      //comments are grouped into to buckets based on their parent comment
      let assert Ok(comment_group) = dict.get(post_comments, comment.parent_id)

      //insert new comment into list
      let updated_group = list.append(comment_group, [comment])

      //update dict with new comment
      dict.insert(post_comments, comment.parent_id, updated_group)
    }
    False -> {
      dict.insert(post_comments, comment.parent_id, list.wrap(comment))
    }
  }
}

pub fn engine_message_handler(
  state: Engine,
  message: EngineMessage,
) -> actor.Next(Engine, EngineMessage) {
  //update the state for the message handling
  //let state = Engine(..state, last_display: display_reddit(state))
  case message {
    Join(user, username) -> {
      actor.continue(
        Engine(
          ..state,
          users: dict.insert(state.users, username, user),
          online: { state.online + 1 },
          trans_count: { state.trans_count + 1 },
        ),
      )
    }
    Leave(user) -> {
      actor.continue(
        Engine(
          ..state,
          users: dict.delete(state.users, user),
          online: { state.online + 1 },
          trans_count: { state.trans_count + 1 },
        ),
      )
    }
    CreateSubReddit(name) -> {
      //start subreddit indexing at 1
      let id = dict.size(state.subreddits) + 1
      //create new subreddit
      let sub = SubReddit(id, name, dict.new(), [])
      //add this subreddit to the list of existing subreddits
      let sub_dict = dict.insert(state.subreddits, id, sub)
      actor.continue(
        Engine(..state, subreddits: sub_dict, trans_count: {
          state.trans_count + 1
        }),
      )
    }
    JoinSubReddit(sub_id, user_subject) -> {
      //using map to locate and update the subreddit of interest
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)
      let updated_subscribers = list.append(sub.subscribers, [user_subject])
      let updated_sub = SubReddit(..sub, subscribers: updated_subscribers)
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)
      //update reddit engine state to include updated list of subreddits
      //and count this towards transmissions
      actor.continue(
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        }),
      )
    }
    LeaveSubReddit(sub_id, subject) -> {
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)
      let updated_accs =
        list.drop_while(sub.subscribers, fn(subscriber) {
          subscriber == subject
        })
      let updated_sub = SubReddit(..sub, subscribers: updated_accs)
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)

      //update reddit engine state to include updated list of subreddits
      //and count this towards transmissions
      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    PostInSub(sub_id, post) -> {
      //io.println("Someone posted in " <> int.to_string(sub_id) <> ".")
      //get sub to post in
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)

      //issue post new id
      let post_id = dict.size(sub.posts) + 1
      let updated_post = Post(..post, id: post_id)

      //sends a new post with updated karma to the users
      list.each(sub.subscribers, fn(subscriber) {
        actor.send(subscriber, AddToFeed(updated_post))
      })

      //insert new post into subreddits post dictionary
      let updated_posts = dict.insert(sub.posts, post_id, updated_post)

      //update subreddit with updated list of posts
      let updated_sub = SubReddit(..sub, posts: updated_posts)

      //update map of subs the engine keeps track of
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)

      //update subscribers 

      //update reddit engine state to include updated list of subreddits
      //and count this towards transmissions
      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    PostComment(sub_id, post_id, parent_id, comment) -> {
      //get sub to post in
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)

      //get post to comment on 
      let assert Ok(post) = dict.get(sub.posts, post_id)

      //issue comment new id
      let comments = list.flatten(dict.values(post.comments))
      let comment_id = list.length(comments) + 1
      let comment = Comment(..comment, id: comment_id, parent_id: parent_id)

      //update comment bucket with new list
      let updated_comments = add_comment(post.comments, comment)

      //update post with new comments map
      let updated_post = Post(..post, comments: updated_comments)

      //sends a new post with updated karma to the users
      list.each(sub.subscribers, fn(subscriber) {
        actor.send(subscriber, AddToFeed(updated_post))
      })

      //insert new post into subreddits post dictionary
      let updated_posts = dict.insert(sub.posts, post_id, updated_post)

      //update subreddit with updated list of posts
      let updated_sub = SubReddit(..sub, posts: updated_posts)

      //update map of subs the engine keeps track of
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)

      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    UpVotePost(sub_id, post_id) -> {
      //get sub to post in
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)

      //get post to comment on 
      let assert Ok(post) = dict.get(sub.posts, post_id)

      //update post with new comments map
      let updated_post = Post(..post, up_votes: { post.up_votes + 1 })

      //update post owner's karma
      actor.send(post.author_subject, UpdateKarma(-1))

      //sends a new post with updated karma to the users
      list.each(sub.subscribers, fn(subscriber) {
        actor.send(subscriber, AddToFeed(updated_post))
      })

      //insert new post into subreddits post dictionary
      let updated_posts = dict.insert(sub.posts, post_id, updated_post)

      //update subreddit with updated list of posts
      let updated_sub = SubReddit(..sub, posts: updated_posts)

      //update map of subs the engine keeps track of
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)

      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    DownVotePost(sub_id, post_id) -> {
      //get sub to post in
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)

      //get post to comment on 
      let assert Ok(post) = dict.get(sub.posts, post_id)

      //update post with new comments map
      let updated_post = Post(..post, up_votes: { post.down_votes + 1 })

      //update post owner's karma
      actor.send(post.author_subject, UpdateKarma(-1))

      //sends a new post with updated karma to the users
      list.each(sub.subscribers, fn(subscriber) {
        actor.send(subscriber, AddToFeed(updated_post))
      })

      //insert new post into subreddits post dictionary
      let updated_posts = dict.insert(sub.posts, post_id, updated_post)

      //update subreddit with updated list of posts
      let updated_sub = SubReddit(..sub, posts: updated_posts)
      //update map of subs the engine keeps track of
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)

      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    UpVoteComment(sub_id, post_id, parent_id, comment_id) -> {
      //get sub to post in
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)

      //get post to comment on 
      let assert Ok(post) = dict.get(sub.posts, post_id)

      //comment's are grouped by parent id so find parent and get list
      let assert Ok(comments) = dict.get(post.comments, parent_id)

      //update comment in list
      let updated_comments =
        list.map(comments, fn(comment) {
          case comment_id == comment.id {
            True -> {
              //update the karma for the comment's author
              actor.send(comment.author_subject, UpdateKarma(1))
              //update comment with up vote
              Comment(..comment, up_votes: comment.up_votes + 1)
            }
            False -> {
              comment
            }
          }
        })

      //update comment bucket with new list
      let updated_comments = dict.insert(post.comments, 0, updated_comments)

      //update post with new comments map
      let updated_post = Post(..post, comments: updated_comments)

      list.each(sub.subscribers, fn(subscriber) {
        actor.send(subscriber, AddToFeed(updated_post))
      })

      //insert new post into subreddits post dictionary
      let updated_posts = dict.insert(sub.posts, post_id, updated_post)

      //update subreddit with updated list of posts
      let updated_sub = SubReddit(..sub, posts: updated_posts)

      //update map of subs the engine keeps track of
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)

      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    DownVoteComment(sub_id, post_id, parent_id, comment_id) -> {
      //get sub to post in
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)

      //get post to comment on 
      let assert Ok(post) = dict.get(sub.posts, post_id)

      //comment's are grouped by parent id so find parent and get list
      let assert Ok(comments) = dict.get(post.comments, parent_id)

      //update comment in list
      let updated_comments =
        list.map(comments, fn(comment) {
          case comment_id == comment.id {
            True -> {
              //update the karma for the comment's author
              actor.send(comment.author_subject, UpdateKarma(-1))
              //update comment with up vote
              Comment(..comment, up_votes: comment.down_votes + 1)
            }
            False -> {
              comment
            }
          }
        })

      //update comment bucket with new list
      let updated_comments = dict.insert(post.comments, 0, updated_comments)

      //update post with new comments map
      let updated_post = Post(..post, comments: updated_comments)

      list.each(sub.subscribers, fn(subscriber) {
        actor.send(subscriber, AddToFeed(updated_post))
      })

      //insert new post into subreddits post dictionary
      let updated_posts = dict.insert(sub.posts, post_id, updated_post)

      //update subreddit with updated list of posts
      let updated_sub = SubReddit(..sub, posts: updated_posts)

      //update map of subs the engine keeps track of
      let updated_subreddits =
        dict.insert(state.subreddits, sub_id, updated_sub)
      let new_state =
        Engine(..state, subreddits: updated_subreddits, trans_count: {
          state.trans_count + 1
        })
      actor.continue(new_state)
    }
    GetSubReddits(client) -> {
      //get all subreddit ids
      let subs =
        list.map(dict.values(state.subreddits), fn(sub) { #(sub.id, sub.name) })
      process.send(client, JoinSub(subs))
      actor.continue(state)
    }
    GetAllSubReddits(client) -> {
      //get all subreddit ids
      let subs =
        list.map(dict.values(state.subreddits), fn(sub) { #(sub.id, sub.name) })
      actor.send(client, subs)
      actor.continue(state)
    }
    GetAUser(user, username) -> {
      let len = dict.size(state.users)
      case len {
        //you're the ony user so message yourself (handled on user side)
        1 -> {
          actor.send(user, SendDM(user))
          actor.continue(state)
        }
        _ -> {
          //remove the user who initaiated the request
          let filtered = dict.delete(state.users, username)
          let users = dict.values(filtered)
          //select a random index in the list
          let index = int.random(len - 1)
          //split list before that index
          let split = list.split(users, index)
          //get the user
          let assert Ok(other_user) = list.first(pair.second(split))
          actor.send(user, SendDM(other_user))
          actor.continue(
            Engine(..state, message_count: { state.message_count + 1 }),
          )
        }
      }
    }
    OnlineUpdate(num) -> {
      actor.continue(Engine(..state, online: { state.online + num }))
    }
    GetPost(reply, sub_id, post_id) -> {
      let assert Ok(sub) = dict.get(state.subreddits, sub_id)
      let assert Ok(post) = dict.get(sub.posts, post_id)
      process.send(reply, post)
      actor.continue(state)
    }
    types.GetUserSubj(reply, username) -> {
      let assert Ok(other) = dict.get(state.users, username)
      actor.send(reply, other)
      actor.continue(state)
    }
  }
}
