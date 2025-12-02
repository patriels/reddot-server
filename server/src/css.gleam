import gleam/string

pub fn get_css() -> String {
  let header = [
    "<head>",
    "<meta name='viewport' content='width=device-width, initial-scale=1'>",
    "<link rel='stylesheet' href='https://www.w3schools.com/w3css/5/w3.css'>",
    "<link rel='stylesheet' href='https://fonts.googleapis.com/css?family=Raleway'>",
    "<style> .button-link {
        background: none!important;
        border: none;
        padding-left: 5px
        padding: 0!important;
        /*optional*/
        font-family: arial, sans-serif;
        /*input has OS specific font-family*/
        color: #069;
        text-decoration: underline;
        cursor: pointer;
      }
    </style>",
    "</head>",
  ]

  string.concat(header)
}
