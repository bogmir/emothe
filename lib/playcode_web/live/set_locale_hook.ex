defmodule PlaycodeWeb.SetLocaleHook do
  @moduledoc """
  LiveView on_mount hook that sets the Gettext locale from the session.
  """
  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || Gettext.get_locale(PlaycodeWeb.Gettext)
    Gettext.put_locale(PlaycodeWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end
end
