defmodule EmotheWeb.Plugs.StoreLastPath do
  @moduledoc """
  Stores the last visited GET path in the session so non-idempotent actions
  (like changing locale) can redirect back without relying on the Referer header.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [current_path: 1]

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    path = current_path(conn)

    conn =
      if path in ["/locale"] do
        conn
      else
        put_session(conn, :last_path, path)
      end

    conn
  end

  def call(conn, _opts), do: conn
end
