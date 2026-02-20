defmodule EmotheWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use EmotheWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders breadcrumb navigation.

  Each item is a map with `:label` and optional `:to` (path for link).
  The last item is rendered as plain text (current page).

  ## Examples

      <.breadcrumbs items={[%{label: "Admin", to: "/admin/plays"}, %{label: "La Virginie"}]} />
  """
  attr :items, :list, required: true, doc: "list of %{label, to} maps"

  def breadcrumbs(assigns) do
    ~H"""
    <nav :if={@items != []} aria-label="Breadcrumb" class="text-sm breadcrumbs py-0">
      <ul>
        <li :for={{item, idx} <- Enum.with_index(@items)}>
          <.link
            :if={Map.get(item, :to) && idx < length(@items) - 1}
            navigate={item.to}
            class="hover:text-primary"
          >
            {item.label}
          </.link>
          <span :if={!Map.get(item, :to) || idx == length(@items) - 1} class="text-base-content/70">
            {item.label}
          </span>
        </li>
      </ul>
    </nav>
    """
  end

  @doc """
  Renders a play context bar for admin play pages.

  Shows the play title, code, author and quick-nav tabs to jump between
  different views of the same play.

  ## Examples

      <.play_context_bar play={@play} active_tab={:content} />
  """
  attr :play, :map, required: true, doc: "the play struct"

  attr :active_tab, :atom,
    default: nil,
    doc: "which tab is active (:overview, :metadata, :content, :public)"

  def play_context_bar(assigns) do
    ~H"""
    <div class="border-b border-base-300 bg-base-100/80 backdrop-blur-sm">
      <div class="mx-auto max-w-7xl px-4 flex items-center justify-between gap-4 py-2">
        <div class="min-w-0 flex-1">
          <h2 class="text-sm font-semibold text-base-content truncate">{@play.title}</h2>
          <p class="text-xs text-base-content/60 truncate">
            {if @play.author_name, do: "#{@play.author_name} — "}{@play.code}
          </p>
        </div>
        <nav class="flex gap-1 flex-shrink-0">
          <.link
            navigate={~p"/admin/plays/#{@play.id}"}
            class={ctx_tab_class(@active_tab == :overview)}
          >
            {gettext("Overview")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/edit"}
            class={ctx_tab_class(@active_tab == :metadata)}
          >
            {gettext("Metadata")}
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/content"}
            class={ctx_tab_class(@active_tab == :content)}
          >
            {gettext("Content")}
          </.link>
          <.link
            navigate={~p"/plays/#{@play.code}"}
            class={ctx_tab_class(@active_tab == :public)}
          >
            <.icon name="hero-eye-micro" class="size-3.5" /> {gettext("Public")}
          </.link>
        </nav>
      </div>
    </div>
    """
  end

  defp ctx_tab_class(true) do
    "inline-flex items-center gap-1 rounded-md px-2.5 py-1.5 text-xs font-medium bg-primary/10 text-primary"
  end

  defp ctx_tab_class(false) do
    "inline-flex items-center gap-1 rounded-md px-2.5 py-1.5 text-xs font-medium text-base-content/70 hover:bg-base-200 hover:text-base-content transition-colors"
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <button
      class="btn btn-ghost btn-circle btn-sm swap swap-rotate"
      phx-click={JS.dispatch("phx:toggle-theme")}
      aria-label="Toggle theme"
    >
      <.icon name="hero-sun-micro" class="size-5 [[data-theme=dark]_&]:hidden" />
      <.icon name="hero-moon-micro" class="size-5 hidden [[data-theme=dark]_&]:block" />
    </button>
    """
  end

  @doc """
  Language toggle component (ES/EN).
  """
  attr :locale, :string, default: "es"

  def locale_toggle(assigns) do
    ~H"""
    <div class="flex items-center gap-0.5">
      <form :if={@locale != "es"} action="/locale" method="post" class="inline">
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="locale" value="es" />
        <button type="submit" class="btn btn-ghost btn-xs font-bold">ES</button>
      </form>
      <span :if={@locale == "es"} class="btn btn-ghost btn-xs font-bold btn-active">ES</span>

      <form :if={@locale != "en"} action="/locale" method="post" class="inline">
        <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
        <input type="hidden" name="locale" value="en" />
        <button type="submit" class="btn btn-ghost btn-xs font-bold">EN</button>
      </form>
      <span :if={@locale == "en"} class="btn btn-ghost btn-xs font-bold btn-active">EN</span>
    </div>
    """
  end
end
