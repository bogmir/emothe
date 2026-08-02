defmodule EmotheWeb.DemoUIHTML do
  @moduledoc false
  use EmotheWeb, :html

  import EmotheWeb.Components.StatisticsPanel
  import EmotheWeb.Layouts, only: [user_menu: 1, admin_sidebar: 1, play_context_bar: 1]

  embed_templates "demo_ui_html/*"
end
