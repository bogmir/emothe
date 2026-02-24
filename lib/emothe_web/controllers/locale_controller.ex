defmodule EmotheWeb.LocaleController do
  use EmotheWeb, :controller

  def update(conn, %{"locale" => locale} = params) when locale in ~w(es en) do
    conn
    |> put_session(:locale, locale)
    |> redirect(to: safe_return_to(params))
  end

  def update(conn, params) do
    conn
    |> redirect(to: safe_return_to(params))
  end

  defp safe_return_to(%{"return_to" => "/" <> _ = path}), do: path
  defp safe_return_to(_), do: "/"
end
