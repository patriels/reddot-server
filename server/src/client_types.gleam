pub type MyMessage {
  Broadcast(String)
}

pub type DirectMessage {
  DirectMessage(sender: String, message: String)
}

pub type Post {
  Post(
    id: Int,
    sub_id: Int,
    title: String,
    author_username: String,
    content: String,
    comments: List(Comment),
    up_votes: Int,
    down_votes: Int,
  )
}

pub type Comment {
  Comment(
    id: Int,
    post_id: Int,
    sub_id: Int,
    content: String,
    author_username: String,
    //not zero if a reply to another comment
    parent_id: Int,
    up_votes: Int,
    down_votes: Int,
  )
}

pub type Account {
  Account(
    username: String,
    feed: List(Post),
    karma: Int,
    inbox: List(DirectMessage),
    display: String,
  )
}

pub type InputMessage {
  DisplayMessage(msg: String)
  //Quit
}
