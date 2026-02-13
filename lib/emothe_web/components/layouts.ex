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
          <.link :if={Map.get(item, :to) && idx < length(@items) - 1} navigate={item.to} class="hover:text-primary">
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
  attr :active_tab, :atom, default: nil, doc: "which tab is active (:overview, :metadata, :content, :public)"

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
            Overview
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/edit"}
            class={ctx_tab_class(@active_tab == :metadata)}
          >
            Metadata
          </.link>
          <.link
            navigate={~p"/admin/plays/#{@play.id}/content"}
            class={ctx_tab_class(@active_tab == :content)}
          >
            Content
          </.link>
          <.link
            navigate={~p"/plays/#{@play.code}"}
            class={ctx_tab_class(@active_tab == :public)}
          >
            <.icon name="hero-eye-micro" class="size-3.5" /> Public
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
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
