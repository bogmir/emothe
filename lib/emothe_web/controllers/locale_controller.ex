defmodule EmotheWeb.LocaleController do
  use EmotheWeb, :controller

  def update(conn, %{"locale" => locale}) when locale in ~w(es en) do
    conn
    |> put_session(:locale, locale)
    |> redirect(to: redirect_back(conn))
  end

  def update(conn, _params) do
    conn
    |> redirect(to: redirect_back(conn))
  end

  defp redirect_back(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)
        uri.path || "/"

      _ ->
        "/"
    end
  end
end
