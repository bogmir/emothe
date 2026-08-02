defmodule EmotheWeb.CurrentPathHook do
  @moduledoc """
  Assigns `:current_path` so the admin sidebar can mark the active entry.
  """
  import Phoenix.Component
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     attach_hook(socket, :current_path, :handle_params, fn _params, uri, socket ->
       {:cont, assign(socket, :current_path, URI.parse(uri).path)}
     end)}
  end
end
