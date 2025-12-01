import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import prng/random
import prng/seed
import types.{
  type Account, type AccountMessage, type EngineMessage, Account, AddToFeed,
  Comment, CommentOnPost, CreateSubReddit, DirectMessage, DownVoteComment,
  DownVotePost, GetAUser, GetSubReddits, GetSubs, Join, JoinSub, JoinSubReddit,
  NextAction, OnlineUpdate, Post, PostInSub, ReceiveDM, ReplyToComment, SendDM,
  Start, UpVoteComment, UpVotePost, UpdateKarma,
}
import utils.{flip_a_coin, get_random_comment, get_random_id, get_random_post}

pub fn create_actors(
  num: Int,
  index: Int,
  curr_freq: Int,
  step: Int,
  engine: Subject(EngineMessage),
) -> Nil {
  case index < num {
    True -> {
      let assert Ok(actor) =
        actor.new(types.Account(
          "User " <> int.to_string(index + 1),
          None,
          curr_freq,
          [],
          [],
          0,
          [],
          engine,
          Some(random.float(0.0, 1.0)),
        ))
        |> actor.on_message(account_message_handler)
        |> actor.start
      //update actor with own subject for further operations
      actor.send(actor.data, Start(actor.data))
      //make user known to reddit engine
      actor.send(engine, Join(actor.data, "User" <> int.to_string(index + 1)))
      //all users first action is to join a subreddit
      actor.send(actor.data, NextAction(0.035, seed.new(index)))
      //continue creating actors
      create_actors(num, { index + 1 }, { curr_freq + step }, step, engine)
    }
    False -> {
      Nil
    }
  }
}

pub fn account_message_handler(
  state: Account,
  message: AccountMessage,
) -> actor.Next(Account, AccountMessage) {
  case message {
    //updates the state's subject since its generated after the fact
    Start(sbj) -> {
      //io.println("User " <> state.username <> " is up and running")
      actor.continue(Account(..state, subject: Some(sbj)))
    }
    GetSubs(_subs) -> {
      actor.continue(state)
    }
    NextAction(choice, seed) -> {
      //echo choice
      //process current choice that was sent to actor
      case choice {
        //create a new subreddit
        n if n <. 0.02 -> {
          let name = "Made by " <> state.username
          actor.send(state.reddit_engine, CreateSubReddit(name))
          actor.continue(state)
        }
        //Send request for the list of subreddits to join
        n if n >. 0.002 && n <. 0.14 -> {
          //Request the list of subreddits to join
          let assert Some(self) = state.subject
          //subreddit will send actor a list of available subreddits to join
          actor.send(state.reddit_engine, GetSubReddits(self))
          actor.continue(state)
        }
        //Leave a subreddit you're apart of
        //TODO: remove posts from feed (beyond project scope)
        n if n >. 0.14 && n <. 0.2 -> {
          //leave subreddit if you have more than two subs
          case list.length(state.subreddits) > 2 {
            True -> {
              //get a subreddits to leave
              let sub_id = get_random_id(state.subreddits)
              let updated_subs =
                list.drop_while(state.subreddits, fn(sub) { sub == sub_id })
              //io.println("User " <> state.username <> " left a subreddit.")
              actor.continue(Account(..state, subreddits: updated_subs))
            }
            False -> {
              //wait for next user action
              actor.continue(state)
            }
          }
        }
        //Make a post in a subreddit
        n if n >. 0.2 && n <. 0.32 -> {
          //can't if you've left all your subreddits
          case !list.is_empty(state.subreddits) {
            True -> {
              //get random sub id
              let sub_id = get_random_id(state.subreddits)
              //need self to get Karma updates
              let assert Some(self) = state.subject
              let post =
                Post(
                  0,
                  sub_id,
                  {
                    "This is a cool topics idea "
                    <> state.username
                    <> " wants to talk about."
                  },
                  state.username,
                  self,
                  {
                    "Imagine this has a lot of conent about something interesting. A lot of great points were made, then they lost you. This is a post by "
                    <> state.username
                  },
                  dict.new(),
                  0,
                  0,
                )
              actor.send(state.reddit_engine, PostInSub(sub_id, post))
              //io.println("User " <> state.username <> " made a post.")
              actor.continue(state)
            }
            False -> {
              //no subreddits to post in
              actor.continue(state)
            }
          }
        }
        //make comment on post or reply to comment
        n if n >. 0.32 && n <. 0.48 -> {
          case list.is_empty(state.feed) {
            True -> {
              //no posts in feed to
              actor.continue(state)
            }
            False -> {
              //get post to possibly comment on
              let post = get_random_post(state.feed)
              //create the comment to post
              let assert Some(self) = state.subject
              let comment =
                Comment(
                  0,
                  { "This is a comment by " <> state.username },
                  state.username,
                  self,
                  0,
                  0,
                  0,
                )
              //check if the post has any comments to reply to
              //flip a coin to decide if to reply to the post or reply to a comment
              case !dict.is_empty(post.comments) && flip_a_coin() {
                //if the post has comments and the flip was true
                //reply to an existing comment under the post
                True -> {
                  let comments = list.flatten(dict.values(post.comments))
                  let existing_comment = get_random_comment(comments)
                  actor.send(
                    state.reddit_engine,
                    ReplyToComment(
                      post.sub_id,
                      post.id,
                      existing_comment.id,
                      comment,
                    ),
                  )
                  //io.println(
                  //"User " <> state.username <> " replied to a comment.",
                  //)
                }
                //if the flip was false then just reply to the post
                False -> {
                  actor.send(
                    state.reddit_engine,
                    CommentOnPost(post.sub_id, post.id, comment),
                  )
                  //io.println(
                  //"User " <> state.username <> " commented on a post.",
                  //)
                }
              }
              actor.continue(state)
            }
          }
        }
        //Upvote a post or a comment
        n if n >. 0.48 && n <. 0.68 -> {
          //make sure there's posts to upvote
          case !list.is_empty(state.feed) {
            True -> {
              let post = get_random_post(state.feed)
              //check if the post has any comments to reply to
              //flip a coin to decide if to reply to the post or reply to a comment
              case flip_a_coin() && !dict.is_empty(post.comments) {
                //if the post has comments and the flip was true upvote a comment
                True -> {
                  let comments = list.flatten(dict.values(post.comments))
                  let comment = get_random_comment(comments)
                  process.send(
                    state.reddit_engine,
                    UpVoteComment(
                      post.sub_id,
                      post.id,
                      comment.parent_id,
                      comment.id,
                    ),
                  )
                  //io.println(
                  //"User " <> state.username <> " up voted a comment.",
                  //)
                }
                //if the post has comments and the flip was false upvote a post
                False -> {
                  process.send(
                    state.reddit_engine,
                    UpVotePost(post.sub_id, post.id),
                  )
                  //io.println("User " <> state.username <> " up voted a post.")
                }
              }
              actor.continue(state)
            }
            False -> {
              //no posts to upvote
              actor.continue(state)
            }
          }
        }
        //Downvote comment or post
        n if n >. 0.68 && n <. 0.8 -> {
          case !list.is_empty(state.feed) {
            True -> {
              let post = get_random_post(state.feed)
              //check if the post has any comments to reply to
              //flip a coin to decide if to reply to the post or reply to a comment
              case flip_a_coin() && !dict.is_empty(post.comments) {
                //if the post has comments and the flip was true upvote a comment
                True -> {
                  let comments = list.flatten(dict.values(post.comments))
                  let comment = get_random_comment(comments)
                  process.send(
                    state.reddit_engine,
                    DownVoteComment(
                      post.sub_id,
                      post.id,
                      comment.parent_id,
                      comment.id,
                    ),
                  )
                  //io.println(
                  //"User " <> state.username <> " down voted a comment.",
                  //)
                }
                //if the post has comments and the flip was false upvote a post
                False -> {
                  process.send(
                    state.reddit_engine,
                    DownVotePost(post.sub_id, post.id),
                  )
                  //io.println("User " <> state.username <> " down voted a post.")
                }
              }
              actor.continue(state)
            }
            False -> {
              //can't do anything so just pass
              actor.continue(state)
            }
          }
        }
        n if n >. 0.8 && n <. 0.86 -> {
          //Repost another users post
          //if the feed is empty then there's no posts to repost
          //if the user isn't subscribed to any subreddits no place to repost
          case list.is_empty(state.feed) || list.is_empty(state.subreddits) {
            True -> {
              actor.continue(state)
            }
            False -> {
              //otherwise select a random post repost
              let post = get_random_post(state.feed)
              //io.println(
              //"User "
              //<> state.username
              //<> " reposted a post by user "
              //<> post.author_username,
              //)
              //select random sub from subscribed subreddits to repost in (can be the same subreddit)
              let sub = get_random_id(state.subreddits)
              //update post's to current author and new subreddit
              let assert Some(self) = state.subject
              let post =
                Post(
                  ..post,
                  author_username: state.username,
                  author_subject: self,
                  sub_id: sub,
                )
              actor.send(state.reddit_engine, PostInSub(sub, post))
              actor.continue(state)
            }
          }
        }
        n if n >. 0.86 && n <. 0.96 -> {
          //ask reddit for a user to send a message to 
          let assert Some(self) = state.subject
          actor.send(state.reddit_engine, GetAUser(self, state.username))
          actor.continue(state)
        }
        _ -> {
          //put user to sleep for a time
          //io.println("User " <> state.username <> " is going offline.")
          //sleep time is proportional to the user frequency so hyper users don't sleep as long :P
          let time = state.frequency * 5
          actor.send(state.reddit_engine, OnlineUpdate(-1))
          process.sleep(time)
          //io.println("User " <> state.username <> " is back online.")
          actor.send(state.reddit_engine, OnlineUpdate(1))
          actor.continue(state)
        }
      }
      //select the next action for the user to take
      let assert Some(self) = state.subject
      let assert Some(generator) = state.generator
      let #(next_choice, updated_seed) = generator |> random.step(seed)
      process.send_after(
        self,
        state.frequency,
        NextAction(next_choice, updated_seed),
      )
      actor.continue(state)
    }
    JoinSub(all_subs) -> {
      //get only the subreddits the user isn't already a part of
      let filtered =
        list.filter(all_subs, fn(sub) { !list.contains(state.subreddits, sub) })

      case list.is_empty(filtered) {
        True -> {
          //already a part of all the subreddits
          actor.continue(state)
        }
        False -> {
          //get the id of one of the avilable subreddits
          let sub_index = get_random_id(filtered)
          //io.println("Choosen sub: " <> int.to_string(sub_index))
          //send self's subject so you can get updates
          let assert Some(self) = state.subject
          actor.send(state.reddit_engine, JoinSubReddit(sub_index, self))
          //update subreddits account is subscribed to
          let updated_subs = list.append(state.subreddits, [sub_index])
          //io.println(
          //"User " <> state.username <> " subscribed to a new subreddit",
          //)
          actor.continue(Account(..state, subreddits: updated_subs))
        }
      }
    }
    ReceiveDM(message) -> {
      //choose to ignore the message or reply to it
      //otherwise the messages will just ping pong forever
      let choice = int.random(2)
      case choice {
        //ignore message
        0 -> {
          actor.continue(
            Account(..state, inbox: list.append(state.inbox, [message])),
          )
        }
        //reply to message
        _ -> {
          let assert Some(self) = state.subject
          let reply =
            DirectMessage(self, {
              state.username <> " sent you a really cool message."
            })
          actor.send(message.sender, ReceiveDM(reply))
          actor.continue(
            Account(..state, inbox: list.append(state.inbox, [message])),
          )
        }
      }
    }
    SendDM(other) -> {
      let assert Some(self) = state.subject
      case other == self {
        True -> {
          //no one to message :((((
          Nil
        }
        //send message to the other user
        False -> {
          let dm =
            DirectMessage(
              self,
              state.username <> " sent you a really cool message.",
            )
          actor.send(other, ReceiveDM(dm))
          Nil
        }
      }

      //not tracking which messages the user sends
      actor.continue(state)
    }
    UpdateKarma(new_vote) -> {
      //io.println(
      //"User "
      //<> state.username
      //<> " now has  "
      //<> int.to_string(state.karma + new_vote)
      //<> " karma.",
      //)
      //value will be either 1 or -1 so just add to value (can be negative)
      actor.continue(Account(..state, karma: { state.karma + new_vote }))
    }
    AddToFeed(post) -> {
      //someone posted in a subreddit so add that to the user feed
      actor.continue(Account(..state, feed: list.append(state.feed, [post])))
    }
  }
}
