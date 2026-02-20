defmodule EmotheWeb.Plugs.SetLocale do
  @moduledoc """
  Reads the user's preferred locale from the session and sets it for Gettext.
  Falls back to the configured default locale ("es").
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = get_session(conn, :locale) || Gettext.get_locale(EmotheWeb.Gettext)
    Gettext.put_locale(EmotheWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end
end
