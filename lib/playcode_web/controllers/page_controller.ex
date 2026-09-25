defmodule PlaycodeWeb.PageController do
  use PlaycodeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
