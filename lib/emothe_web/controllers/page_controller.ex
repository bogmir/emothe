defmodule EmotheWeb.PageController do
  use EmotheWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
